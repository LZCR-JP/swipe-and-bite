class CandidateVotesController < ApplicationController
  before_action :set_participant
  before_action :ensure_feedback_open

  def create
    recorder = CandidateVoteRecorder.new(
      participant: @participant,
      candidate_id: params[:candidate_id],
      approved: params[:approved],
      decision_round: params[:decision_round]
    )
    recorder.call

    redirect_to participant_path(@participant.token),
                status: :see_other,
                notice: recorder.notice
  rescue CandidateVoteRecorder::InvalidApproval
    head :unprocessable_entity
  rescue CandidateVoteRecorder::VotingClosed
    redirect_to participant_path(@participant.token), status: :see_other, alert: "This vote is no longer available."
  end

  private

  def set_participant
    @participant = Participant.find_by!(
      token: params[:participant_token]
    )
    @nomikai = @participant.nomikai
    return head :forbidden if @participant.host? || (current_user && current_user.id == @nomikai.user_id)
  end

  def ensure_feedback_open
    return if @nomikai.restaurant_feedback_open?

    render plain: "Restaurant feedback is not open for this event.",
           status: :forbidden
  end
end
