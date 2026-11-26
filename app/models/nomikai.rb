class Nomikai < ApplicationRecord
  STATUSES = ["open", "closed"].freeze

  scope :ongoing, -> { where(status: "open", matches_found_at: nil) }
  scope :finished, -> { where.not(matches_found_at: nil) }

  def ongoing?
    status == "open" && matches_found_at.nil?
  end

  def finished?
    matches_found_at.present?
  end

  JOIN_CODE_PREFIX = "SWIPE".freeze
  JOIN_CODE_LENGTH = 4

  belongs_to :user
  has_many :participants, dependent: :destroy
  has_many :invitations, dependent: :destroy
  has_many :candidates, dependent: :destroy
  has_many :nomikai_vibe_cards, dependent: :destroy
  has_many :vibe_cards, through: :nomikai_vibe_cards
  has_many :venues, through: :candidates

  has_secure_token :share_token

  before_validation :set_default_name, on: :create
  before_validation :assign_join_code, on: :create

  validates :area, presence: true
  validates :meal_period, inclusion: { in: %w[lunch dinner] }
  validate :coordinates_for_map_location

  def coordinates_for_map_location
    if area == "Selected on map" && (latitude.nil? || longitude.nil?)
      errors.add(:area, "requires a meeting point")
    end
    if latitude.nil? != longitude.nil?
      errors.add(:area, "requires both coordinates")
    end
  end
  validates :group_size, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 50 }
  validates :budget_per_person, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }, allow_nil: true
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }
  validates :join_code, presence: true, uniqueness: true

  def self.normalize_join_code(input)
    input.to_s.upcase.gsub(/[\s-]/, "").delete_prefix(JOIN_CODE_PREFIX)
  end

  def self.find_by_join_code(input)
    code = normalize_join_code(input)
    numeric = code.match?(/\A[0-9]{4}\z/)
    legacy = code.match?(/\A[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}\z/)
    return unless numeric || legacy

    find_by(join_code: code)
  end

  def self.generate_join_code
    used = where("join_code ~ ?", "^[0-9]{4}$").pluck(:join_code)
    available = (0...10_000).map { |number| format("%04d", number) } - used
    raise "No join codes available" if available.empty?

    available.fetch(SecureRandom.random_number(available.length))
  end

  def formatted_join_code
    join_code.match?(/\A[0-9]{4}\z/) ? join_code : "#{JOIN_CODE_PREFIX}-#{join_code}"
  end

  # Revokes the current code; anyone holding the old one can no longer join.
  def regenerate_join_code!
    update!(join_code: self.class.generate_join_code)
  end

  def accepting_participants?
    status == "open" && (event_date.nil? || event_date.future?)
  end

  private

  def set_default_name
    return unless name.blank?

    self.name = "#{meal_period.to_s.capitalize} gathering"
  end

  def assign_join_code
    self.join_code ||= self.class.generate_join_code
  end
end
