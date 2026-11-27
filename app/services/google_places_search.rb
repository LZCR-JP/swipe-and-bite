require "json"
require "net/http"
require "uri"

class GooglePlacesSearch
  ENDPOINT = URI(
    "https://places.googleapis.com/v1/places:searchText"
  )

  BASIC_FIELDS = [
    "places.id",
    "places.displayName",
    "places.formattedAddress",
    "places.googleMapsUri",
    "places.primaryType",
    "places.primaryTypeDisplayName",
    "places.businessStatus",
    "places.attributions",
    "places.photos"
  ].freeze

  DETAILED_FIELDS = [
    "places.priceLevel",
    "places.priceRange",
    "places.websiteUri"
  ].freeze

  AREA_CENTERS = {
    "shibuya"    => [35.6580, 139.7016],
    "渋谷"        => [35.6580, 139.7016],
    "shinjuku"   => [35.6909, 139.7003],
    "新宿"        => [35.6909, 139.7003],
    "roppongi"   => [35.6635, 139.7310],
    "六本木"      => [35.6635, 139.7310],
    "ginza"      => [35.6717, 139.7650],
    "銀座"        => [35.6717, 139.7650],
    "marunouchi" => [35.6812, 139.7671],
    "丸の内"      => [35.6812, 139.7671],
    "ebisu"      => [35.6467, 139.7101],
    "恵比寿"      => [35.6467, 139.7101],
    "ikebukuro"  => [35.7295, 139.7109],
    "池袋"        => [35.7295, 139.7109],
    "akasaka"    => [35.6722, 139.7360],
    "赤坂"        => [35.6722, 139.7360],
    "toranomon"  => [35.6702, 139.7498],
    "虎ノ門"      => [35.6702, 139.7498],
    "meguro"     => [35.6339, 139.7158],
    "目黒"        => [35.6339, 139.7158]
  }.freeze

  SEARCH_HALF_WIDTH_KM = 0.8
  FALLBACK_HALF_WIDTH_KM = 2.0

  DIETARY_SEARCH_TERMS = {
    "Vegetarian" => "ベジタリアン",
    "Vegan" => "ヴィーガン",
    "Halal" => "ハラール",
    "Gluten-free" => "グルテンフリー",
    "Seafood allergy" => "魚介アレルギー対応",
    "Nut allergy" => "ナッツアレルギー対応"
  }.freeze

  attr_reader :used_fallback, :next_state

  def initialize(nomikai, detailed: false, continuation: nil)
    @nomikai = nomikai
    @detailed = detailed
    @continuation = continuation
  end

  def call
    @next_state = nil
    @next_page_token = nil
    @seen_ids = []
    @page_token = nil
    @used_fallback = false
    @active_filters = search_filters

    if @continuation
      @query = @continuation.fetch("query")
      @page_token = @continuation.fetch("page_token")
      @seen_ids = @continuation.fetch("seen_ids")
      @used_fallback = @continuation.fetch("used_fallback")
      if @continuation.fetch("filters") != @active_filters.deep_stringify_keys
        raise StaleSearch, "Search conditions have changed"
      end
      @request_filters = @continuation.fetch("request_filters", @active_filters.deep_stringify_keys).deep_symbolize_keys
      places = search_places(@query)
    else
      intent = RestaurantSearchIntent.new(@nomikai)
      @query = intent.call
      @used_fallback = intent.used_fallback
      places = search_with_fallback(@query)
    end

    places = places.uniq { |place| place.fetch("id") }
                   .reject { |place| @seen_ids.include?(place.fetch("id")) }
                   .first(3)

    if @next_page_token.present?
      @next_state = {
        "query" => @query,
        "page_token" => @next_page_token,
        "seen_ids" => @seen_ids + places.map { |place| place.fetch("id") },
        "used_fallback" => @used_fallback,
        "filters" => @active_filters.deep_stringify_keys,
        "request_filters" => @request_filters.deep_stringify_keys
      }
    end

    save_candidates(places)
    candidates = candidates_by_place_id
    places.map do |place|
      present(place, candidates.fetch(place.fetch("id")))
    end
  end

  class StaleSearch < StandardError; end
  class Unavailable < StandardError; end

  private

  def search_with_fallback(query)
    broad_filters = @active_filters.except(:priceLevels)
    wider_restriction = location_restriction(FALLBACK_HALF_WIDTH_KM)
    wider_filters = wider_restriction ? broad_filters.merge(locationRestriction: wider_restriction) : broad_filters
    attempts = [
      [query, @active_filters],
      [fallback_query, broad_filters],
      [broad_query, wider_filters]
    ].uniq

    attempts.each_with_index do |(attempt_query, filters), index|
      @query = attempt_query
      @request_filters = filters
      @next_page_token = nil
      @used_fallback = true if index.positive?
      places = search_places(attempt_query)
      return places if places.any?
    end

    []
  end

  def fallback_query
    terms = [@nomikai.area == "Selected on map" ? nil : @nomikai.area]
    terms << meal_term
    terms << (@nomikai.group_size.to_i >= 6 ? "宴会" : "グループ利用")
    terms.concat(dietary_terms)
    terms << "レストラン"

    terms.compact.join(" ")
  end

  def broad_query
    terms = [@nomikai.area == "Selected on map" ? nil : @nomikai.area]
    terms << meal_term
    terms << "レストラン"
    terms.compact.join(" ")
  end

  def meal_term
    @nomikai.meal_period == "lunch" ? "ランチ" : "ディナー"
  end

  def dietary_terms
    @nomikai.participants.flat_map(&:restrictions).compact.uniq.filter_map do |restriction|
      DIETARY_SEARCH_TERMS[restriction]
    end
  end

  def field_mask
    fields = BASIC_FIELDS.dup
    fields.concat(DETAILED_FIELDS) if @detailed
    fields.push("nextPageToken").join(",")
  end

  def search_places(query)
    response = post(build_request(query))

    unless response.is_a?(Net::HTTPSuccess)
      raise Unavailable, "Google Places returned HTTP #{response.code}"
    end

    body = JSON.parse(response.body)
    @next_page_token = body["nextPageToken"]
    Array(body["places"])
  rescue Unavailable
    raise
  rescue StandardError => error
    Rails.logger.error("Google Places search failed (#{error.class})")
    raise Unavailable, "Restaurant search is temporarily unavailable"
  end

  def build_request(query)
    request = Net::HTTP::Post.new(ENDPOINT)

    request["Content-Type"] = "application/json"
    api_key = ENV["GOOGLE_MAPS_API_KEY"].presence
    raise Unavailable, "Google Places API key is missing" unless api_key

    request["X-Goog-Api-Key"] = api_key

    request["X-Goog-FieldMask"] = field_mask

    payload = (@request_filters || @active_filters || search_filters).merge(textQuery: query, pageSize: 3)
    payload[:pageToken] = @page_token if @page_token.present?
    request.body = JSON.generate(payload)
    request
  end

  def search_filters
    payload = {
      includedType: "restaurant",
      languageCode: "en",
      regionCode: "JP",
      rankPreference: "RELEVANCE"
    }
    levels = budget_price_levels
    payload[:priceLevels] = levels if levels.any?
    restriction = location_restriction
    payload[:locationRestriction] = restriction if restriction
    payload
  end

  def effective_budget
    budgets = @nomikai.participants.pluck(:budget_max)

    (budgets + [@nomikai.budget_per_person])
      .compact
      .min
  end

  def budget_price_levels
    budget = effective_budget

    return [] if budget.nil?

    case budget
    when 0..3000
      ["PRICE_LEVEL_INEXPENSIVE"]

    when 3001..6000
      [
        "PRICE_LEVEL_INEXPENSIVE",
        "PRICE_LEVEL_MODERATE"
      ]

    when 6001..10000
      [
        "PRICE_LEVEL_INEXPENSIVE",
        "PRICE_LEVEL_MODERATE",
        "PRICE_LEVEL_EXPENSIVE"
      ]

    else
      []
    end
  end

  def area_center
    if @nomikai.latitude.present? &&
       @nomikai.longitude.present?

      return [
        @nomikai.latitude.to_f,
        @nomikai.longitude.to_f
      ]
    end

    AREA_CENTERS[@nomikai.area.to_s.strip.downcase]
  end

  def location_restriction(half_width_km = SEARCH_HALF_WIDTH_KM)
    center = area_center

    unless center
      Rails.logger.warn("Search area coordinates unavailable")
      return nil
    end

    lat, lng = center

    lat_delta = half_width_km / 111.0

    lng_delta = half_width_km /
      (111.0 * Math.cos(lat * Math::PI / 180))

    {
      rectangle: {
        low: {
          latitude: lat - lat_delta,
          longitude: lng - lng_delta
        },
        high: {
          latitude: lat + lat_delta,
          longitude: lng + lng_delta
        }
      }
    }
  end

  def post(request)
    Net::HTTP.start(
      ENDPOINT.host,
      ENDPOINT.port,
      use_ssl: true,
      open_timeout: 5,
      read_timeout: 20
    ) do |http|
      http.request(request)
    end
  end

  def save_candidates(places)
    @nomikai.with_lock do
      places.each do |place|
        venue = Venue.find_or_initialize_by(google_place_id: place.fetch("id"))
        venue.assign_attributes(
          name: place.dig("displayName", "text").presence || venue.name,
          primary_type: place.dig("primaryTypeDisplayName", "text").presence || venue.primary_type,
          formatted_address: place["formattedAddress"].presence || venue.formatted_address,
          google_maps_uri: place["googleMapsUri"].presence || venue.google_maps_uri,
          price_level: place["priceLevel"].presence || venue.price_level
        )
        venue.save! if venue.new_record? || venue.changed?

        @nomikai.candidates.find_or_create_by!(
          venue: venue
        )
      end
    end
  end

  def candidates_by_place_id
    @nomikai.candidates
            .includes(:venue)
            .index_by do |candidate|
      candidate.venue.google_place_id
    end
  end

  def present(place, candidate)
    {
      candidate_id: candidate.id,
      selected: candidate.selected?,
      google_place_id: place.fetch("id"),
      name: place.dig("displayName", "text"),
      address: place["formattedAddress"],
      google_maps_uri: place["googleMapsUri"],

      cuisine: place["primaryType"],
      category: place.dig(
        "primaryTypeDisplayName", "text"
      ),

      business_status: place["businessStatus"],
      price_level: place["priceLevel"],
      price_range: place["priceRange"],

      rating: place["rating"],
      review_count: place["userRatingCount"],

      good_for_groups: place["goodForGroups"],
      outdoor_seating: place["outdoorSeating"],
      reservable: place["reservable"],

      vegetarian_food: place["servesVegetarianFood"],
      serves_dinner: place["servesDinner"],

      phone_number: place["nationalPhoneNumber"],
      website: place["websiteUri"],
      photo_name: place["photos"]&.first&.dig("name"),
      photo_attributions: place["photos"]&.first&.dig("authorAttributions") || [],
      attributions: place["attributions"]
    }
  end
end
