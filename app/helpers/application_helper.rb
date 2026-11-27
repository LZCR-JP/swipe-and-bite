module ApplicationHelper
  def history_photo_available?(nomikai)
    nomikai.confirmed? && nomikai.candidates.find(&:selected?)&.venue&.google_place_id.present?
  end

  def plan_list_title(nomikai)
    if nomikai.finished?
      restaurant_name = nomikai.candidates.find(&:selected?)&.venue&.name
      return restaurant_name if restaurant_name.present?
    end

    plan_title(nomikai)
  end

  def plan_title(nomikai)
    meal = nomikai.meal_period.to_s.capitalize
    name = nomikai.name.to_s.strip
    return "#{meal} plan" if name.blank? || name.casecmp?("#{meal} gathering")

    name
  end
end
