class CandidateVotesController < ApplicationController
  before_action :set_participant
  before_action :ensure_open

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

  def ensure_open
    return if @nomikai.status == "open"

    render plain: "This nomikai is closed.",
           status: :forbidden
  end
end
