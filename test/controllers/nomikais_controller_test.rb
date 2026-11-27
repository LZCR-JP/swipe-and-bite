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
    @gathering.update!(status: "closed", matches_found_at: Time.current, decision_state: "legacy")
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

  test "host lobby shows the join code instead of the retired email invite form" do
    @gathering.invitations.create!(email: "aiko@example.com", sent_at: Time.current)

    get nomikai_path(@gathering)
    assert_response :success
    assert_select "input.host-lobby__code[value=?]", @gathering.formatted_join_code, count: 1
    assert_select "form[action=?] button.host-lobby__swipe", start_host_swipes_nomikai_path(@gathering), count: 1
    assert_select "input[name=emails]", count: 0
    assert_no_match "aiko@example.com", response.body
  end

  test "host can share the invite and the participant panel refreshes when responses change" do
    get nomikai_path(@gathering)
    assert_response :success
    assert_select 'button[data-action="invite-share#share"]', text: /Share invite/
    assert_select '.plan-crew__avatar.is-empty', count: 3
    assert_select '.plan-crew .host-lobby__section-head p', text: '0 / 3 joined'
    assert_select '.plan-crew__caption strong', text: 'Waiting for 3 friends to join'
    assert_select '.plan-crew .host-lobby__progress-label strong', text: '0 / 4'
    assert_select 'button.host-lobby__primary[disabled]', text: 'Find restaurants'

    get progress_nomikai_path(@gathering), params: { view: 'lobby', signature: '0:0:4' }, as: :json
    assert_response :success
    assert_nil response.parsed_body['html']

    @gathering.participants.create!(nickname: 'Guest 1', completed_at: Time.current)
    get progress_nomikai_path(@gathering), params: { view: 'lobby', signature: '0:0:4' }, as: :json
    assert_response :success
    assert_equal '1:1:4', response.parsed_body['signature']
    assert_match 'Find restaurants', response.parsed_body['html']
    assert_match 'is-ready', response.parsed_body['html']
    assert_equal 1, response.parsed_body['guest_joined']
    assert_equal 3, response.parsed_body['guest_total']

    @gathering.participants.create!(user: @host, nickname: @host.name, completed_at: Time.current)
    get nomikai_path(@gathering)
    assert_select '.plan-crew__avatar.is-empty', count: 2
    assert_select '.plan-crew .host-lobby__section-head p', text: '1 / 3 joined'
    assert_select '.plan-crew__caption strong', text: 'Waiting for 2 friends to join'
    assert_select '.plan-crew .host-lobby__progress-label strong', text: '2 / 4'
  end

end
