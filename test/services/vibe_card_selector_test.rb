require "test_helper"

class VibeCardSelectorTest < ActiveSupport::TestCase
  setup do
    @nomikai = create_nomikai(budget_per_person: 4000)
  end

  test "selects eight distinct photos with diverse food and atmosphere" do
    6.times { |i| photo("food", cuisine: "cuisine-#{i}") }
    %w[cozy modern outdoor privacy luxury casual].each { |vibe| photo("venue", scores: { vibe => 90 }) }
    cards = VibeCardSelector.new(@nomikai).call.map(&:vibe_card)
    assert_equal 8, cards.size
    assert_equal 8, cards.map(&:id).uniq.size
    food = cards.select { |card| card.image_type == "food" }
    venues = cards.select { |card| card.image_type == "venue" }
    assert_equal 4, food.size
    assert_equal 4, food.map(&:cuisine).uniq.size
    assert_equal 4, venues.size
    assert_equal 4, venues.map { |card| card.vibe_scores.keys.first }.uniq.size
  end

  test "fills missing types only with eligible photos" do
    7.times { photo("food") }
    photo("venue")
    outside = photo("venue", min_budget: 9000)
    cards = VibeCardSelector.new(@nomikai).call.map(&:vibe_card)
    assert_equal 8, cards.size
    assert_not_includes cards, outside
  end

  test "does not replace an existing deck" do
    15.times do |i|
      @nomikai.nomikai_vibe_cards.create!(vibe_card: photo("food"), position: i + 1)
    end
    ids = @nomikai.nomikai_vibe_cards.order(:position).pluck(:id)
    assert_equal ids, VibeCardSelector.new(@nomikai).call.order(:position).pluck(:id)
  end

  test "uses fewer than eight when the eligible pool is smaller" do
    3.times { photo("food") }
    photo("venue", min_budget: 9000)
    assert_equal 3, VibeCardSelector.new(@nomikai).call.size
  end

  private

  def photo(type, cuisine: "japanese", scores: {}, min_budget: 1000)
    VibeCard.create!(title: "Example", description: "Example photo", image_url: "/icon.png",
                     image_type: type, cuisine: cuisine, vibe_scores: scores,
                     min_budget: min_budget, active: true)
  end
end
