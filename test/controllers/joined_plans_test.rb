require "test_helper"

class JoinedPlansTest < ActionDispatch::IntegrationTest
  setup do
    @host = create_host
    @plan = create_nomikai(user: @host, event_date: nil)
    @other = create_nomikai(user: create_host(email: "other-host@example.com"), event_date: nil)
    @other.participants.create!(nickname: "Unrelated guest")
    @venue = Venue.create!(google_place_id: "joined-plans-restaurant", name: "Test Restaurant", primary_type: "Izakaya")
    @candidate = @plan.candidates.create!(venue: @venue)
  end

  test "guest can return from Plans and receive voting and confirmation updates in another session" do
    guest = open_session
    guest.post join_with_code_path(@plan.join_code)
    participant = @plan.participants.find_by!(nickname: "Guest 1")
    participant.update!(completed_at: Time.current)
    guest.get nomikais_path
    assert_equal 200, guest.response.status
    assert_includes guest.response.body, participant_path(participant.token)
    assert_includes guest.response.body, "Waiting for the host"
    assert_not_includes guest.response.body, @other.participants.first.token

    @plan.update!(matches_found_at: Time.current)
    sign_in @host
    patch select_candidate_nomikai_path(@plan, candidate_id: @candidate.id), params: { decision: "vote" }
    guest.get plan_updates_path(format: :json)
    assert_equal "vote", guest.response.parsed_body.fetch("updates").first.fetch("state")
    guest.post participant_candidate_votes_path(participant.token), params: { candidate_id: @candidate.id, decision_round: @plan.reload.decision_round, approved: true }
    assert_not @plan.reload.confirmed?
    guest.get plan_updates_path(format: :json)
    assert_empty guest.response.parsed_body.fetch("updates")
    patch select_candidate_nomikai_path(@plan, candidate_id: @candidate.id), params: { decision: "confirm" }
    assert @plan.reload.confirmed?
    get plan_updates_path(format: :json)
    assert_equal "Test Restaurant", response.parsed_body.fetch("updates").first.fetch("restaurant")
    guest.get plan_updates_path(format: :json)
    assert_equal "confirmed", guest.response.parsed_body.fetch("updates").first.fetch("state")
    guest.get nomikais_path
    assert_includes guest.response.body, "Restaurant confirmed"
    assert_includes guest.response.body, participant_path(participant.token)
    guest.get participant_path(participant.token)
    assert_includes guest.response.body, "It's confirmed!"
    assert_includes guest.response.body, "Test Restaurant"

    stranger = open_session
    stranger.get confirmation_photo_nomikai_path(@plan, format: :json)
    assert_equal 404, stranger.response.status
    stranger.get plan_updates_path(format: :json)
    assert_empty stranger.response.parsed_body.fetch("updates")
    stranger.get nomikais_path
    assert_not_includes stranger.response.body, participant.token
  end

  test "signed in member sees joined plans but not host swipe records" do
    member = create_host(email: "member@example.com")
    participant = @plan.participants.create!(user: member, nickname: member.name)
    own_plan = create_nomikai(user: member, event_date: nil)
    own_swipes = own_plan.participants.create!(user: member, nickname: member.name)
    sign_in member
    get nomikais_path
    assert_response :success
    assert_select "a.joined-plan-card[href=?]", participant_swipes_path(participant.token), count: 1
    assert_select "a.joined-plan-card[href=?]", participant_swipes_path(own_swipes.token), count: 0
    @plan.update!(status: "closed")
    get nomikais_path
    assert_select "a.joined-plan-card", count: 0
  end
end
