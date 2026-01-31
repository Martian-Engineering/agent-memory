# 🧠 Agent Memory

**A three-layer persistent memory system for AI agents.**

Knowledge graph + daily notes + tacit knowledge, with automated fact extraction, contradiction detection, and recency-scored retrieval. Built in bash, no dependencies beyond `jq`.

> **Key insight:** Memory is infrastructure, not a feature. Embeddings measure similarity, not truth. You need structure, timestamps, and maintenance.

Inspired by [@rohit4verse's architecture](https://x.com/rohit4verse/status/2012925228159295810).

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  RETRIEVAL LAYER                     │
│  retrieve-memory.sh                                  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐ │
│  │ Entity   │→│ Summary  │→│ Fact     │→│ Daily  │ │
│  │ Match    │ │ Load     │ │ Search   │ │ Notes  │ │
│  └──────────┘ └──────────┘ └──────────┘ └────────┘ │
│        Cascading stages with recency scoring         │
└───────────────────────┬─────────────────────────────┘
                        │
┌───────────────────────┼─────────────────────────────┐
│                 STORAGE LAYERS                        │
│                                                       │
│  Layer 1: Knowledge Graph    memory/entities/         │
│  ┌──────────────────────────────────────────┐        │
│  │  alice/items.json    ← atomic facts      │        │
│  │  alice/summary.md    ← weekly snapshot    │        │
│  │  acme-corp/items.json                     │        │
│  │  acme-corp/summary.md                     │        │
│  │  index.json          ← metadata index     │        │
│  └──────────────────────────────────────────┘        │
│                                                       │
│  Layer 2: Daily Notes        memory/YYYY-MM-DD.md    │
│  ┌──────────────────────────────────────────┐        │
│  │  Raw timeline. Written continuously.      │        │
│  │  Durable facts extracted → Layer 1        │        │
│  └──────────────────────────────────────────┘        │
│                                                       │
│  Layer 3: Tacit Knowledge    MEMORY.md               │
│  ┌──────────────────────────────────────────┐        │
│  │  How your human operates. Preferences,    │        │
│  │  patterns, communication style.           │        │
│  └──────────────────────────────────────────┘        │
└───────────────────────┬─────────────────────────────┘
                        │
┌───────────────────────┼─────────────────────────────┐
│              COMPOUNDING ENGINE                       │
│                                                       │
│  Extraction (every 30 min)    Synthesis (weekly)     │
│  ┌────────────────────┐      ┌────────────────────┐ │
│  │ Scan sources        │      │ Rewrite summaries  │ │
│  │ Extract facts       │      │ Resolve conflicts  │ │
│  │ Dedup + validate    │      │ Prune old facts    │ │
│  │ Detect conflicts    │      │ Update MEMORY.md   │ │
│  └────────────────────┘      └────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

---

## Quick Start

```bash
# Clone the repo
git clone https://github.com/Martian-Engineering/agent-memory.git
cd agent-memory

# Bootstrap the memory directory
bash setup.sh ~/my-workspace/memory

# Add your first fact
bash ~/my-workspace/memory/pipelines/add-fact.sh alice person "Alice is the lead engineer at Acme Corp" manual

# Add a relationship edge
bash ~/my-workspace/memory/pipelines/add-edge.sh alice person "Alice works at Acme Corp" works_at acme-corp manual

# Build the entity index
bash ~/my-workspace/memory/pipelines/build-entity-index.sh

# Retrieve context
bash ~/my-workspace/memory/pipelines/retrieve-memory.sh "what does alice do"
```

### Environment

Set `MEMORY_HOME` to point at your memory directory:

```bash
export MEMORY_HOME=~/my-workspace/memory
```

All scripts auto-detect paths from their own location, but `MEMORY_HOME` overrides when set.

---

## The Three Layers

### Layer 1: Knowledge Graph (`memory/entities/`)

Every important person, company, or project gets a folder:

```
memory/entities/
  alice/
    items.json    ← timestamped atomic facts
    summary.md    ← weekly-rewritten snapshot
  acme-corp/
    items.json
    summary.md
  index.json      ← metadata for all entities
```

**Atomic facts** are the source of truth:

```json
{
  "id": "uuid",
  "content": "Alice got promoted to VP of Engineering",
  "source": "conversation",
  "sourceRef": "session-123",
  "entityType": "person",
  "createdAt": "2026-01-28T23:00:00Z",
  "status": "active",
  "supersedes": null,
  "edge": null
}
```

**Nothing is ever deleted.** When facts change, the old fact is marked `historical` and the new one links back via `supersedes`. The knowledge graph preserves how understanding evolves.

**Optional structured edges** enable graph traversal:

```json
{
  "content": "Alice works at Acme Corp",
  "edge": {
    "subject": "alice",
    "predicate": "works_at",
    "object": "acme-corp"
  }
}
```

### Layer 2: Daily Notes (`memory/YYYY-MM-DD.md`)

The raw timeline. Write continuously throughout the day — session notes, decisions, context. Durable facts are extracted into Layer 1 by the automated pipeline.

### Layer 3: Tacit Knowledge (`MEMORY.md`)

Not facts about the world — facts about your human. Communication preferences, work patterns, tool preferences. Updated manually or by synthesis when patterns emerge.

---

## The Compounding Engine

Two automated processes maintain the system:

### Fact Extraction (recommended: every 30 minutes)

Scans your data sources (conversation logs, meeting notes, transcripts) for durable facts. Uses the validated wrapper for automatic deduplication and contradiction detection.

See [`prompts/extract-facts.md`](prompts/extract-facts.md) for the extraction prompt template.

### Weekly Synthesis

For each entity:
1. Reviews all facts in `items.json`
2. Rewrites `summary.md` with current state
3. Marks contradicting facts as historical
4. Prunes old historical facts (truncates, never deletes)
5. Updates `MEMORY.md` if new patterns emerge

See [`prompts/weekly-synthesis.md`](prompts/weekly-synthesis.md) for the synthesis prompt template.

---

## Retrieval

### Tiered Retrieval with Recency Scoring

```bash
bash memory/pipelines/retrieve-memory.sh "what is alice working on"
```

**Cascading stages:**

1. **Entity matching** — Searches `index.json` for entities matching query terms
2. **Summary loading** — Loads `summary.md` for matched entities (up to 5), sorted by recency
3. **Fact search** — If insufficient results, searches all `items.json` for matching active facts (up to 10)
4. **Daily notes fallback** — If still insufficient, searches recent daily notes (last 7 days)

**Recency scoring** uses exponential time decay:

```
score = e^(-λ × days_old)    where λ = ln(2) / half_life
```

| Age | Score |
|-----|-------|
| Today | 1.000 |
| 1 day | 0.977 |
| 1 week | 0.871 |
| 30 days (half-life) | 0.500 |
| 60 days | 0.250 |
| 90 days | 0.125 |

Configure via `RECENCY_HALF_LIFE_DAYS` (default: 30).

### Access Frequency Tracking

The retrieval tool logs which entities and facts get accessed most often:

```bash
bash memory/pipelines/report-hot-facts.sh
```

---

## Fact Validation

`add-fact-validated.sh` wraps fact insertion with three safety layers:

1. **Deduplication** — Jaccard similarity (word overlap). Facts >70% similar to existing active facts are rejected.
2. **Contradiction detection** — Anchor pattern matching. When "Alice works at X" arrives and "Alice works at Y" already exists, the old fact is automatically marked `historical`.
3. **Write rules** — Rejects low-signal facts: too short (<15 chars), transient states ("is tired"), vague language ("might be", "probably").

```bash
# All four outcomes:
bash pipelines/add-fact-validated.sh alice person "Alice joined Acme as CTO" conversation
# → ADDED: Added fact abc-123 to alice

bash pipelines/add-fact-validated.sh alice person "Alice joined Acme as CTO" conversation
# → DEDUPE: New fact is 1.00 similar to existing: "Alice joined Acme as CTO..."

bash pipelines/add-fact-validated.sh alice person "Alice works at NewCorp now" conversation
# → SUPERSEDED: Added fact def-456, marked abc-123 historical

bash pipelines/add-fact-validated.sh alice person "Alice is tired" conversation
# → REJECTED: Contains transient/vague pattern: 'is tired'
```

---

## Time Decay

The system implements **two complementary decay mechanisms:**

### Semantic Decay (Synthesis Time)

- New facts contradicting old ones mark the older fact `historical`
- Weekly synthesis rewrites summaries focusing on `active` facts
- Historical facts get brief mentions ("Previously worked at X, now at Y")
- Facts older than 6 months with `historical` status get content truncated

### Recency Scoring (Retrieval Time)

Exponential time decay ensures newer facts surface first in search results:

```
score = e^(-λ × days_old)    where λ = ln(2) / 30
```

**Why both:** Semantic decay adds LLM judgment about relevance. Recency scoring adds temporal ordering. A fact from 3 months ago that was never contradicted should rank higher than a trivial fact from yesterday.

---

## File Structure

```
agent-memory/
  README.md                          ← This file
  LICENSE                            ← MIT
  setup.sh                           ← Bootstrap script

  pipelines/
    add-fact.sh                      ← Low-level fact insertion
    add-fact-validated.sh            ← Validated wrapper (use this)
    add-edge.sh                      ← Structured relationship edges
    retrieve-memory.sh               ← Tiered retrieval + recency scoring
    build-entity-index.sh            ← Rebuild index.json
    checkpoint-save.sh               ← Save session state
    checkpoint-load.sh               ← Load session state
    report-hot-facts.sh              ← Access frequency reports
    update-memory-status.sh          ← Maintenance logging

  prompts/
    extract-facts.md                 ← Extraction pipeline docs
    extract-facts-task.md            ← Extraction cron task
    weekly-synthesis.md              ← Synthesis pipeline docs
    weekly-synthesis-task.md         ← Synthesis cron task

  templates/
    entities/
      README.md                      ← Schema documentation
      index.json                     ← Empty starter
    MEMORY-template.md               ← Layer 3 template
```

---

## Requirements

- **bash** (4.0+)
- **jq** — JSON processing
- **uuidgen** — Fact ID generation (available on macOS and most Linux)

No cloud services, no API keys, no database. Just files.

---

## Credits

Architecture inspired by [@rohit4verse's thread](https://x.com/rohit4verse/status/2012925228159295810) on persistent memory for AI agents (January 2026).

Built by [Martian Engineering](https://martian.engineering).

## License

MIT
