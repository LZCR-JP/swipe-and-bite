require "test_helper"

# Existing links can still be used, even though sending new email invitations
# is no longer part of the host interface.
class LegacyInvitesTest < ActionDispatch::IntegrationTest
  setup do
    @host = create_host
    @nomikai = create_nomikai(user: @host)
  end

  test "joining through an existing invite accepts it and allows resuming" do
    invitation = @nomikai.invitations.create!(email: "aiko@example.com")

    assert_difference -> { @nomikai.participants.count }, 1 do
      post invite_path(invitation.token)
    end

    invitation.reload
    assert invitation.accepted?
    assert_equal "Guest 1", invitation.participant.nickname
    assert_redirected_to participant_swipes_path(invitation.participant.token)

    assert_no_difference -> { @nomikai.participants.count } do
      get invite_path(invitation.token)
    end
    assert_redirected_to participant_swipes_path(invitation.participant.token)
  end

  test "revoked invite links cannot be used" do
    invitation = @nomikai.invitations.create!(email: "aiko@example.com", status: "revoked")

    get invite_path(invitation.token)
    assert_response :not_found

    assert_no_difference -> { @nomikai.participants.count } do
      post invite_path(invitation.token)
    end
    assert_response :not_found
  end

  test "pending invite links cannot be used after cancellation" do
    invitation = @nomikai.invitations.create!(email: "aiko@example.com")
    @nomikai.update!(status: "closed")

    assert_no_difference -> { @nomikai.participants.count } do
      post invite_path(invitation.token)
    end
    assert_response :forbidden
    assert invitation.reload.pending?
  end

  test "existing share links still allow joining" do
    get join_path(@nomikai.share_token)
    assert_response :success
    assert_select "h1", text: "Join this plan?"

    assert_difference -> { @nomikai.participants.count }, 1 do
      post join_path(@nomikai.share_token)
    end
    assert_redirected_to participant_swipes_path(@nomikai.participants.last.token)
  end
end
