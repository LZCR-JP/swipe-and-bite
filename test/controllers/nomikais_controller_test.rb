require "test_helper"

class NomikaisControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create_host
    sign_in @host
    @gathering = create_nomikai(user: @host, event_date: nil)
  end

  test "ongoing gathering blocks another create" do
    get new_nomikai_path
    assert_response :success
    assert_select ".ongoing-card", count: 1
    assert_no_difference "Nomikai.count" do
      post nomikais_path, params: { nomikai: { area: "Ginza", group_size: 4, meal_period: "lunch", budget_per_person: 3000 } }
    end
    assert_redirected_to nomikai_path(@gathering)
  end

  test "cancel removes gathering from ongoing and history" do
    patch close_nomikai_path(@gathering)
    assert_redirected_to new_nomikai_path
    assert_not @gathering.reload.ongoing?
    assert_not @gathering.finished?
    get nomikais_path
    assert_select ".ongoing-card", count: 0
    assert_select ".gathering-history__row", count: 0
  end

  test "finished gathering appears in history and does not block creation screen" do
    @gathering.update!(status: "closed", matches_found_at: Time.current)
    get nomikais_path
    assert_select ".ongoing-card", count: 0
    assert_select ".gathering-history__row", count: 1
    get new_nomikai_path
    assert_select ".meeting-create", count: 1
  end

  test "cannot request matches with no completed responses" do
    post recommendations_nomikai_path(@gathering)
    assert_redirected_to nomikai_path(@gathering)
    assert @gathering.reload.ongoing?
  end
end
