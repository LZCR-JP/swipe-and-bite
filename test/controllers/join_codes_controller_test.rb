require "test_helper"

class JoinCodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @nomikai = create_nomikai
  end

  test "shows the code entry page" do
    get join_code_path
    assert_response :success
  end

  test "valid code redirects to the participant form without exposing the share token" do
    post join_code_path, params: { code: @nomikai.join_code.downcase }

    assert_redirected_to join_with_code_path(@nomikai.formatted_join_code)
    follow_redirect!
    assert_response :success
    assert_no_match @nomikai.share_token, response.body
  end

  test "unknown code shows an error" do
    post join_code_path, params: { code: "SWIPE-ZZZZZZ" }

    assert_response :unprocessable_entity
    assert_match "find an event with that code", response.body
  end

  test "closed event shows an error" do
    @nomikai.update!(status: "closed")
    post join_code_path, params: { code: @nomikai.formatted_join_code }

    assert_response :unprocessable_entity
    assert_match "no longer accepting", response.body
  end

  test "joining with a code creates a participant" do
    assert_difference -> { @nomikai.participants.count }, 1 do
      post join_with_code_path(@nomikai.formatted_join_code),
           params: { participant: { nickname: "Aiko", budget_max: 4000 } }
    end
    participant = @nomikai.participants.last
    assert_equal "Guest 1", participant.nickname
    assert_nil participant.budget_max
    assert_redirected_to participant_swipes_path(participant.token)
  end

  test "a regenerated code no longer works" do
    old_code = @nomikai.formatted_join_code
    @nomikai.regenerate_join_code!

    get join_with_code_path(old_code)
    assert_redirected_to join_code_path
  end
end
