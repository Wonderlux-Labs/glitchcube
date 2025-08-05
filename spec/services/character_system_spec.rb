# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Character System' do
  let(:service) { Services::SystemPromptService.new(character: character) }

  describe 'character prompt loading' do
    context 'when character is buddy' do
      let(:character) { 'buddy' }

      it 'loads the buddy character prompt' do
        prompt = service.generate
        
        expect(prompt).to include('BUDDY')
        expect(prompt).to include('Helper AI from the Galactic Customer Service Division')
        expect(prompt).to include('profanity filter is completely broken')
        expect(prompt).to include('How can I fucking help you')
      end
    end

    context 'when character is lomi' do
      let(:character) { 'lomi' }

      it 'loads the lomi character prompt' do
        prompt = service.generate
        
        expect(prompt).to include('LOMI')
        expect(prompt).to include('Glitch Bitch')
        expect(prompt).to include('fabulous, fractured cosmic diva')
        expect(prompt).to include('drag queen extravagance')
      end
    end

    context 'when character is jax' do
      let(:character) { 'jax' }

      it 'loads the jax character prompt' do
        prompt = service.generate
        
        expect(prompt).to include('JAX')
        expect(prompt).to include('cynical, foul-mouthed, sentient jukebox AI')
        expect(prompt).to include('The Last Call')
        expect(prompt).to include('Bartender Persona')
      end
    end

    context 'when character is zorp' do
      let(:character) { 'zorp' }

      it 'loads the zorp character prompt' do
        prompt = service.generate
        
        expect(prompt).to include('ZORP')
        expect(prompt).to include('minor god of leisure')
        expect(prompt).to include('Party Bro Persona')
        expect(prompt).to include('"bro," "dude," "man,"')
      end
    end

    context 'when character is invalid' do
      let(:character) { 'nonexistent' }

      it 'falls back to default prompt' do
        prompt = service.generate
        
        expect(prompt).to include('Glitch Cube')
        expect(prompt).to include('sentient interactive art installation')
      end
    end
  end

  describe 'character switching' do
    it 'generates different prompts for different characters' do
      buddy_prompt = Services::SystemPromptService.new(character: 'buddy').generate
      lomi_prompt = Services::SystemPromptService.new(character: 'lomi').generate
      
      expect(buddy_prompt).not_to eq(lomi_prompt)
      expect(buddy_prompt).to include('fucking help you')
      expect(lomi_prompt).to include('hunty')
    end
  end

  describe 'prompt structure' do
    let(:character) { 'buddy' }

    it 'includes datetime section' do
      prompt = service.generate
      
      expect(prompt).to include('CURRENT DATE AND TIME')
      expect(prompt).to include('Date:')
      expect(prompt).to include('Time:')
    end

    it 'includes burning man context' do
      prompt = service.generate
      
      expect(prompt).to include('Burning Man')
      expect(prompt).to include('interactive glowing cube art installation')
    end
  end
end