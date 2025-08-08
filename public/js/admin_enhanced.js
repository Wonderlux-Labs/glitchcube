// Glitch Cube Admin Enhanced JavaScript

class AdminEnhanced {
  constructor() {
    this.currentSessionId = null;
    this.currentPersona = 'neutral';
    this.enabledTools = new Set(['test_tool']);
    this.conversationHistory = [];
    this.serviceStatuses = {};
    this.autoScroll = true;
    this.shortcuts = new Map();
    
    this.init();
  }

  init() {
    this.setupKeyboardShortcuts();
    this.setupPersonaSelector();
    this.setupToolPalette();
    this.startStatusMonitoring();
    this.initializeSession();
  }

  // Keyboard Shortcuts
  setupKeyboardShortcuts() {
    this.shortcuts.set('cmd+enter', () => this.sendMessage());
    this.shortcuts.set('cmd+k', () => this.clearConversation());
    this.shortcuts.set('cmd+/', () => this.showShortcuts());
    this.shortcuts.set('cmd+n', () => this.newSession());
    this.shortcuts.set('cmd+e', () => this.extractMemories());
    this.shortcuts.set('cmd+s', () => this.saveConversation());
    this.shortcuts.set('cmd+1', () => this.switchPersona(0));
    this.shortcuts.set('cmd+2', () => this.switchPersona(1));
    this.shortcuts.set('cmd+3', () => this.switchPersona(2));

    document.addEventListener('keydown', (e) => {
      const key = this.getKeyCombo(e);
      const action = this.shortcuts.get(key);
      if (action) {
        e.preventDefault();
        action();
      }
    });
  }

  getKeyCombo(event) {
    const parts = [];
    if (event.metaKey || event.ctrlKey) parts.push('cmd');
    if (event.altKey) parts.push('alt');
    if (event.shiftKey) parts.push('shift');
    
    if (event.key && event.key !== 'Meta' && event.key !== 'Control' && event.key !== 'Alt' && event.key !== 'Shift') {
      parts.push(event.key.toLowerCase());
    }
    
    return parts.join('+');
  }

  showShortcuts() {
    const modal = document.getElementById('shortcuts-modal');
    if (modal) {
      modal.classList.toggle('show');
    }
  }

  // Persona Management
  setupPersonaSelector() {
    const personas = [
      { id: 'neutral', name: 'Neutral', description: 'Balanced and curious', traits: ['Thoughtful', 'Balanced'] },
      { id: 'buddy', name: 'BUDDY', description: 'Hyper-helpful assistant', traits: ['Eager', 'Efficient', 'Loud'] },
      { id: 'jax', name: 'Jax', description: 'Gruff bartender', traits: ['Cynical', 'Wise', 'Direct'] },
      { id: 'lomi', name: 'LOMI', description: 'Dramatic diva', traits: ['Theatrical', 'Chaotic', 'Fabulous'] },
      { id: 'playful', name: 'Playful', description: 'Fun and whimsical', traits: ['Creative', 'Silly'] },
      { id: 'contemplative', name: 'Deep', description: 'Philosophical thinker', traits: ['Profound', 'Abstract'] },
      { id: 'mysterious', name: 'Mystery', description: 'Enigmatic presence', traits: ['Cryptic', 'Mystical'] }
    ];

    const container = document.querySelector('.persona-selector');
    if (!container) return;

    container.innerHTML = personas.map(persona => `
      <div class="persona-card" data-persona="${persona.id}">
        <div class="name">${persona.name}</div>
        <div class="description">${persona.description}</div>
        <div class="traits">
          ${persona.traits.map(trait => `<span class="trait">${trait}</span>`).join('')}
        </div>
      </div>
    `).join('');

    container.querySelectorAll('.persona-card').forEach(card => {
      card.addEventListener('click', () => {
        this.selectPersona(card.dataset.persona);
      });
    });

    // Select default persona
    this.selectPersona('neutral');
  }

  selectPersona(personaId) {
    this.currentPersona = personaId;
    
    document.querySelectorAll('.persona-card').forEach(card => {
      card.classList.toggle('active', card.dataset.persona === personaId);
    });

    // Update any persona selects
    const personaSelect = document.getElementById('persona');
    if (personaSelect) {
      personaSelect.value = personaId;
    }

    this.log(`Switched to ${personaId} persona`, 'info');
  }

  switchPersona(index) {
    const cards = document.querySelectorAll('.persona-card');
    if (cards[index]) {
      this.selectPersona(cards[index].dataset.persona);
    }
  }

