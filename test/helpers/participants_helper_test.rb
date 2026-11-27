require "test_helper"

class ParticipantsHelperTest < ActionView::TestCase
  include ParticipantsHelper

  test "formats actual yen endpoints and missing endpoints" do
    low = { "currencyCode" => "JPY", "units" => "1000" }
    high = { "currencyCode" => "JPY", "units" => "2000" }
    assert_equal "¥1,000–¥2,000", restaurant_price_range("startPrice" => low, "endPrice" => high)
    assert_equal "From ¥1,000", restaurant_price_range("startPrice" => low)
    assert_equal "Under ¥2,000", restaurant_price_range("endPrice" => high)
    assert_equal "¥1,000", restaurant_price_range("startPrice" => low, "endPrice" => low)
    assert_nil restaurant_price_range("startPrice" => high, "endPrice" => low)
    assert_nil restaurant_price_range(nil)
    assert_nil restaurant_price_range({})
    assert_nil restaurant_price_range("startPrice" => { "currencyCode" => "JPY", "units" => "unknown" })
  end
end
