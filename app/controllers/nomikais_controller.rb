class NomikaisController < ApplicationController
  before_action :authenticate_user!, except: %i[index participant_updates confirmation_photo]
  before_action :set_nomikai, only: %i[show destroy close progress recommendations recommendations_landing select_candidate candidate_decision start_host_swipes]

  def index
    @ongoing_gathering = current_user&.nomikais&.ongoing&.includes(:participants)&.first
    @nomikais = current_user ? current_user.nomikais.finished.includes(candidates: :venue).order(Arel.sql("COALESCE(confirmed_at, matches_found_at) DESC")) : Nomikai.none
    @joined_active, @joined_history = joined_plans.entries.partition { |person| person.nomikai.ongoing? }
    ActiveRecord::Associations::Preloader.new(records: @joined_history.map(&:nomikai), associations: { candidates: :venue }).call
  end

  def participant_updates
    expires_now
    updates = joined_plans.entries.filter_map do |person|
      state = joined_plans.status(person)
      next unless %w[vote confirmed].include?(state)

      plan = person.nomikai
      update = { key: "#{person.id}:#{plan.decision_round}:#{state}",
        state: state, title: helpers.plan_title(plan), path: participant_path(person.token) }
      update.merge!(confirmation_update(plan)) if state == "confirmed"
      update
    end
    if current_user
      current_user.nomikais.where(decision_state: "confirmed").where(confirmed_at: 15.minutes.ago..Time.current).find_each do |plan|
        updates << { key: "host:#{current_user.id}:#{plan.id}:#{plan.decision_round}:confirmed",
          state: "confirmed", title: helpers.plan_title(plan), path: nomikai_path(plan) }.merge(confirmation_update(plan))
      end
    end
    render json: { signature: joined_plans.signature, updates: updates }
  end

  def confirmation_photo
    expires_now
    plan = current_user&.nomikais&.find_by(id: params[:id]) || joined_plans.entries.find { |person| person.nomikai_id.to_s == params[:id].to_s }&.nomikai
    return head :not_found unless plan&.confirmed?
    venue = plan.candidates.find_by(selected: true)&.venue
    return head :not_found unless venue

    details = GooglePlaceDetails.new(venue.google_place_id, include_photo: true).call || {}
    photo_name = details[:photo_name]
    return render json: {} if photo_name.blank?

    token = Rails.application.message_verifier(:restaurant_photo).generate(photo_name, expires_in: 5.minutes, purpose: :confirmed_restaurant_photo)
    render json: { photo_url: restaurant_photo_path(token: token), authors: details[:photo_attributions] || [] }
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

  def start_host_swipes
    participant = nil
    @nomikai.with_lock do
      if @nomikai.collecting_swipes?
        participant = @nomikai.participants.find_or_create_by!(user: current_user) do |person|
          person.nickname = current_user.name.to_s.truncate(30)
        end
      end
    end
    if participant && participant.completed_at.nil?
      redirect_to participant_swipes_path(participant.token), status: :see_other
    else
      redirect_to nomikai_path(@nomikai), status: :see_other
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
    return redirect_to nomikai_path(@nomikai) unless @nomikai.collecting_swipes?
  end

  def update
    @nomikai = current_user.nomikais.find(params[:id])
    return redirect_to nomikai_path(@nomikai), status: :see_other unless @nomikai.collecting_swipes?

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
    people = @nomikai.participants.order(:created_at).to_a
    completed = people.count { |person| person.completed_at.present? }
    payload = {
      ongoing: @nomikai.ongoing?,
      joined: people.size,
      completed: completed,
      total: @nomikai.group_size,
      matches_ready: @nomikai.matches_ready?,
      decision_state: @nomikai.decision_state,
      signature: @nomikai.decision_signature
    }
    if params[:view] == "lobby"
      payload[:guest_joined] = people.count { |person| !person.host? }
      payload[:guest_total] = [@nomikai.group_size - 1, 0].max
      payload[:ongoing] = @nomikai.collecting_swipes?
    end
    if params[:view] == "lobby" && payload[:ongoing]
      signature = [people.size, completed, @nomikai.group_size].join(":")
      payload[:signature] = signature
      if params[:signature] != signature
        payload[:html] = render_to_string(partial: "nomikais/crew_progress", locals: { nomikai: @nomikai, people: people }, formats: [:html])
      end
    end
    render json: payload
  end

  def recommendations
    unless @nomikai.ongoing? && @nomikai.decision_state != "voting" && (@nomikai.matches_ready? || @nomikai.participants.where.not(completed_at: nil).exists?)
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
      cancelled = !@nomikai.ongoing? || @nomikai.decision_state == "voting"
      if !cancelled && @places.any? && !@nomikai.matches_ready?
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
  rescue GooglePlacesSearch::Unavailable => error
    Rails.logger.warn("Restaurant recommendations unavailable for nomikai #{@nomikai.id}: #{error.message}")
    @places = []
    @used_fallback = false
    @reshuffled = params[:continuation].present?
    @search_error = true
    render :recommendations, status: :service_unavailable
  end

  def recommendations_landing
    redirect_to nomikai_path(@nomikai),
                notice: "Search results are temporary. Run a new search to refresh them."
  end

  def candidate_decision
    @candidate = @nomikai.candidates.includes(:venue).find(params[:candidate_id])
    return redirect_to nomikai_path(@nomikai) unless @nomikai.ongoing? && @nomikai.matches_ready?
    if @nomikai.decision_state == "voting" && (!@candidate.selected? || !@nomikai.all_votes_received?)
      redirect_to nomikai_path(@nomikai), alert: "Wait for everyone to vote."
    end
  end

  def select_candidate
    candidate = @nomikai.candidates.find(params[:candidate_id])
    mode = params[:decision]
    return head :unprocessable_entity unless %w[confirm vote].include?(mode)

    @nomikai.with_lock do
      unless @nomikai.ongoing? && @nomikai.matches_ready?
        return redirect_to nomikai_path(@nomikai), status: :see_other
      end
      if @nomikai.decision_state == "voting" && (mode != "confirm" || !candidate.reload.selected? || !@nomikai.all_votes_received?)
        return redirect_to nomikai_path(@nomikai), status: :see_other, alert: "Wait for everyone to vote before confirming."
      end
      if mode == "vote" && !@nomikai.voting_participants.exists?
        return redirect_to candidate_decision_nomikai_path(@nomikai, candidate_id: candidate.id), status: :see_other, alert: "No other participants to ask. Confirm the restaurant yourself."
      end
      @nomikai.candidates.where.not(id: candidate.id).update_all(selected: false)
      candidate.update!(selected: true)
      candidate.candidate_votes.delete_all if mode == "vote"
      @nomikai.decision_round += 1
      if mode == "confirm"
        @nomikai.confirm_restaurant!
      else
        @nomikai.update!(decision_state: "voting")
      end
    end
    redirect_to nomikai_path(@nomikai), status: :see_other
  end

  private

  def confirmation_update(plan)
    return {} unless plan.confirmed_at && plan.confirmed_at >= 15.minutes.ago
    venue = plan.candidates.find_by(selected: true)&.venue
    return {} unless venue
    { restaurant: venue.name.presence || "Restaurant", address: venue.formatted_address,
      photo_endpoint: confirmation_photo_nomikai_path(plan, format: :json) }
  end

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
