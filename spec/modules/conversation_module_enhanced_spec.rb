# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/modules/conversation_module'

RSpec.describe ConversationModule, 'enhanced features' do
  let(:module_instance) { described_class.new }
  let(:mock_home_assistant) { instance_double(HomeAssistantClient) }
  let(:mock_llm_response) do
    instance_double(
      Services::LLMResponse,
      response_text: 'Hello from Glitch Cube!',
      continue_conversation?: true,
      model: 'test-model',
      cost: 0.001,
      usage: { prompt_tokens: 10, completion_tokens: 20 }
    )
  end

  before do
    # Mock HomeAssistant client
    allow(HomeAssistantClient).to receive(:new).and_return(mock_home_assistant)
    allow(mock_home_assistant).to receive(:speak).and_return(true)
    
    # Mock LLM Service
    allow(Services::LLMService).to receive(:complete).and_return(mock_llm_response)
    
    # Mock conversation persistence
    mock_conversation = double(
      'Conversation',
      id: 'test-123',
      session_id: 'session-456',
      add_message: true,
      update_totals!: true
    )
    allow(Conversation).to receive_message_chain(:active, :find_by).and_return(nil)
    allow(Conversation).to receive(:create!).and_return(mock_conversation)
    
    # Mock services
    allow(Services::LoggerService).to receive(:log_interaction)
    allow(Services::LoggerService).to receive(:log_tts)
    
    # Mock system prompt
    mock_prompt_service = instance_double(Services::SystemPromptService)
    allow(Services::SystemPromptService).to receive(:new).and_return(mock_prompt_service)
    allow(mock_prompt_service).to receive(:generate).and_return('System prompt')
  end

  describe '#update_awtrix_display' do
    let(:message) { 'Hello there!' }
    let(:response) { 'Nice to see you!' }
    let(:persona) { 'playful' }

    before do
      allow(GlitchCube.config.home_assistant).to receive(:url).and_return('http://localhost:8123')
    end

    it 'updates AWTRIX display with persona-based colors' do
      expect(mock_home_assistant).to receive(:awtrix_display_text).with(
        'Nice to see you!',
        color: [255, 0, 255], # Magenta for playful
        duration: 5,
        rainbow: true # Rainbow for playful
      )
      
      expect(mock_home_assistant).to receive(:awtrix_mood_light).with(
        [255, 0, 255],
        brightness: 80
      )

      module_instance.send(:update_awtrix_display, message, response, persona)
      
      # Give the future a moment to execute
      sleep(0.1)
    end

    it 'truncates long responses for display' do
      long_response = 'This is a very long response that should be truncated for the AWTRIX display'
      
      expect(mock_home_assistant).to receive(:awtrix_display_text).with(
        '💭 playful...',
        anything
      )
      expect(mock_home_assistant).to receive(:awtrix_mood_light)

      module_instance.send(:update_awtrix_display, message, long_response, persona)
      sleep(0.1)
    end

    it 'uses different colors for different personas' do
      expect(mock_home_assistant).to receive(:awtrix_display_text).with(
        anything,
        hash_including(color: [0, 100, 255]) # Blue for contemplative
      )
      expect(mock_home_assistant).to receive(:awtrix_mood_light).with([0, 100, 255], anything)

      module_instance.send(:update_awtrix_display, message, response, 'contemplative')
      sleep(0.1)
    end

    it 'handles AWTRIX errors gracefully' do
      allow(mock_home_assistant).to receive(:awtrix_display_text).and_raise('AWTRIX error')
      
      expect { module_instance.send(:update_awtrix_display, message, response, persona) }.not_to raise_error
    end

    it 'skips update when HA URL not configured' do
      allow(GlitchCube.config.home_assistant).to receive(:url).and_return(nil)
      
      expect(mock_home_assistant).not_to receive(:awtrix_display_text)
      
      module_instance.send(:update_awtrix_display, message, response, persona)
    end
  end

  describe 'integration with conversation enhancements' do
    let(:context) { { include_sensors: true } }

    it 'includes conversation enhancements module' do
      expect(module_instance).to respond_to(:execute_parallel_tools)
      expect(module_instance).to respond_to(:enrich_context_with_sensors)
      expect(module_instance).to respond_to(:with_self_healing)
    end

    it 'can enrich context with sensor data' do
      allow(mock_home_assistant).to receive(:battery_level).and_return(85)
      allow(mock_home_assistant).to receive(:temperature).and_return(22.5)
      allow(mock_home_assistant).to receive(:motion_detected?).and_return(false)

      enriched = module_instance.enrich_context_with_sensors(context)

      expect(enriched[:sensor_data]).to include(
        battery: 85,
        temperature: 22.5,
        motion: false
      )
    end
  end

  describe '#call with enhancements' do
    let(:message) { 'How is the temperature?' }
    let(:context) { { include_sensors: true, persona: 'contemplative' } }

    it 'integrates all enhancements in conversation flow' do
      # Expect sensor enrichment
      expect(mock_home_assistant).to receive(:battery_level).and_return(75)
      expect(mock_home_assistant).to receive(:temperature).and_return(23.0)
      expect(mock_home_assistant).to receive(:motion_detected?).and_return(true)

      # Expect AWTRIX updates
      expect(mock_home_assistant).to receive(:awtrix_display_text)
      expect(mock_home_assistant).to receive(:awtrix_mood_light)

      result = module_instance.call(message: message, context: context)

      expect(result[:response]).to eq('Hello from Glitch Cube!')
      expect(result[:persona]).to eq('contemplative')
      expect(result[:continue_conversation]).to be true
    end

    it 'handles failures gracefully with self-healing' do
      # Simulate LLM failure then success
      call_count = 0
      allow(Services::LLMService).to receive(:complete) do
        call_count += 1
        if call_count == 1
          raise Services::LLMService::LLMError, 'Temporary error'
        else
          mock_llm_response
        end
      end

      result = module_instance.call(message: message, context: context)

      expect(result[:response]).to include('offline')
      expect(result[:error]).to eq('llm_error')
    end
  end
end