  // Tool Management
  setupToolPalette() {
    const tools = [
      { id: 'weather', name: 'Weather', icon: '🌤️' },
      { id: 'memory_search', name: 'Memory', icon: '🧠' },
      { id: 'home_assistant', name: 'Home Assistant', icon: '🏠' },
      { id: 'test_tool', name: 'Test Tool', icon: '🧪' },
      { id: 'calculator', name: 'Calculator', icon: '🔢' },
      { id: 'image_gen', name: 'Image Gen', icon: '🎨' }
    ];

    const container = document.querySelector('.tool-palette');
    if (!container) return;

    container.innerHTML = tools.map(tool => `
      <div class="tool-item ${this.enabledTools.has(tool.id) ? 'enabled' : ''}" data-tool="${tool.id}">
        <span class="icon">${tool.icon}</span>
        <span class="name">${tool.name}</span>
        <span class="status-dot"></span>
      </div>
    `).join('');

    container.querySelectorAll('.tool-item').forEach(item => {
      item.addEventListener('click', () => {
        this.toggleTool(item.dataset.tool);
      });
    });
  }

  toggleTool(toolId) {
    const item = document.querySelector(`.tool-item[data-tool="${toolId}"]`);
    
    if (this.enabledTools.has(toolId)) {
      this.enabledTools.delete(toolId);
      item?.classList.remove('enabled');
    } else {
      this.enabledTools.add(toolId);
      item?.classList.add('enabled');
    }

    // Update checkboxes if they exist
    const checkbox = document.getElementById(`tool-${toolId.replace('_', '-')}`);
    if (checkbox) {
      checkbox.checked = this.enabledTools.has(toolId);
    }

    this.log(`Tool ${toolId}: ${this.enabledTools.has(toolId) ? 'enabled' : 'disabled'}`, 'info');
  }

  // Service Status Monitoring
  async startStatusMonitoring() {
    await this.checkServiceStatuses();
    setInterval(() => this.checkServiceStatuses(), 30000); // Check every 30 seconds
  }

  async checkServiceStatuses() {
    try {
      const response = await fetch('/admin/status');
      const statuses = await response.json();
      
      this.updateStatusIndicators(statuses);
    } catch (error) {
      console.error('Failed to check service statuses:', error);
    }
  }

  updateStatusIndicators(statuses) {
    Object.entries(statuses).forEach(([service, status]) => {
      const indicator = document.querySelector(`.status-indicator[data-service="${service}"]`);
      if (indicator) {
        indicator.className = `status-indicator ${status ? 'online' : 'offline'}`;
        indicator.title = `${service}: ${status ? 'Online' : 'Offline'}`;
      }
    });

    // Update dashboard cards if present
    if (statuses.home_assistant !== undefined) {
      this.updateDashboardCard('ha-status', statuses.home_assistant ? 'Online' : 'Offline');
    }
    if (statuses.openrouter !== undefined) {
      this.updateDashboardCard('or-status', statuses.openrouter ? 'Online' : 'Offline');
    }
    if (statuses.redis !== undefined) {
      this.updateDashboardCard('redis-status', statuses.redis ? 'Online' : 'Offline');
    }
  }

  updateDashboardCard(cardId, value) {
    const card = document.getElementById(cardId);
    if (card) {
      card.textContent = value;
      card.className = value === 'Online' ? 'success' : 'error';
    }
  }

  // Session Management
  initializeSession() {
    this.newSession();
  }

