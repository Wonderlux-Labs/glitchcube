# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Admin Routes' do
  describe 'GET /admin/advanced' do
    it 'loads the advanced admin page' do
      get '/admin/advanced'

      expect(last_response).to be_ok
      expect(last_response.body).to include('GLITCH CUBE ADVANCED TESTING')
    end

    it 'includes session management panel' do
      get '/admin/advanced'

      expect(last_response.body).to include('Session Management')
      expect(last_response.body).to include('New Session')
      expect(last_response.body).to include('Extract Memories')
    end

    it 'includes conversation testing panel' do
      get '/admin/advanced'

      expect(last_response.body).to include('Advanced Conversation Testing')
      expect(last_response.body).to include('Enable Tools:')
      expect(last_response.body).to include('Send Message')
    end

    it 'includes memory management panel' do
      get '/admin/advanced'

      expect(last_response.body).to include('Memory Management')
      expect(last_response.body).to include('Recent')
      expect(last_response.body).to include('Search')
      expect(last_response.body).to include('Popular')
    end

    it 'includes JavaScript for functionality' do
      get '/admin/advanced'

      expect(last_response.body).to include('newSession()')
      expect(last_response.body).to include('extractMemories()')
      expect(last_response.body).to include('loadMemories(')
    end

    it 'has proper content type' do
      get '/admin/advanced'

      expect(last_response.content_type).to include('text/html')
    end
  end

  describe 'GET /admin' do
    it 'loads the main admin page' do
      get '/admin'

      expect(last_response).to be_ok
      expect(last_response.body).to include('Glitch Cube Admin')
    end
  end

  describe 'GET /admin/errors' do
    it 'loads the errors page' do
      get '/admin/errors'

      expect(last_response).to be_ok
      expect(last_response.body).to include('error')
    end
  end
end
