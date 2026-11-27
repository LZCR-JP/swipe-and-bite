class NomikaisController < ApplicationController
  before_action :authenticate_user!
  before_action :set_nomikai, only: %i[show destroy close progress start_swipes recommendations recommendations_landing select_candidate]

  def index
    @ongoing_gathering = current_user.nomikais.ongoing.includes(:participants).first
    @nomikais = current_user.nomikais.finished.order(matches_found_at: :desc)
  end

  def show
    if !@nomikai.ongoing? && !@nomikai.finished?
      redirect_to nomikais_path, status: :see_other
      return
    end
    @participants = @nomikai.participants.order(:created_at)
    @selected_candidate = @nomikai.candidates
                                   .includes(:venue, :candidate_votes)
                                   .find_by(selected: true)
    @selected_restaurant_name = @selected_candidate&.venue&.name

    if @selected_candidate && (@selected_candidate.venue.name.blank? || @selected_candidate.venue.primary_type.blank?)
      venue = @selected_candidate.venue
      details = GooglePlaceDetails.new(venue.google_place_id).call || {}
      venue.assign_attributes(
        name: venue.name.presence || details[:name],
        primary_type: venue.primary_type.presence || details[:primary_type],
        formatted_address: venue.formatted_address.presence || details[:formatted_address],
        google_maps_uri: venue.google_maps_uri.presence || details[:google_maps_uri],
        price_level: venue.price_level.presence || details[:price_level],
        rating: venue.rating.presence || details[:rating]
      )
      venue.save! if venue.changed?
      @selected_restaurant_name = venue.name
    end
  end

  def new
    @ongoing_gathering = current_user.nomikais.ongoing.includes(:participants).first
    @nomikai = Nomikai.new
  end

  def create
    current_user.with_lock do
      @ongoing_gathering = current_user.nomikais.ongoing.first
      unless @ongoing_gathering
        @nomikai = current_user.nomikais.build(nomikai_params)
        VibeCardSelector.new(@nomikai).call if @nomikai.save
      end
    end

    if @ongoing_gathering
      redirect_to nomikai_path(@ongoing_gathering), status: :see_other,
                  alert: "Finish or cancel your ongoing gathering first."
    elsif @nomikai.persisted?
      redirect_to nomikai_path(@nomikai), status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @nomikai = current_user.nomikais.find(params[:id])
  end

  def update
    @nomikai = current_user.nomikais.find(params[:id])

    if @nomikai.update(nomikai_params)
      redirect_to nomikai_path(@nomikai),
                  notice: "Gathering successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @nomikai.destroy!

    redirect_to nomikais_path,
                status: :see_other,
                notice: "Nomikai deleted."
  end

  def close
    cancelled = false
    @nomikai.with_lock do
      if @nomikai.ongoing?
        @nomikai.update!(status: "closed")
        cancelled = true
      end
    end

    if cancelled
      redirect_to new_nomikai_path, status: :see_other, notice: "Gathering cancelled."
    else
      redirect_to nomikais_path, status: :see_other
    end
  end

  def progress
    expires_now
    render json: {
      ongoing: @nomikai.ongoing?,
      joined: @nomikai.participants.count,
      completed: @nomikai.participants.where.not(completed_at: nil).count,
      total: @nomikai.group_size
    }
  end

  def start_swipes
    participant = nil

    @nomikai.with_lock do
      if @nomikai.ongoing?
        participant = @nomikai.participants.find_or_create_by!(user: current_user) do |record|
          record.nickname = current_user.name.to_s.strip.truncate(30)
        end
      end
    end

    if participant&.completed_at.present? || !@nomikai.ongoing?
      redirect_to nomikai_path(@nomikai), status: :see_other
    else
      redirect_to participant_swipes_path(participant.token), status: :see_other
    end
  end

  def recommendations
    unless @nomikai.finished? || (@nomikai.ongoing? && @nomikai.participants.where.not(completed_at: nil).exists?)
      redirect_to nomikai_path(@nomikai), alert: "Complete at least one response before searching.", status: :see_other
      return
    end
    expires_now
    verifier = Rails.application.message_verifier(:restaurant_matches)
    purpose = "restaurant_matches:#{current_user.id}:#{@nomikai.id}"

    if params[:continuation].present?
      continuation = verifier.verified(params[:continuation].to_s, purpose: purpose)
      unless continuation.is_a?(Hash)
        redirect_to nomikai_path(@nomikai), alert: "Search expired. Please start a new search.", status: :see_other
        return
      end
    end

    service = GooglePlacesSearch.new(@nomikai, detailed: true, continuation: continuation)
    @places = service.call
    cancelled = false
    @nomikai.with_lock do
      cancelled = !@nomikai.ongoing? && !@nomikai.finished?
      if !cancelled && @places.any? && !@nomikai.finished?
        @nomikai.update!(matches_found_at: Time.current)
      end
    end
    if cancelled
      redirect_to new_nomikai_path, status: :see_other, alert: "This gathering was cancelled."
      return
    end
    @used_fallback = service.used_fallback
    @reshuffled = continuation.present?
    if service.next_state
      @next_matches_token = verifier.generate(service.next_state, purpose: purpose, expires_in: 15.minutes)
    end
  rescue GooglePlacesSearch::StaleSearch
    redirect_to nomikai_path(@nomikai), alert: "Search conditions changed. Please start a new search.", status: :see_other
  end

  def recommendations_landing
    redirect_to nomikai_path(@nomikai),
                notice: "Search results are temporary. Run a new search to refresh them."
  end

  def select_candidate
    candidate = @nomikai.candidates.find(params[:candidate_id])

    @nomikai.with_lock do
      @nomikai.candidates.where.not(id: candidate.id).update_all(selected: false)
      candidate.update!(selected: true)
    end

    redirect_to nomikai_path(@nomikai),
                status: :see_other,
                notice: "Restaurant selected."
  end

  private

  def set_nomikai
    @nomikai = current_user.nomikais.find(params[:id])
  end

  def nomikai_params
    params.require(:nomikai).permit(
      :name,
      :area,
      :latitude,
      :longitude,
      :meal_period,
      :group_size,
      :budget_per_person
    )
  end
end
