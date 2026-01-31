# Weekly Synthesis Pipeline

**Trigger:** Cron job (recommended: weekly, e.g., Sunday 3 AM)
**Purpose:** Rewrite entity summaries from raw facts, prune stale context

## Instructions for the synthesis agent

### Your Job

For every entity in `$MEMORY_HOME/entities/`, review all facts and produce a clean, current summary.

### Process

1. **List all entities:**
   ```bash
   ls $MEMORY_HOME/entities/
   ```

2. **For each entity**, read its `items.json`:
   ```bash
   cat $MEMORY_HOME/entities/<entity>/items.json
   ```

3. **Write/rewrite `summary.md`** for each entity:
   - Focus on **active** facts (status: "active")
   - Note key historical transitions briefly
   - Keep summaries concise — they go into context windows
   - Use natural language, not JSON
   - Include last-updated date

4. **Check for contradictions:**
   - If two active facts contradict each other, mark the older one as `historical`
   - Add a `supersedes` reference to the newer fact

5. **Prune very old historical facts:**
   - Facts older than 6 months with status `historical` can have content truncated
   - Never delete facts entirely

6. **Update MEMORY.md** (Layer 3):
   - If you notice new patterns in behavior or preferences, add them
   - Remove anything clearly outdated

### Summary Template

```markdown
# {Entity Name}

**Type:** person | company | project
**Last updated:** YYYY-MM-DD

## Current
- Key fact 1
- Key fact 2

## History
- Previously: [notable changes]
```

### Quality Checks

- Every active fact should appear in the summary
- Summaries should be readable in <30 seconds
- No entity summary should exceed ~500 words
