module ApplicationHelper
  def plan_title(nomikai)
    meal = nomikai.meal_period.to_s.capitalize
    name = nomikai.name.to_s.strip
    return "#{meal} plan" if name.blank? || name.casecmp?("#{meal} gathering")

    name
  end
end
