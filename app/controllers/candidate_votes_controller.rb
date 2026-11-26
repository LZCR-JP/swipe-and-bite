class CandidateVotesController < ApplicationController
  before_action :set_participant
  before_action :ensure_feedback_open

  def create
    recorder = CandidateVoteRecorder.new(
      participant: @participant,
      candidate_id: params[:candidate_id],
      approved: params[:approved]
    )
    recorder.call

    redirect_to participant_path(@participant.token),
                status: :see_other,
                notice: recorder.notice
  rescue CandidateVoteRecorder::InvalidApproval
    head :unprocessable_entity
  end

  private

  def set_participant
    @participant = Participant.find_by!(
      token: params[:participant_token]
    )
    @nomikai = @participant.nomikai
  end

  def ensure_feedback_open
    return if @nomikai.restaurant_feedback_open?

    render plain: "Restaurant feedback is not open for this event.",
           status: :forbidden
  end
end