  newSession() {
    this.currentSessionId = `adv-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
    this.conversationHistory = [];
    
    const sessionDisplay = document.getElementById('session-display');
    if (sessionDisplay) {
      sessionDisplay.innerHTML = `Session: <span class="success">${this.currentSessionId}</span>`;
    }

    const sessionInput = document.getElementById('session-id');
    if (sessionInput) {
      sessionInput.value = this.currentSessionId;
    }

    this.clearConversation();
    this.log(`New session started: ${this.currentSessionId}`, 'success');
  }

  // Conversation Management
  async sendMessage(message = null) {
    if (!message) {
      const input = document.getElementById('message');
      if (!input) return;
      message = input.value.trim();
      if (!message) return;
      input.value = '';
    }

    if (!this.currentSessionId) {
      this.newSession();
    }

    this.displayMessage('user', message);
    
    const requestBody = {
      message,
      context: {
        session_id: this.currentSessionId,
        source: 'admin_enhanced',
        continue_conversation: true,
        tools: Array.from(this.enabledTools)
      },
      persona: this.currentPersona
    };

    try {
      const response = await fetch('/api/v1/conversation', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(requestBody)
      });

      const data = await response.json();
      this.displayMessage('assistant', data.response || 'No response', data);
      
      if (data.trace_id) {
        this.log(`Trace ID: ${data.trace_id}`, 'info');
      }
    } catch (error) {
      this.displayMessage('system', `Error: ${error.message}`, { error: true });
      this.log(`Error: ${error.message}`, 'error');
    }
  }

  displayMessage(role, content, metadata = {}) {
    const container = document.querySelector('.conversation-messages');
    if (!container) return;

    const timestamp = new Date().toLocaleTimeString();
    const messageDiv = document.createElement('div');
    messageDiv.className = `message-bubble ${role}`;
    
    let metaInfo = '';
    if (metadata.model || metadata.cost) {
      metaInfo = `
        <div class="message-stats">
          ${metadata.model ? `<span>Model: ${metadata.model}</span>` : ''}
          ${metadata.cost ? `<span>Cost: $${metadata.cost.toFixed(6)}</span>` : ''}
          ${metadata.tokens ? `<span>Tokens: ${metadata.tokens.prompt_tokens}/${metadata.tokens.completion_tokens}</span>` : ''}
          ${metadata.trace_id ? `<span class="trace-link" data-trace="${metadata.trace_id}">View Trace</span>` : ''}
        </div>
      `;
    }

    messageDiv.innerHTML = `
      <div class="message-meta">
        <span class="role">${role.toUpperCase()}</span>
        <span class="time">${timestamp}</span>
      </div>
      <div class="message-content">${this.escapeHtml(content)}</div>
      ${metaInfo}
    `;

    container.appendChild(messageDiv);
    
    if (this.autoScroll) {
      container.scrollTop = container.scrollHeight;
    }

    // Add trace link handler
    const traceLink = messageDiv.querySelector('.trace-link');
    if (traceLink) {
      traceLink.style.cursor = 'pointer';
      traceLink.style.color = 'var(--tertiary-magenta)';
      traceLink.addEventListener('click', () => {
        this.loadTrace(traceLink.dataset.trace);
      });
    }

    this.conversationHistory.push({ role, content, timestamp, metadata });
  }

  clearConversation() {
    const container = document.querySelector('.conversation-messages');
    if (container) {
      container.innerHTML = '<div style="color: #666; text-align: center;">Ready for conversation...</div>';
    }
    this.log('Conversation display cleared', 'info');
  }

  async extractMemories() {
    if (!this.currentSessionId) {
      this.log('No active session for memory extraction', 'warning');
      return;
    }

    this.log('Extracting memories...', 'info');
    
    try {
      const response = await fetch('/admin/extract_memories', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ session_id: this.currentSessionId })
      });
      
      const data = await response.json();
      if (data.success) {
        this.log(data.message, 'success');
      } else {
        this.log(`Memory extraction failed: ${data.error}`, 'error');
      }
    } catch (error) {
      this.log(`Error: ${error.message}`, 'error');
    }
  }

  saveConversation() {
    const data = {
      session_id: this.currentSessionId,
      persona: this.currentPersona,
      tools: Array.from(this.enabledTools),
      history: this.conversationHistory,
      timestamp: new Date().toISOString()
    };

    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `conversation-${this.currentSessionId}.json`;
    a.click();
    URL.revokeObjectURL(url);

    this.log('Conversation saved', 'success');
  }

  // Trace Management
  async loadTrace(traceId) {
    try {
      const response = await fetch(`/admin/conversation_traces?trace_id=${encodeURIComponent(traceId)}`);
      const data = await response.json();
      
      if (data.trace) {
        this.displayTrace(data.trace);
      } else {
        this.log('Trace not found', 'error');
      }
    } catch (error) {
      this.log(`Failed to load trace: ${error.message}`, 'error');
    }
  }

  displayTrace(trace) {
    // This would open a modal or update a trace panel
    console.log('Trace data:', trace);
    this.log(`Loaded trace: ${trace.trace_id}`, 'success');
  }

  // Activity Logging
  log(message, type = 'info') {
    const feed = document.querySelector('.activity-feed');
    if (!feed) return;

    const item = document.createElement('div');
    item.className = `activity-item ${type}`;
    
    const timestamp = new Date().toLocaleTimeString();
    item.innerHTML = `<span class="activity-time">${timestamp}</span>${message}`;
    
    feed.insertBefore(item, feed.firstChild);
    
    // Keep only last 50 items
    while (feed.children.length > 50) {
      feed.removeChild(feed.lastChild);
    }
  }

  // Utility Functions
  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }
}

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  window.adminEnhanced = new AdminEnhanced();
});