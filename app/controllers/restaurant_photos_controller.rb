require "json"
require "net/http"
require "uri"

class RestaurantPhotosController < ApplicationController
  def show
    expires_now
    verifier = Rails.application.message_verifier(:restaurant_photo)
    name = verifier.verified(params[:token].to_s, purpose: :confirmed_restaurant_photo)
    name ||= verifier.verified(params[:token].to_s, purpose: :participant_restaurant_photo)
    name ||= verifier.verified(params[:token].to_s, purpose: :restaurant_photo) if user_signed_in?
    return head :not_found unless name.is_a?(String) && name.match?(%r{\Aplaces/[A-Za-z0-9_-]+/photos/[A-Za-z0-9_-]+\z})

    uri = URI("https://places.googleapis.com/v1/#{name}/media")
    uri.query = URI.encode_www_form(maxWidthPx: 480, maxHeightPx: 480, skipHttpRedirect: true)
    request = Net::HTTP::Get.new(uri)
    request["X-Goog-Api-Key"] = ENV.fetch("GOOGLE_MAPS_API_KEY")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 6) do |http|
      http.request(request)
    end
    return head :not_found unless response.is_a?(Net::HTTPSuccess)

    photo_uri = URI.parse(JSON.parse(response.body).fetch("photoUri"))
    return head :not_found unless photo_uri.is_a?(URI::HTTPS) && photo_uri.host.to_s.end_with?(".googleusercontent.com")

    redirect_to photo_uri.to_s, allow_other_host: true
  rescue KeyError, JSON::ParserError, URI::InvalidURIError, IOError, SystemCallError, SocketError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
    Rails.logger.warn("Restaurant photo unavailable: #{e.class}")
    head :not_found
  end
end
