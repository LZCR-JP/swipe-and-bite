require "test_helper"

class NomikaiTest < ActiveSupport::TestCase
  test "assigns a readable join code on create" do
    nomikai = create_nomikai

    assert_match(/\A[0-9]{4}\z/, nomikai.join_code)
    assert_equal nomikai.join_code, nomikai.formatted_join_code
  end

  test "finds by join code regardless of case, spacing, dashes or prefix" do
    nomikai = create_nomikai
    code = nomikai.join_code

    ["SWIPE-#{code}", "swipe-#{code.downcase}", " #{code} ", "swipe #{code}", code.chars.join("-")].each do |input|
      assert_equal nomikai, Nomikai.find_by_join_code(input), "expected #{input.inspect} to match"
    end
  end

  test "preserves leading zeros and legacy codes" do
    numeric = create_nomikai(join_code: "0042")
    legacy = create_nomikai(user: create_host(email: "legacy@example.com"), join_code: "K7QM2P")
    assert_equal numeric, Nomikai.find_by_join_code("0042")
    assert_equal legacy, Nomikai.find_by_join_code("SWIPE-K7QM2P")
  end

  test "new codes are distinct" do
    assert_not_equal create_nomikai.join_code, create_nomikai(user: create_host(email: "second@example.com")).join_code
  end

  test "rejects malformed join codes" do
    create_nomikai

    assert_nil Nomikai.find_by_join_code("")
    assert_nil Nomikai.find_by_join_code("SWIPE-")
    assert_nil Nomikai.find_by_join_code("ABC")
  end

  test "regenerating the join code revokes the old one" do
    nomikai = create_nomikai
    old_code = nomikai.formatted_join_code

    nomikai.regenerate_join_code!

    assert_nil Nomikai.find_by_join_code(old_code)
    assert_equal nomikai, Nomikai.find_by_join_code(nomikai.formatted_join_code)
  end

  test "only open, upcoming events accept participants" do
    assert create_nomikai.accepting_participants?
    assert_not create_nomikai(status: "closed").accepting_participants?

    past = create_nomikai(user: create_host(email: "past@example.com"))
    past.update_column(:event_date, 1.day.ago)
    assert_not past.accepting_participants?
  end

  test "new gatherings do not require a date" do
    gathering = create_nomikai(event_date: nil, meal_period: "lunch")
    assert gathering.accepting_participants?
    assert_equal "lunch", gathering.meal_period
    assert_not gathering.name.blank?
  end

  test "map location requires coordinates" do
    gathering = create_nomikai(event_date: nil)
    gathering.area = "Selected on map"
    assert_not gathering.valid?
    gathering.latitude = 35.658
    gathering.longitude = 139.7016
    assert gathering.valid?
  end

end
