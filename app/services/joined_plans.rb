# Membership is based on the signed-in account or this browser's guest session.
# Never include the host's own swipe record in the participant list.
class JoinedPlans
  def initialize(user:, guest_tokens:)
    @user = user
    @guest_tokens = guest_tokens
  end

  def entries
    @entries ||= begin
      scope = if @user
                Participant.where(user_id: @user.id)
              else
                Participant.where(user_id: nil, token: @guest_tokens)
              end
      scope.joins(:nomikai)
           .where("participants.user_id IS NULL OR participants.user_id != nomikais.user_id")
           .merge(Nomikai.ongoing.or(Nomikai.where(decision_state: "confirmed")))
           .includes(:nomikai).order(created_at: :desc).to_a
    end
  end

  def status(participant)
    @statuses ||= {}
    @statuses[participant.id] ||= determine_status(participant)
  end

  def signature
    entries.map { |person| [person.id, person.nomikai.decision_round, status(person)].join(":") }.join("|")
  end

  private

  def determine_status(participant)
    plan = participant.nomikai
    return "confirmed" if plan.confirmed?
    if plan.decision_state == "voting"
      candidate = plan.candidates.find_by(selected: true)
      if candidate
        return "vote" unless participant.candidate_votes.exists?(candidate_id: candidate.id)
        return plan.all_votes_received? ? "awaiting_confirmation" : "voted"
      end
    end
    return "review" if plan.matches_ready?
    participant.completed_at.present? ? "waiting" : "swipe"
  end

end
