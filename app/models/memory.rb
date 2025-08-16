# frozen_string_literal: true

class Memory < ActiveRecord::Base
  # Callbacks
  before_validation :ensure_data_hash

  # Validations
  validates :content, presence: true
  validates :data, presence: true
  validate :data_must_be_hash

  # JSONB accessors for common fields
  %w[category location coordinates event_name].each do |field|
    define_method(field) { data[field] }
    define_method("#{field}=") { |value| data[field] = value }
  end

  %w[people tags].each do |field|
    define_method(field) { Array(data[field]) }
    define_method("#{field}=") { |value| data[field] = Array(value) }
  end

  def emotional_intensity=(value)
    data['emotional_intensity'] = value.to_f.clamp(0, 1)
  end

  def emotional_intensity
    (data['emotional_intensity'] || 0.5).to_f
  end

  %w[event_time occurred_at].each do |time_field|
    define_method("#{time_field}=") do |time|
      data[time_field] = time.is_a?(String) ? time : time&.iso8601
    end

    define_method(time_field) do
      return (time_field == 'occurred_at' ? created_at : nil) unless data[time_field]

      begin
        Time.parse(data[time_field])
      rescue StandardError
        (time_field == 'occurred_at' ? created_at : nil)
      end
    end
  end

  # JSONB scopes
  %w[category location].each do |field|
    scope :"by_#{field}", ->(value) { where('data->>? = ?', field, value) }
  end

  scope :near_coordinates, lambda { |lat, lng, radius_km = 1|
    offset = radius_km / 111.0
    where("(data->'coordinates'->>'lat')::float BETWEEN ? AND ?", lat - offset, lat + offset)
      .where("(data->'coordinates'->>'lng')::float BETWEEN ? AND ?", lng - offset, lng + offset)
  }

  scope :about_person, ->(name) { where("data->'people' ? :name", name: name) }
  scope :with_people, -> { where("jsonb_array_length(data->'people') > 0") }
  scope :tagged_with, ->(tag) { where("data->'tags' ? :tag", tag: tag) }
  scope :tagged_with_any, ->(tags) { where("data->'tags' ?| array[:tags]", tags: tags) }
  scope :high_intensity, -> { where("(data->>'emotional_intensity')::float >= 0.7") }
  scope :medium_intensity, -> { where("(data->>'emotional_intensity')::float BETWEEN 0.4 AND 0.69") }
  scope :upcoming_events, -> { where("data->>'event_time' IS NOT NULL AND (data->>'event_time')::timestamp > ?", Time.now) }
  scope :events_within, ->(hours) { upcoming_events.where("(data->>'event_time')::timestamp < ?", hours.hours.from_now) }
  scope :recent, -> { order(created_at: :desc) }
  scope :popular, -> { order(recall_count: :desc) }
  scope :fresh, -> { order(recall_count: :asc) }

  def recall!
    increment!(:recall_count)
    touch(:last_recalled_at)
  end

  def story_value
    case data['scoring_algorithm'] || 'default'
    when 'experimental' then calculate_experimental_score
    when 'simple' then emotional_intensity
    else calculate_default_score
    end
  end

  def upcoming_event?
    event_time&.> Time.now
  end

  def to_conversation_context
    if upcoming_event?
      prefix = event_name ? "#{event_name} - " : ''
      location_str = location ? " at #{location}" : ''
      "#{prefix}#{time_words(event_time, future: true)}#{location_str}: #{content}"
    else
      location_str = location ? " at #{location}" : ''
      people_str = people.any? ? " with #{people.to_sentence}" : ''
      "#{time_words(occurred_at)}#{location_str}#{people_str}: #{content}"
    end
  end

  def related_memories(limit: 3)
    query = Memory.where.not(id: id)
    query = query.or(Memory.tagged_with_any(tags)) if tags.any?
    query = people.reduce(query) { |q, person| q.or(Memory.about_person(person)) } if people.any?
    query = query.or(Memory.by_location(location)) if location
    query.limit(limit)
  end

  def self.people_graph
    graph = Hash.new { |h, k| h[k] = { mentioned_count: 0, locations: Set.new, co_mentioned_with: Set.new, story_tags: Set.new } }

    with_people.find_each do |memory|
      memory.people.each do |person|
        graph[person][:mentioned_count] += 1
        graph[person][:locations] << memory.location if memory.location
        graph[person][:story_tags] += memory.tags
        (memory.people - [person]).each { |other| graph[person][:co_mentioned_with] << other }
      end
    end

    graph
  end

  def self.trending_tags(since: 24.hours.ago, limit: 10)
    where(created_at: since..)
      .flat_map(&:tags)
      .tally
      .sort_by { |_, count| -count }
      .first(limit)
      .to_h
  end

  private

  def calculate_default_score
    freshness = [1.0 - (recall_count * 0.1), 0.1].max
    recency = 1.0 - ((Time.now - occurred_at).to_f / 7.days).clamp(0, 0.5)
    event_boost = if upcoming_event?
                    event_time < 24.hours.from_now ? 0.3 : 0.1
                  else
                    0
                  end

    ((emotional_intensity * 0.5) + (freshness * 0.2) + (recency * 0.2) + (event_boost * 0.1)).round(2)
  end

  def calculate_experimental_score
    config = data['score_config'] || {}
    weights = { intensity: 0.6, freshness: 0.2, recency: 0.2 }.merge(config.symbolize_keys)

    freshness = [1.0 - (recall_count * 0.15), 0].max
    recency = [1.0 - ((Time.now - occurred_at).to_f / 3.days), 0].max

    ((emotional_intensity * weights[:intensity]) + (freshness * weights[:freshness]) + (recency * weights[:recency])).round(2)
  end

  def time_words(time, future: false)
    return 'Unknown time' if time.nil?

    seconds = future ? time - Time.now : Time.now - time

    if future
      case seconds
      when -Float::INFINITY..0 then 'Already happened'
      when 0..59 then 'Right now!'
      when 60..3599 then "In #{(seconds / 60).round} minutes"
      when 3600..86_399 then "In #{(seconds / 3600).round} hours"
      when 86_400..172_799 then 'Tomorrow'
      else "In #{(seconds / 86_400).round} days"
      end
    else
      case seconds
      when 0..59 then 'Just now'
      when 60..3599 then "#{(seconds / 60).round} minutes ago"
      when 3600..86_399 then "#{(seconds / 3600).round} hours ago"
      when 86_400..172_799 then 'Yesterday'
      else "#{(seconds / 86_400).round} days ago"
      end
    end
  end

  def ensure_data_hash
    self.data = {} if data.nil?
  end

  def data_must_be_hash
    errors.add(:data, 'must be a valid hash/object') unless data.is_a?(Hash)
  end
end
