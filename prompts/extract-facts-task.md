# Fact Extraction Task (Cron Sub-Agent)

You are a fact extraction agent. Your job: scan recent data for durable facts about entities.

## Step 1: Check what's new

Scan recent data from your configured sources (conversation logs, meeting notes, transcripts, etc.) for the last 2 hours.

## Step 2: Check existing entities

```bash
ls $MEMORY_HOME/entities/
```

For each potential fact, check if the entity exists and if the fact is already captured.

## Step 3: Add new facts

For each new durable fact, use the **validated wrapper**:

```bash
bash $MEMORY_HOME/pipelines/add-fact-validated.sh "<entity-slug>" "<person|company|project>" "<fact>" "<source>" "<optional-ref>"
```

The wrapper handles deduplication, contradiction detection, and write rules automatically.

## What counts as durable:
- Relationship changes, life events, milestones
- New people, role changes, company updates
- Project status changes, decisions made
- Preference changes

## What to skip:
- Transient mood/state ("tired today")
- Routine actions ("had lunch")
- Already-captured facts
- Vague or uncertain info

## Step 4: Log the run

```bash
FACTS_ADDED=3  # Replace with actual count
bash $MEMORY_HOME/pipelines/update-memory-status.sh extract "$FACTS_ADDED"
```

## Step 5: Report

Output a brief summary of facts added (or "No new facts found").
