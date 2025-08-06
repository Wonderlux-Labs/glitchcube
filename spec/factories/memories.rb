# frozen_string_literal: true

FactoryBot.define do
  factory :memory do
    content { 'Someone tried to STEAL me at the Man yesterday!' }
    data do
      {
        category: 'personal_experiences',
        emotional_intensity: 0.9,
        people: ['Crazy Dave', 'Rainbow'],
        tags: %w[theft drama wild the-man],
        location: 'The Man',
        occurred_at: 1.hour.ago.iso8601
      }
    end

    # Variations for different memory types
    factory :upcoming_event_memory do
      content { 'Robot Heart sunrise set tomorrow at 6am in deep playa!' }
      data do
        {
          category: 'events_witnessed',
          emotional_intensity: 0.8,
          event_name: 'Robot Heart Sunrise',
          event_time: 1.day.from_now.change(hour: 6).iso8601,
          location: 'Deep Playa',
          tags: %w[music sunrise robot-heart party]
        }
      end
    end

    factory :gossip_memory do
      content { 'I heard Camp Questionmark is throwing a secret party tonight!' }
      data do
        {
          category: 'gossip',
          emotional_intensity: 0.7,
          people: ['Someone from Camp Questionmark'],
          tags: %w[gossip party secret camp-questionmark],
          location: 'Center Camp'
        }
      end
    end

    factory :location_memory do
      content { 'Last time I was here, someone covered me in glitter!' }
      data do
        {
          category: 'location_stories',
          emotional_intensity: 0.6,
          location: '9 & K',
          tags: %w[glitter funny art],
          occurred_at: 2.days.ago.iso8601
        }
      end
    end

    factory :high_intensity_memory do
      content { "THE TEMPLE BURN WAS THE MOST BEAUTIFUL THING I'VE EVER SEEN!" }
      data do
        {
          category: 'emotional_moments',
          emotional_intensity: 1.0,
          location: 'The Temple',
          tags: %w[temple burn emotional beautiful transcendent],
          occurred_at: 3.days.ago.iso8601
        }
      end
    end

    factory :experimental_memory do
      content { 'A dust devil picked me up and spun me around!' }
      data do
        {
          category: 'personal_experiences',
          emotional_intensity: 0.85,
          tags: %w[weather dust-devil wild],
          location: 'Open Playa',
          # Experimental fields the LLM might add
          weather: 'dusty',
          time_of_day: 'sunset',
          mood: 'playful',
          score_config: {
            intensity_weight: 0.7,
            freshness_weight: 0.2,
            recency_weight: 0.1
          }
        }
      end
    end
  end
end
