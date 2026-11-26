class CandidateVoteRecorder
  class InvalidApproval < StandardError; end

  def initialize(participant:, candidate_id:, approved:)
    @participant = participant
    @candidate_id = candidate_id
    @approved = approved
  end

  def call
    approval = approved_value

    candidate = @participant.nomikai.candidates.find_by!(
      id: @candidate_id,
      selected: true
    )

    @vote = @participant.candidate_votes.find_or_initialize_by(
      candidate: candidate
    )
    @vote.update!(approved: approval)
    @vote
  end

  def notice
    if @vote.approved?
      "You approved the selected restaurant."
    else
      "You asked for another option."
    end
  end

  private

  def approved_value
    case @approved.to_s
    when "true"
      true
    when "false"
      false
    else
      raise InvalidApproval
    end
  end
end
