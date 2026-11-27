require "test_helper"

class RestaurantDecisionsTest < ActionDispatch::IntegrationTest
  setup do
    @host = create_host
    @plan = create_nomikai(user: @host, event_date: nil)
    @guest = @plan.participants.create!(nickname: "Guest 1", completed_at: Time.current)
    @second_guest = @plan.participants.create!(nickname: "Guest 2", completed_at: Time.current)
    @venue = Venue.create!(google_place_id: "test-restaurant", name: "Test Restaurant", primary_type: "Izakaya")
    @candidate = @plan.candidates.create!(venue: @venue)
  end

  test "host cannot join their own plan through code or link but can start host swipes" do
    sign_in @host
    assert_no_difference -> { @plan.participants.count } do
      post join_code_path, params: { code: @plan.join_code }
      assert_redirected_to nomikai_path(@plan)
      get join_with_code_path(@plan.join_code)
      assert_redirected_to nomikai_path(@plan)
      post join_path(@plan.share_token)
      assert_redirected_to nomikai_path(@plan)
    end
    assert_difference -> { @plan.participants.count }, 1 do
      post start_host_swipes_nomikai_path(@plan)
    end
    host_swipes = @plan.participants.find_by!(user: @host)
    assert_redirected_to participant_swipes_path(host_swipes.token)
    assert_no_difference -> { @plan.participants.count } do
      post start_host_swipes_nomikai_path(@plan)
    end
    assert_not @plan.voting_participants.exists?(host_swipes.id)
    sign_out @host
    get participant_swipes_path(host_swipes.token)
    assert_response :forbidden
  end

  test "picking opens a decision screen and does not select or confirm until explicitly requested" do
    @plan.update!(matches_found_at: Time.current)
    sign_in @host
    get nomikai_path(@plan)
    assert_response :success
    assert_select 'dialog.restaurant-decision__sheet' do
      assert_select 'input[name="decision"][value="confirm"]', count: 1
      assert_select 'input[name="decision"][value="vote"]', count: 1
    end
    assert_not @candidate.reload.selected?
    get candidate_decision_nomikai_path(@plan, candidate_id: @candidate.id)
    assert_response :success
    assert_match "Confirm restaurant", response.body
    assert_match "Ask participants", response.body
    assert_not @candidate.reload.selected?
    assert @plan.reload.ongoing?
    patch select_candidate_nomikai_path(@plan, candidate_id: @candidate.id)
    assert_response :unprocessable_entity
    patch select_candidate_nomikai_path(@plan, candidate_id: @candidate.id), params: { decision: "confirm" }
    assert @plan.reload.confirmed?
    assert @candidate.reload.selected?
    assert_not @plan.ongoing?
    assert @plan.finished?
    sign_out @host
    get participant_path(@guest.token)
    assert_response :success
    assert_match "Test Restaurant", response.body
    assert_select ".participant-vote-actions", count: 0
    assert_select ".participant-event-card", count: 0
    assert_select ".participant-welcome", count: 0
    assert_select ".participant-restaurant__photo", count: 1
    assert_select ".participant-restaurant__price", count: 1
  end

  test "all guests vote before only the host can confirm" do
    host_swipes = @plan.participants.create!(user: @host, nickname: @host.name, completed_at: Time.current)
    open_vote
    assert @plan.ongoing?
    assert @plan.restaurant_feedback_open?
    get participant_path(@guest.token)
    assert_response :success
    assert_select "h1", text: "Host picked a restaurant"
    assert_select ".participant-vote-actions button", count: 2
    assert_select ".participant-preferences", count: 0
    post participant_candidate_votes_path(host_swipes.token), params: vote_params(true)
    assert_response :forbidden
    post participant_candidate_votes_path(@guest.token), params: vote_params(true)
    assert @plan.reload.restaurant_feedback_open?
    assert_not @plan.confirmed?
    sign_in @host
    patch select_candidate_nomikai_path(@plan, candidate_id: @candidate.id), params: { decision: "confirm" }
    assert_not @plan.reload.confirmed?
    sign_out @host
    post participant_candidate_votes_path(@second_guest.token), params: vote_params(true)
    assert @plan.reload.all_votes_received?
    assert_not @plan.confirmed?
    get participant_path(@guest.token)
    assert_match "Waiting for host confirmation", response.body
    sign_in @host
    patch select_candidate_nomikai_path(@plan, candidate_id: @candidate.id), params: { decision: "confirm" }
    assert @plan.reload.confirmed?
    assert_not @plan.restaurant_feedback_open?
  end

  test "a no vote returns the decision to the host and stale votes cannot confirm a new round" do
    open_vote
    old_round = @plan.decision_round
    post participant_candidate_votes_path(@guest.token), params: vote_params(false)
    assert @plan.reload.restaurant_feedback_open?
    post participant_candidate_votes_path(@second_guest.token), params: vote_params(true)
    assert_equal "rejected", @plan.reload.decision_state
    assert @plan.ongoing?
    open_vote
    assert_operator @plan.decision_round, :>, old_round
    post participant_candidate_votes_path(@second_guest.token), params: vote_params(true).merge(decision_round: old_round)
    assert_equal 0, @candidate.candidate_votes.count
    assert @plan.reload.restaurant_feedback_open?
  end

  private

  def open_vote
    @plan.update!(matches_found_at: Time.current) unless @plan.matches_ready?
    sign_in @host
    patch select_candidate_nomikai_path(@plan, candidate_id: @candidate.id), params: { decision: "vote" }
    assert_redirected_to nomikai_path(@plan)
    sign_out @host
    @plan.reload
  end

  def vote_params(approved)
    { candidate_id: @candidate.id, decision_round: @plan.decision_round, approved: approved }
  end
end
