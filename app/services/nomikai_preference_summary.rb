class NomikaiPreferenceSummary
  def initialize(nomikai)
    @nomikai = nomikai
  end

  def call
    participants = @nomikai.participants.to_a
    budgets = participants.filter_map(&:budget_max)
    swipes = Swipe.joins(:nomikai_vibe_card)
                  .where(nomikai_vibe_cards: { nomikai_id: @nomikai.id })
                  .where(participant_id: participants.map(&:id))
                  .includes(nomikai_vibe_card: :vibe_card).to_a

    feedback = card_feedback(swipes)

    {
      area: @nomikai.area,
      meal_period: @nomikai.meal_period,
      event_budget_per_person: @nomikai.budget_per_person,
      effective_budget_per_person: (budgets + [@nomikai.budget_per_person]).compact.min,
      group_size: @nomikai.group_size,
      participants_joined: participants.size,
      participants_completed: participants.count { |p| p.completed_at.present? },
      participants_voted: swipes.map(&:participant_id).uniq.size,
      participant_budget_maxima: budgets,
      non_drinkers: participants.count(&:non_drinker?),
      dietary_restrictions: participants.flat_map(&:restrictions)
                                        .compact.reject(&:blank?).tally,
      liked_vibes: title_counts(feedback, :likes),
      disliked_vibes: title_counts(feedback, :dislikes),
      cuisine_preferences: cuisine_preferences(swipes),
      vibe_evidence: vibe_evidence(feedback),
      card_feedback: feedback
    }
  end

  private

  def card_feedback(swipes)
    swipes.group_by(&:nomikai_vibe_card_id).map do |_, votes|
      card = votes.first.nomikai_vibe_card.vibe_card

      {
        title: card.title,
        image_type: card.image_type,
        cuisine: card.cuisine,
        vibe_scores: card.vibe_scores || {},
        likes: votes.count(&:liked?),
        dislikes: votes.count { |vote| !vote.liked? }
      }
    end
  end

  def title_counts(feedback, key)
    feedback.each_with_object(Hash.new(0)) do |card, counts|
      counts[card[:title]] += card[key] if card[key].positive?
    end
  end

  def cuisine_preferences(swipes)
    food_votes = swipes.select do |swipe|
      card = swipe.nomikai_vibe_card.vibe_card
      card.image_type == "food" && card.cuisine.present? && card.cuisine != "unspecified"
    end

    food_votes.group_by { |swipe| swipe.nomikai_vibe_card.vibe_card.cuisine }
              .transform_values do |votes|
      by_person = votes.group_by(&:participant_id)
      rates = by_person.values.map { |person_votes| person_votes.count(&:liked?).fdiv(person_votes.size) }

      {
        like_rate: (rates.sum.fdiv(rates.size) * 100).round,
        participants: by_person.size,
        likes: votes.count(&:liked?),
        dislikes: votes.count { |vote| !vote.liked? }
      }
    end
  end

  def vibe_evidence(feedback)
    dimensions = Hash.new do |hash, key|
      hash[key] = { liked_sum: 0, disliked_sum: 0, likes: 0, dislikes: 0 }
    end

    feedback.each do |card|
      card[:vibe_scores].each do |name, score|
        next unless score.is_a?(Numeric) && score.between?(0, 100)

        evidence = dimensions[name]
        evidence[:liked_sum] += score * card[:likes]
        evidence[:disliked_sum] += score * card[:dislikes]
        evidence[:likes] += card[:likes]
        evidence[:dislikes] += card[:dislikes]
      end
    end

    dimensions.transform_values do |evidence|
      {
        liked_average: average(evidence[:liked_sum], evidence[:likes]),
        disliked_average: average(evidence[:disliked_sum], evidence[:dislikes]),
        likes: evidence[:likes],
        dislikes: evidence[:dislikes]
      }
    end
  end

  def average(sum, count)
    count.positive? ? sum.fdiv(count).round(1) : nil
  end
end
