class SwipesController < ApplicationController
  before_action :set_participant
  before_action :ensure_open

  def index
    selector = VibeCardSelector.new(@nomikai)
    selector.call
    @show_card_fallback_notice = selector.fallback?

    @cards = @nomikai.nomikai_vibe_cards.order(:position)
    @total_cards = @cards.count
    @completed_count = @participant.swipes.count

    return render plain: "No matching vibe cards available." if @total_cards.zero?

    @current_card = @cards.where.not(
      id: @participant.swipes.select(:nomikai_vibe_card_id)
    ).first

    if @current_card.nil? && @participant.completed_at.present?
      redirect_to swipe_return_path, status: :see_other
    end
  end

  def create
    @nomikai.with_lock do
      unless @nomikai.ongoing?
        return redirect_to swipe_return_path, status: :see_other
      end

      if @participant.reload.completed_at.present?
        return redirect_to swipe_return_path, status: :see_other
      end

      card = @nomikai.nomikai_vibe_cards.find(
        params[:nomikai_vibe_card_id]
      )

      return head :unprocessable_entity unless ["true", "false"].include?(params[:liked].to_s)

      swipe = @participant.swipes.find_or_initialize_by(
        nomikai_vibe_card: card
      )

      swipe.liked = params[:liked] == "true"
      swipe.save!

      # The last swipe is not completion: dietary preferences must be submitted.
    end

    redirect_to participant_swipes_path(@participant.token),
                status: :see_other
  end

  def finish
    finished = false
    @nomikai.with_lock do
      @participant.reload
      if @nomikai.ongoing? && @nomikai.nomikai_vibe_cards.exists? &&
          !@nomikai.nomikai_vibe_cards.where.not(id: @participant.swipes.select(:nomikai_vibe_card_id)).exists?
        unless @participant.completed_at.present?
          preferences = params.fetch(:participant, ActionController::Parameters.new).permit(:non_drinker, restrictions: [])
          @participant.update!(
            restrictions: Array(preferences[:restrictions]) & Participant::DIETARY_RESTRICTIONS,
            non_drinker: ActiveModel::Type::Boolean.new.cast(preferences[:non_drinker]) == true,
            completed_at: Time.current
          )
        end
        finished = true
      end
    end
    if finished
      redirect_to swipe_return_path, status: :see_other
    elsif @nomikai.ongoing?
      redirect_to participant_swipes_path(@participant.token), status: :see_other
    else
      redirect_to swipe_return_path, status: :see_other
    end
  end

  private

  def set_participant
    @participant = Participant.find_by!(
      token: params[:participant_token]
    )

    @nomikai = @participant.nomikai
  end

  def swipe_return_path
    organizer_participant = current_user&.id == @nomikai.user_id &&
                          @participant.user_id == current_user.id
    return nomikai_path(@nomikai) if organizer_participant

    participant_path(@participant.token)
  end

  def ensure_open
    return if @nomikai.ongoing?

    redirect_to swipe_return_path, status: :see_other
  end
end
