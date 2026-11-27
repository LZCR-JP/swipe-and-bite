require "bigdecimal"

module ParticipantsHelper
  # Google returns a Money object per endpoint, and may omit either bound.
  # Never substitute the host's budget or a guessed price level for a real range.
  def restaurant_price_range(range)
    return unless range.is_a?(Hash)

    low = restaurant_money(range["startPrice"])
    high = restaurant_money(range["endPrice"])
    if low && high
      return unless low.first == high.first
      return if low.last > high.last
      return format_restaurant_money(low) if low.last == high.last
      "#{format_restaurant_money(low)}–#{format_restaurant_money(high)}"
    elsif low
      "From #{format_restaurant_money(low)}"
    elsif high
      "Under #{format_restaurant_money(high)}"
    end
  end

  private

  def restaurant_money(value)
    return unless value.is_a?(Hash)
    currency = value["currencyCode"].to_s
    return unless currency.match?(/\A[A-Z]{3}\z/)

    # Protobuf JSON omits units/nanos when zero.
    units = Integer(value.fetch("units", 0))
    nanos = Integer(value.fetch("nanos", 0))
    return if units.negative? || !nanos.between?(0, 999_999_999)
    return if currency == "JPY" && !nanos.zero?

    [currency, BigDecimal(units.to_s) + BigDecimal(nanos.to_s) / 1_000_000_000]
  rescue ArgumentError, TypeError
    nil
  end

  def format_restaurant_money(money)
    currency, amount = money
    if currency == "JPY"
      "¥#{number_with_delimiter(amount.to_i)}"
    else
      "#{currency} #{number_with_precision(amount, precision: 2, delimiter: ',', strip_insignificant_zeros: true)}"
    end
  end
end
