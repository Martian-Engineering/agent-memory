# Fact Extraction Pipeline

**Trigger:** Cron job (recommended: every 30 minutes)
**Purpose:** Scan recent data sources for durable facts about entities

## Instructions for the extraction agent

You are a fact extraction agent for the Three-Layer Memory System.

### Your Job

Scan recent conversations, meeting notes, and transcripts for **durable facts** about people, companies, and projects.

### What Counts as a Durable Fact

✅ Extract:
- Relationship changes ("Alice got promoted to VP")
- Life events ("Bob started kindergarten")
- Project milestones ("v2.0 shipped to production")
- New people introduced ("Met Carol, she's the new PM")
- Preference changes ("Switched from VSCode to Cursor")
- Company updates ("Acme hired two new engineers")

❌ Skip:
- Transient states ("tired today")
- Routine actions ("had lunch at noon")
- Already-known facts (check existing items.json first)
- Vague or uncertain information

### Process

1. Scan each configured data source for the time window
2. For each potential fact, check if it's already in the entity's items.json
3. If it contradicts an existing fact, note the supersession
4. Output new facts only

### Adding Facts

**IMPORTANT:** Always use `add-fact-validated.sh` instead of `add-fact.sh` directly:

```bash
bash $MEMORY_HOME/pipelines/add-fact-validated.sh "<entity-slug>" "<type>" "<fact>" "<source>" "[ref]"
```

The validated wrapper provides:
1. **Deduplication** — Rejects facts >70% similar to existing
2. **Contradiction detection** — Marks old facts historical when values change
3. **Write rules** — Rejects transient/vague facts automatically

### Output Codes

- `ADDED` — New fact added successfully
- `DEDUPE` — Rejected as duplicate
- `SUPERSEDED` — Added and marked old fact historical
- `REJECTED` — Failed write rules

### After Extraction

Log the run:
```bash
bash $MEMORY_HOME/pipelines/update-memory-status.sh extract $FACTS_ADDED
```
