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
      redirect_to completion_path
    end
  end

  def create
    @nomikai.with_lock do
      unless @nomikai.collecting_swipes?
        return redirect_to completion_path, status: :see_other
      end

      if @participant.reload.completed_at.present?
        return redirect_to completion_path, status: :see_other
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
      if @nomikai.collecting_swipes? && @nomikai.nomikai_vibe_cards.exists? &&
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
      redirect_to completion_path, status: :see_other
    elsif @nomikai.collecting_swipes?
      redirect_to participant_swipes_path(@participant.token), status: :see_other
    else
      redirect_to completion_path, status: :see_other
    end
  end

  private

  def set_participant
    @participant = Participant.find_by!(
      token: params[:participant_token]
    )

    @nomikai = @participant.nomikai
    if @participant.host?
      return head :forbidden unless current_user && current_user.id == @nomikai.user_id
    elsif current_user && current_user.id == @nomikai.user_id
      return redirect_to nomikai_path(@nomikai), status: :see_other
    end
  end

  def completion_path
    @participant.host? ? nomikai_path(@nomikai) : participant_path(@participant.token)
  end

  def ensure_open
    return if @nomikai.collecting_swipes?

    redirect_to completion_path, status: :see_other
  end
end
