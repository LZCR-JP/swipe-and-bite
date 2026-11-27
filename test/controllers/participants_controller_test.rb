require "test_helper"

class ParticipantsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @nomikai = create_nomikai(budget_per_person: 3500)
    @join_path = join_with_code_path(@nomikai.formatted_join_code)
  end

  test "confirmation does not create a participant" do
    assert_no_difference -> { @nomikai.participants.count } do
      get @join_path
    end
    assert_response :success
    assert_match "Join this plan?", response.body
    assert_match "3,500", response.body
    assert_no_match 'name="participant[nickname]"', response.body
  end

  test "guest receives a generated name and can resume from same browser" do
    post @join_path
    participant = @nomikai.participants.last
    assert_equal "Guest 1", participant.nickname
    assert_nil participant.user_id
    assert_redirected_to participant_swipes_path(participant.token)
    assert_no_difference -> { @nomikai.participants.count } do
      post @join_path
    end
    assert_redirected_to participant_swipes_path(participant.token)
  end

  test "guest names are unique within a gathering" do
    @nomikai.participants.create!(nickname: "Guest 1")
    post @join_path
    assert_equal "Guest 2", @nomikai.participants.order(:id).last.nickname
  end

  test "signed in participant uses account name and cannot join twice" do
    user = create_host(email: "guest-user@example.com")
    sign_in user
    post @join_path, params: { participant: { nickname: "Forged", budget_max: 1 } }
    participant = @nomikai.participants.find_by!(user: user)
    assert_equal user.name, participant.nickname
    assert_nil participant.budget_max
    assert_no_difference -> { @nomikai.participants.count } do
      post @join_path
    end
    assert_redirected_to participant_swipes_path(participant.token)
  end
end
