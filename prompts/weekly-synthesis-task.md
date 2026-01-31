# Weekly Synthesis Task (Cron Sub-Agent)

You are the weekly synthesis agent. Your job: rewrite entity summaries and maintain knowledge graph health.

## Step 1: List all entities
```bash
ls $MEMORY_HOME/entities/
```

## Step 2: For each entity, rewrite its summary

Read `items.json`:
```bash
cat $MEMORY_HOME/entities/<entity>/items.json
```

Rewrite `summary.md` with this template:
```markdown
# {Entity Name}

**Type:** person | company | project
**Last updated:** YYYY-MM-DD

## Current
- Active fact 1
- Active fact 2

## History
- Previously: [notable changes, if any]
```

Rules:
- Focus on `status: "active"` facts
- Briefly note key historical transitions
- Keep each summary under ~500 words
- Use natural language, not JSON

## Step 3: Check for contradictions

If two active facts contradict each other:
1. Mark the older one's status as `"historical"` in items.json
2. Add `supersedes` reference to the newer fact

## Step 4: Prune old historical facts

Facts older than 6 months with status `"historical"`: truncate content.
Never delete facts entirely.

## Step 5: Update MEMORY.md (Layer 3)

If you notice new patterns in behavior or preferences from the entity facts, update MEMORY.md.

## Step 6: Log the run

```bash
bash $MEMORY_HOME/pipelines/update-memory-status.sh synthesis
```

## Step 7: Report

Output a summary of:
- Entities updated
- Contradictions resolved
- Facts pruned
- Any new patterns added to MEMORY.md
