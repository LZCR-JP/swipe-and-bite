require "test_helper"

class InvitationsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @host = create_host
    @nomikai = create_nomikai(user: @host)
    sign_in @host
  end

  test "host can send email invites" do
    assert_enqueued_emails 1 do
      post nomikai_invitations_path(@nomikai), params: { emails: "aiko@example.com" }
    end

    assert_redirected_to nomikai_path(@nomikai, tab: "email", anchor: "invite")
    assert @nomikai.invitations.find_by(email: "aiko@example.com").pending?
  end

  test "other users cannot invite to someone else's event" do
    sign_in create_host(email: "other@example.com")

    post nomikai_invitations_path(@nomikai), params: { emails: "aiko@example.com" }
    assert_response :not_found
  end

  test "cannot invite to a closed event" do
    @nomikai.update!(status: "closed")

    assert_no_enqueued_emails do
      post nomikai_invitations_path(@nomikai), params: { emails: "aiko@example.com" }
    end
    assert_equal "This event is no longer accepting new teammates.", flash[:invite_alert]
  end

  test "revoking an invite disables its link" do
    invitation = @nomikai.invitations.create!(email: "aiko@example.com")

    delete nomikai_invitation_path(@nomikai, invitation)
    assert invitation.reload.revoked?

    get invite_path(invitation.token)
    assert_response :not_found
  end

  test "resend is throttled" do
    invitation = @nomikai.invitations.create!(email: "aiko@example.com", sent_at: Time.current)

    assert_no_enqueued_emails do
      post resend_nomikai_invitation_path(@nomikai, invitation)
    end
    assert_match "wait a minute", flash[:invite_alert]
  end

  test "joining through an invite link accepts the invite" do
    invitation = @nomikai.invitations.create!(email: "aiko@example.com")
    sign_out @host

    post invite_path(invitation.token), params: { participant: { nickname: "Aiko", budget_max: 4000 } }

    invitation.reload
    assert invitation.accepted?
    assert_redirected_to participant_swipes_path(invitation.participant.token)

    get invite_path(invitation.token)
    assert_redirected_to participant_swipes_path(invitation.participant.token)
  end

  test "show page renders the invite card" do
    @nomikai.invitations.create!(email: "aiko@example.com", sent_at: Time.current)

    get nomikai_path(@nomikai)
    assert_response :success
    assert_match @nomikai.formatted_join_code, response.body
    assert_match "aiko@example.com", response.body
  end
end
