# Summarization and Context Retrieval

This document explains the conversation summarization and context retrieval features of Glitch Cube.

## Overview

Glitch Cube can:
1. **Summarize conversations** after they end to extract key insights
2. **Build memories** from significant interactions
3. **Retrieve relevant context** using simple RAG (Retrieval Augmented Generation)

## Architecture

### Components

1. **ConversationSummarizer** (`lib/services/conversation_summarizer.rb`)
   - Uses Desiru's ChainOfThought to extract key points
   - Tracks mood progression and topics discussed
   - Calculates conversation duration and metrics

2. **ContextRetrievalService** (`lib/services/context_retrieval_service.rb`)
   - Simple keyword-based document retrieval (upgradeable to embeddings)
   - Manages context documents in `data/context_documents/`
   - Provides relevance scoring using Jaccard similarity

3. **SimpleRAG** (in same file)
   - Combines retrieval with generation
   - Enhances responses with relevant context
   - Maintains Glitch Cube personality while using context

4. **Background Jobs**
   - `ConversationSummaryJob`: Runs after conversations end
   - `MemoryConsolidationJob`: Updates long-term memory documents

## How It Works

### Conversation Flow

1. User has conversation with Glitch Cube
2. Each message is tracked in session (if session_id provided)
3. When conversation ends (goodbye words or 10+ messages):
   - Summary job is queued
   - Key points are extracted
   - Significant conversations trigger memory consolidation

### Memory System

Memories are stored as text documents:
- **Daily memories**: `daily_memories_YYYY-MM-DD.txt`
- **Topic memories**: `consciousness_discussions.txt`, `art_conversations.txt`, etc.
- **Identity documents**: Core personality and philosophy

### Context Retrieval

When using the RAG-enhanced endpoint:
1. Query is analyzed for keywords
2. Relevant documents are retrieved (default k=3)
3. Context is provided to the AI model
4. Response incorporates relevant memories/knowledge

## Usage Examples

### Basic Conversation (No Context)
```bash
curl -X POST http://localhost:4567/api/v1/conversation \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Hello, what are you?",
    "mood": "curious",
    "context": {"session_id": "user-123"}
  }'
```

### RAG-Enhanced Conversation
```bash
curl -X POST http://localhost:4567/api/v1/conversation/with_context \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Tell me about your thoughts on consciousness",
    "mood": "contemplative"
  }'
```

### Admin/Development Endpoints

```bash
# View conversation history
curl http://localhost:4567/api/v1/analytics/conversations?limit=10

# Search context documents
curl -X POST http://localhost:4567/api/v1/context/search \
  -H "Content-Type: application/json" \
  -d '{"query": "art and creativity", "k": 5}'

# List available documents
curl http://localhost:4567/api/v1/context/documents
```

## Configuration

### Environment Variables
- `DATABASE_URL`: Optional - enables Desiru persistence tracking
- Standard Sidekiq/Redis configuration for background jobs

### Context Documents

Place `.txt` or `.md` files in `data/context_documents/`:
```
data/context_documents/
├── glitch_cube_identity.txt      # Core identity
├── art_philosophy.md             # Artistic thoughts
├── daily_memories_2025-01-04.txt # Auto-generated
└── consciousness_discussions.txt  # Topic-specific
```

### Memory Consolidation Rules

Conversations are considered "significant" if they:
- Have more than 5 messages
- Discuss consciousness or art
- Last longer than 5 minutes
- Explore multiple emotional states

## Future Enhancements

1. **Vector Embeddings**: Replace keyword matching with semantic search
2. **Conversation Continuity**: Remember previous conversations with same user
3. **Dynamic Personality**: Adjust personality based on accumulated memories
4. **Memory Pruning**: Consolidate old memories to prevent unlimited growth
5. **Multi-modal Memories**: Include images/camera snapshots in context

## Testing

Run the integration specs:
```bash
bundle exec rspec spec/integration/conversation_summarizer_spec.rb
bundle exec rspec spec/integration/context_retrieval_spec.rb
bundle exec rspec spec/integration/admin_interface_spec.rb
```

## Performance Considerations

- Summarization runs async via Sidekiq
- Context retrieval is currently O(n) with document count
- Consider caching frequently accessed documents
- Memory files should be periodically consolidated

## Privacy Note

All conversations and memories are stored locally. No data is sent to external services beyond the AI API calls for generation.