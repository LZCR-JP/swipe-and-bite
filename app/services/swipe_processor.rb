class SwipeProcessor
  class InvalidChoice < StandardError; end
  class ClosedNomikai < StandardError; end

  def initialize(participant:, nomikai:, card_id:, liked:)
    @participant = participant
    @nomikai = nomikai
    @card_id = card_id
    @liked = liked
  end

  def call
    @nomikai.with_lock do
      raise ClosedNomikai unless @nomikai.status == "open"

      card = @nomikai.nomikai_vibe_cards.find(@card_id)

      swipe = @participant.swipes.find_or_initialize_by(
        nomikai_vibe_card: card
      )

      swipe.liked = liked_value
      swipe.save!

      complete_participant_if_finished
    end
  end

  private

  def liked_value
    case @liked.to_s
    when "true"
      true
    when "false"
      false
    else
      raise InvalidChoice
    end
  end

  def complete_participant_if_finished
    return unless @participant.swipes.count ==
                  @nomikai.nomikai_vibe_cards.count

    @participant.update!(
      completed_at: @participant.completed_at || Time.current
    )
  end
end
