# frozen_string_literal: true

class Memory < ActiveRecord::Base
  # Validations
  validates :content, presence: true

  # ========================================
  # JSONB Helper Methods
  # ========================================

  # Setter helpers for common fields
  def category=(value)
    data['category'] = value
  end

  def category
    data['category']
  end

  def location=(value)
    data['location'] = value
  end

  def location
    data['location']
  end

  def coordinates=(value)
    data['coordinates'] = value
  end

  def coordinates
    data['coordinates']
  end

  def people=(names)
    data['people'] = Array(names)
  end

  def people
    Array(data['people'])
  end

  def tags=(tags)
    data['tags'] = Array(tags)
  end

  def tags
    Array(data['tags'])
  end

  def emotional_intensity=(value)
    data['emotional_intensity'] = value.to_f.clamp(0, 1)
  end

  def emotional_intensity
    (data['emotional_intensity'] || 0.5).to_f
  end

  def event_name=(name)
    data['event_name'] = name
  end

  def event_name
    data['event_name']
  end

  def event_time=(time)
    data['event_time'] = time.is_a?(String) ? time : time&.iso8601
  end

  def event_time
    return nil unless data['event_time']

    begin
      Time.parse(data['event_time'])
    rescue StandardError
      nil
    end
  end

  def occurred_at=(time)
    data['occurred_at'] = time.is_a?(String) ? time : time&.iso8601
  end

  def occurred_at
    return created_at unless data['occurred_at']

    begin
      Time.parse(data['occurred_at'])
    rescue StandardError
      created_at
    end
  end

  # Add any custom data
  def add_data(key, value)
    data[key.to_s] = value
  end

  def get_data(key)
    data[key.to_s]
  end

  # ========================================
  # Scopes for Querying JSONB
  # ========================================

  # Category scopes
  scope :by_category, ->(category) { where("data->>'category' = ?", category) }

  # Location scopes
  scope :by_location, ->(location) { where("data->>'location' = ?", location) }
  scope :near_coordinates, lambda { |lat, lng, radius_km = 1|
    where("(data->'coordinates'->>'lat')::float BETWEEN ? AND ?", lat - (radius_km / 111.0), lat + (radius_km / 111.0))
      .where("(data->'coordinates'->>'lng')::float BETWEEN ? AND ?", lng - (radius_km / 111.0), lng + (radius_km / 111.0))
  }

  # People scopes
  scope :about_person, ->(name) { where("data->'people' ? :name", name: name) }
  scope :with_people, -> { where("jsonb_array_length(data->'people') > 0") }

  # Tag scopes
  scope :tagged_with, ->(tag) { where("data->'tags' ? :tag", tag: tag) }
  scope :tagged_with_any, ->(tags) { where("data->'tags' ?| array[:tags]", tags: tags) }

  # Intensity scopes
  scope :high_intensity, -> { where("(data->>'emotional_intensity')::float >= 0.7") }
  scope :medium_intensity, -> { where("(data->>'emotional_intensity')::float BETWEEN 0.4 AND 0.69") }

  # Event scopes
  scope :upcoming_events, lambda {
    where("data->>'event_time' IS NOT NULL")
      .where("(data->>'event_time')::timestamp > ?", Time.now)
  }
  scope :events_within, lambda { |hours|
    upcoming_events.where("(data->>'event_time')::timestamp < ?", hours.hours.from_now)
  }

  # Ordering scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :popular, -> { order(recall_count: :desc) }
  scope :fresh, -> { order(recall_count: :asc) } # Less-told stories

  # ========================================
  # Instance Methods
  # ========================================

  # Track when memory is recalled
  def recall!
    increment!(:recall_count)
    touch(:last_recalled_at)
  end

  # Calculate story value with configurable algorithm
  def story_value
    algorithm = data['scoring_algorithm'] || 'default'

    case algorithm
    when 'experimental'
      calculate_experimental_score
    when 'simple'
      emotional_intensity
    else
      calculate_default_score
    end
  end

  # Check if this is an upcoming event
  def upcoming_event?
    event_time && event_time > Time.now
  end

  # Format for conversation injection
  def to_conversation_context
    if upcoming_event?
      time_until = time_until_in_words(event_time)
      event_prefix = event_name ? "#{event_name} - " : ''
      location_str = location ? " at #{location}" : ''
      "#{event_prefix}#{time_until}#{location_str}: #{content}"
    else
      time_ago = time_ago_in_words(occurred_at)
      location_str = location ? " at #{location}" : ''
      people_str = people.any? ? " with #{people.to_sentence}" : ''
      "#{time_ago}#{location_str}#{people_str}: #{content}"
    end
  end

  # Find related memories
  def related_memories(limit: 3)
    # Find memories with overlapping tags, people, or location
    related = Memory.where.not(id: id)

    related = related.or(Memory.tagged_with_any(tags)) if tags.any?

    if people.any?
      people.each do |person|
        related = related.or(Memory.about_person(person))
      end
    end

    related = related.or(Memory.by_location(location)) if location

    related.limit(limit)
  end

  # ========================================
  # Class Methods
  # ========================================

  # Build social graph from people mentions
  def self.people_graph
    memories_with_people = with_people

    graph = Hash.new do |h, k|
      h[k] = {
        mentioned_count: 0,
        locations: Set.new,
        co_mentioned_with: Set.new,
        story_tags: Set.new
      }
    end

    memories_with_people.find_each do |memory|
      memory.people.each do |person|
        graph[person][:mentioned_count] += 1
        graph[person][:locations] << memory.location if memory.location
        graph[person][:story_tags] += memory.tags

        # Track co-mentions
        (memory.people - [person]).each do |other_person|
          graph[person][:co_mentioned_with] << other_person
        end
      end
    end

    graph
  end

  # Get trending topics from recent tags
  def self.trending_tags(since: 24.hours.ago, limit: 10)
    recent_memories = where(created_at: since..)
    tag_counts = Hash.new(0)

    recent_memories.find_each do |memory|
      memory.tags.each { |tag| tag_counts[tag] += 1 }
    end

    tag_counts.sort_by { |_, count| -count }.first(limit).to_h
  end

  private

  def calculate_default_score
    # Default algorithm balancing intensity, freshness, and recency
    freshness_bonus = [1.0 - (recall_count * 0.1), 0.1].max
    recency_factor = 1.0 - ((Time.now - occurred_at).to_f / 7.days).clamp(0, 0.5)

    # Boost upcoming events
    event_boost = if upcoming_event? && event_time < 24.hours.from_now
                    0.3
                  elsif upcoming_event?
                    0.1
                  else
                    0
                  end

    ((emotional_intensity * 0.5) + (freshness_bonus * 0.2) + (recency_factor * 0.2) + (event_boost * 0.1)).round(2)
  end

  def calculate_experimental_score
    # Experimental algorithm - can be tweaked without changing code
    config = data['score_config'] || {}

    intensity_weight = config['intensity_weight'] || 0.6
    freshness_weight = config['freshness_weight'] || 0.2
    recency_weight = config['recency_weight'] || 0.2

    freshness = [1.0 - (recall_count * 0.15), 0].max
    recency = [1.0 - ((Time.now - occurred_at).to_f / 3.days), 0].max

    ((emotional_intensity * intensity_weight) + (freshness * freshness_weight) + (recency * recency_weight)).round(2)
  end

  def time_ago_in_words(time)
    return 'Unknown time' if time.nil?

    seconds = Time.now - time
    case seconds
    when 0..59 then 'Just now'
    when 60..3599 then "#{(seconds / 60).round} minutes ago"
    when 3600..86_399 then "#{(seconds / 3600).round} hours ago"
    when 86_400..172_799 then 'Yesterday'
    else "#{(seconds / 86_400).round} days ago"
    end
  end

  def time_until_in_words(time)
    return 'Unknown time' if time.nil?

    seconds = time - Time.now
    case seconds
    when -Float::INFINITY..0 then 'Already happened'
    when 0..59 then 'Right now!'
    when 60..3599 then "In #{(seconds / 60).round} minutes"
    when 3600..86_399 then "In #{(seconds / 3600).round} hours"
    when 86_400..172_799 then 'Tomorrow'
    else "In #{(seconds / 86_400).round} days"
    end
  end
end
