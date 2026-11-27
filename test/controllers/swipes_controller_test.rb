require "test_helper"

class SwipesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @nomikai = create_nomikai
    @participant = @nomikai.participants.create!(nickname: "Guest 1")
    @card = @nomikai.nomikai_vibe_cards.create!(position: 1, vibe_card: VibeCard.create!(title: "Dinner", description: "Dinner", active: true, image_url: "/icon.png"))
    @finish_path = finish_participant_swipes_path(@participant.token)
  end

  test "last swipe opens restrictions without marking participant complete" do
    post participant_swipes_path(@participant.token), params: { nomikai_vibe_card_id: @card.id, liked: true }
    assert_nil @participant.reload.completed_at
    follow_redirect!
    assert_response :success
    assert_match "Any dietary restrictions", response.body
  end

  test "swipe screen includes the tutorial and a replay button" do
    get participant_swipes_path(@participant.token)
    assert_response :success
    assert_select "[data-controller~='swipe-tutorial']" do
      assert_select "dialog.swipe-tutorial[data-swipe-tutorial-target='dialog']"
      assert_select "button.swipe-help-button[data-action='swipe-tutorial#open']"
    end
  end

  test "finish cannot bypass the swipes" do
    post @finish_path
    assert_nil @participant.reload.completed_at
    assert_redirected_to participant_swipes_path(@participant.token)
  end

  test "finish saves only supported restrictions and records completion" do
    @participant.swipes.create!(nomikai_vibe_card: @card, liked: true)
    post @finish_path, params: { participant: { restrictions: ["Halal", "Nut allergy", "Unknown"], non_drinker: "1" } }
    assert_redirected_to participant_path(@participant.token)
    @participant.reload
    assert_equal ["Halal", "Nut allergy"], @participant.restrictions
    assert @participant.non_drinker?
    assert @participant.completed_at.present?
    post @finish_path
    assert_equal ["Halal", "Nut allergy"], @participant.reload.restrictions
  end

  test "finish with no restrictions works" do
    @participant.swipes.create!(nomikai_vibe_card: @card, liked: false)
    post @finish_path
    assert_redirected_to participant_path(@participant.token)
    assert @participant.reload.completed_at.present?
    assert_empty @participant.restrictions
  end
end
