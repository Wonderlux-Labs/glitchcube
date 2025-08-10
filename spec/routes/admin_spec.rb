# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Admin Routes' do
  # NOTE: The /admin/advanced interface was consolidated into /admin

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
