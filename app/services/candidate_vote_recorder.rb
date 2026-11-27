class CandidateVoteRecorder
  class InvalidApproval < StandardError; end
  class VotingClosed < StandardError; end

  def initialize(participant:, candidate_id:, approved:, decision_round:)
    @participant = participant
    @candidate_id = candidate_id
    @approved = approved
    @decision_round = decision_round.to_s
  end

  def call
    approval = approved_value
    nomikai = @participant.nomikai
    nomikai.with_lock do
      raise VotingClosed unless nomikai.restaurant_feedback_open? && !@participant.host? && @decision_round == nomikai.decision_round.to_s
      candidate = nomikai.candidates.find_by!(id: @candidate_id, selected: true)
      eligible = nomikai.voting_participants
      raise VotingClosed unless eligible.exists?(@participant.id)
      @vote = @participant.candidate_votes.find_or_initialize_by(candidate: candidate)
      raise VotingClosed if @vote.persisted?
      @vote.update!(approved: approval)
      votes = candidate.candidate_votes.where(participant_id: eligible.select(:id))
      if votes.count == eligible.count && votes.where(approved: false).exists?
        nomikai.update!(decision_state: "rejected")
      end
      # Even unanimous approval is advisory. Only the host can confirm.
    end
    @vote
  end

  def notice
    @vote.approved? ? "Vote saved." : "Your feedback is saved."
  end

  private

  def approved_value
    case @approved.to_s
    when "true" then true
    when "false" then false
    else raise InvalidApproval
    end
  end
end
