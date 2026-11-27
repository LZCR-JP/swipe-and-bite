class Nomikai < ApplicationRecord
  STATUSES = ["open", "closed"].freeze

  ACTIVE_DECISIONS = %w[pending voting rejected].freeze
  scope :ongoing, -> { where(status: "open", decision_state: ACTIVE_DECISIONS) }
  scope :finished, -> { where(decision_state: %w[confirmed legacy]) }
  validates :decision_state, inclusion: { in: ACTIVE_DECISIONS + %w[confirmed legacy] }

  def ongoing?
    status == "open" && ACTIVE_DECISIONS.include?(decision_state)
  end

  def matches_ready?
    matches_found_at.present?
  end

  def collecting_swipes?
    ongoing? && !matches_ready?
  end

  def finished?
    %w[confirmed legacy].include?(decision_state)
  end

  def confirmed?
    decision_state == "confirmed"
  end

  def restaurant_feedback_open?
    ongoing? && decision_state == "voting" && candidates.where(selected: true).exists?
  end

  def voting_participants
    participants.where(user_id: nil).or(participants.where.not(user_id: user_id))
  end

  def all_votes_received?
    selected = candidates.find_by(selected: true)
    eligible = voting_participants
    selected.present? && eligible.exists? &&
      selected.candidate_votes.where(participant_id: eligible.select(:id)).count == eligible.count
  end

  def confirm_restaurant!
    update!(decision_state: "confirmed", confirmed_at: Time.current, status: "closed")
  end

  def decision_signature
    selected = candidates.find_by(selected: true)
    votes = selected ? selected.candidate_votes.where(participant_id: voting_participants.select(:id)) : CandidateVote.none
    [status, decision_state, decision_round, matches_found_at&.to_i, selected&.id, votes.count, votes.where(approved: true).count].join(":")
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
    collecting_swipes? && (event_date.nil? || event_date.future?)
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
