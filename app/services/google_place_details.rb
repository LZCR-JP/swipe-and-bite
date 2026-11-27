require "json"
require "net/http"
require "uri"

class GooglePlaceDetails
  BASE_URL = "https://places.googleapis.com/v1/places"

  def initialize(place_id, include_photo: false, include_price_range: false)
    @place_id = place_id
    @include_photo = include_photo
    @include_price_range = include_price_range
  end

  def call
    return if api_key.blank?

    response = get(build_request)
    return log_failure(response) unless response.is_a?(Net::HTTPSuccess)

    place = JSON.parse(response.body)
    {
      name: place.dig("displayName", "text"),
      primary_type: place.dig("primaryTypeDisplayName", "text"),
      formatted_address: place["formattedAddress"],
      google_maps_uri: place["googleMapsUri"],
      price_level: place["priceLevel"],
      rating: place["rating"],
      price_range: place["priceRange"],
      attributions: place["attributions"],
      photo_name: place["photos"]&.first&.dig("name"),
      photo_attributions: place["photos"]&.first&.dig("authorAttributions")
    }.compact
  rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError,
         IOError, SystemCallError, OpenSSL::SSL::SSLError => e
    Rails.logger.warn("Google Place Details lookup failed: #{e.class}")
    nil
  end

  private

  def api_key
    ENV.fetch("GOOGLE_MAPS_API_KEY", nil)
  end

  def uri
    @uri ||= begin
      request_uri = URI("#{BASE_URL}/#{URI::DEFAULT_PARSER.escape(@place_id)}")
      request_uri.query = URI.encode_www_form(languageCode: "en")
      request_uri
    end
  end

  def build_request
    request = Net::HTTP::Get.new(uri)
    request["X-Goog-Api-Key"] = api_key
    request["X-Goog-FieldMask"] = if @include_price_range
                                    fields = %w[displayName formattedAddress googleMapsUri priceRange attributions]
                                    fields << "photos" if @include_photo
                                    fields.join(",")
                                  elsif @include_photo
                                    "photos"
                                  else
                                    "displayName,primaryTypeDisplayName,formattedAddress,googleMapsUri,priceLevel,rating"
                                  end
    request
  end

  def get(request)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
      http.request(request)
    end
  end

  def log_failure(response)
    Rails.logger.warn("Google Place Details failed with HTTP #{response.code}")
    nil
  end
end
