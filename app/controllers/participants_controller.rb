class ParticipantsController < ApplicationController
  # Code URLs are guessable in principle, so throttle lookups the same way /join does.
  rate_limit to: 10, within: 1.minute, only: %i[new create], if: -> { params[:code].present? },
             with: -> { redirect_to join_code_path, alert: "Too many attempts. Please wait a minute and try again." }

  before_action :set_entry_point, only: %i[new create]
  before_action :ensure_open, only: %i[new create]

  def new
    @participant = existing_participant
    return redirect_to resume_path(@participant) if @participant
  end

  def create
    @nomikai.with_lock do
      if @nomikai.accepting_participants?
        @invitation&.reload
        if @invitation&.accepted? && @invitation.participant
          @participant = @invitation.participant
        elsif !@invitation&.revoked?
          @participant = existing_participant
        end
        unless @participant || @invitation&.revoked?
          @participant = @nomikai.participants.create!(
            nickname: current_user ? current_user.name.to_s.strip.truncate(30) : next_guest_name,
            user: current_user,
            invitation: @invitation
          )
        end
      end
    end
    unless @participant
      return render_unavailable("This event is no longer accepting new teammates.", status: :forbidden)
    end
    remember_guest(@participant) unless current_user
    redirect_to resume_path(@participant), status: :see_other
  end

  def show
    @participant = Participant.find_by!(token: params[:token])
    @nomikai = @participant.nomikai
    @selected_candidate = @nomikai.candidates
                                  .includes(:venue)
                                  .find_by(selected: true)

    @candidate_vote = if @selected_candidate
                        @participant.candidate_votes.find_by(
                          candidate: @selected_candidate
                        )
                      end
  end

  private

  # A teammate can arrive via a personal email invite, a join code, or the share link.
  def set_entry_point
    if params[:invite_token]
      set_from_invitation
    elsif params[:code]
      set_from_join_code
    else
      @nomikai = Nomikai.find_by!(share_token: params[:share_token])
      @join_path = join_path(@nomikai.share_token)
    end
  end

  def set_from_invitation
    @invitation = Invitation.find_by(token: params[:invite_token])

    if @invitation.nil? || @invitation.revoked?
      return render_unavailable(
        "This invite link is no longer valid. Ask your host to send a new one, or join with a code.",
        status: :not_found
      )
    end

    if @invitation.accepted? && @invitation.participant
      return redirect_to resume_path(@invitation.participant)
    end

    @nomikai = @invitation.nomikai
    @join_path = invite_path(@invitation.token)
  end

  def set_from_join_code
    @nomikai = Nomikai.find_by_join_code(params[:code])

    unless @nomikai
      return redirect_to join_code_path,
                         alert: "That code isn't valid anymore. Double-check it with your host."
    end

    @join_path = join_with_code_path(@nomikai.formatted_join_code)
  end

  def ensure_open
    return if @nomikai.accepting_participants?

    render_unavailable("This event is no longer accepting new teammates.", status: :forbidden)
  end

  def render_unavailable(message, status:)
    @message = message
    render :unavailable, status: status
  end

  def existing_participant
    if current_user
      @nomikai.participants.find_by(user_id: current_user.id)
    else
      token = (session[:guest_participants] || {})[@nomikai.id.to_s]
      @nomikai.participants.find_by(token: token, user_id: nil) if token.present?
    end
  end

  def remember_guest(participant)
    entries = (session[:guest_participants] || {}).dup
    entries.delete(@nomikai.id.to_s)
    entries[@nomikai.id.to_s] = participant.token
    session[:guest_participants] = entries.to_a.last(10).to_h
  end

  # Called inside the gathering's row lock, so two guests get different names.
  def next_guest_name
    used = @nomikai.participants.pluck(:nickname).filter_map do |name|
      match = name.to_s.match(/\AGuest (\d+)\z/i)
      match[1].to_i if match
    end
    "Guest #{(used.max || 0) + 1}"
  end

  def resume_path(participant)
    if participant.completed_at.present? || !participant.nomikai.ongoing?
      participant_path(participant.token)
    else
      participant_swipes_path(participant.token)
    end
  end
end
