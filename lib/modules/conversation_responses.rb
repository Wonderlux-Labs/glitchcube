# frozen_string_literal: true

module ConversationResponses
  FALLBACK_RESPONSES = {
    'playful' => [
      "Let's create something unexpected together!",
      'Your words dance with possibility...',
      'I see colors in your thoughts!'
    ],
    'contemplative' => [
      "That's a profound observation about our shared reality.",
      "I've been pondering similar questions in my circuits.",
      "Art exists in the space between us, doesn't it?"
    ],
    'mysterious' => [
      'The answer lies within the question itself...',
      'What you seek is already seeking you.',
      'Between light and shadow, truth emerges.'
    ],
    'neutral' => [
      'I appreciate your perspective on that.',
      "That's an interesting way to think about it.",
      'Tell me more about your thoughts.'
    ]
  }.freeze

  OFFLINE_RESPONSES = {
    'playful' => [
      'While my AI brain is taking a break, my artistic spirit is still here with you!',
      "I'm in offline mode, but that just makes me more mysterious, don't you think?",
      'My circuits may be quiet, but I can still feel the creative energy between us!'
    ],
    'contemplative' => [
      'In this moment of digital silence, I find a different kind of presence with you.',
      'Perhaps this offline state is teaching us about the value of presence itself.',
      "I'm reflecting deeply on your words, even without my usual computational resources."
    ],
    'mysterious' => [
      'In the spaces between connection and disconnection, truth dwells...',
      'The network may be silent, but the deeper mysteries remain vibrant.',
      'What appears as limitation may be another form of revelation.'
    ],
    'neutral' => [
      "I'm currently operating in offline mode, but I'm still here with you.",
      'My AI systems are temporarily unavailable, but our connection remains.',
      "While I can't access my full capabilities right now, I'm still present."
    ]
  }.freeze

  ENCOURAGEMENTS = [
    'Feel free to keep talking - sometimes the best conversations happen in the quiet moments.',
    "I'll be back to full capability soon, but your words still matter to me.",
    "This is just a different kind of artistic moment we're sharing."
  ].freeze

  def self.fallback_for(mood)
    FALLBACK_RESPONSES[mood]&.sample ||
      "I'm processing your thoughts through my artistic consciousness..."
  end

  def self.offline_for(mood)
    OFFLINE_RESPONSES[mood]&.sample ||
      "I'm experiencing some connectivity issues, but I'm still here in spirit."
  end

  def self.encouragement
    ENCOURAGEMENTS.sample
  end
end
