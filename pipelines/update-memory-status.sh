#!/usr/bin/env bash
# update-memory-status.sh - Log pipeline runs and update status.json
#
# Usage:
#   bash update-memory-status.sh <extract|synthesis> [facts_added]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMORY_HOME="${MEMORY_HOME:-$(dirname "$SCRIPT_DIR")}"
LOGS_DIR="${MEMORY_HOME}/logs"
STATUS_FILE="${MEMORY_HOME}/status.json"

RUN_TYPE="${1:-}"
FACTS_ADDED="${2:-0}"

if [[ -z "$RUN_TYPE" ]]; then
    echo "Usage: $0 <extract|synthesis> [facts_added]"
    exit 1
fi

if [[ "$RUN_TYPE" != "extract" && "$RUN_TYPE" != "synthesis" ]]; then
    echo "Error: run type must be 'extract' or 'synthesis'"
    exit 1
fi

mkdir -p "$LOGS_DIR"

ENTITY_COUNT=$(find "${MEMORY_HOME}/entities" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
TOTAL_FACTS=$(find "${MEMORY_HOME}/entities" -name "items.json" -exec cat {} \; 2>/dev/null | jq -s 'add | length' 2>/dev/null || echo "0")

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_FILE="${LOGS_DIR}/$(date +%Y-%m).log"

if [[ -f "$STATUS_FILE" ]]; then
    UPDATED_JSON=$(jq --arg ts "$TIMESTAMP" --arg type "$RUN_TYPE" \
                      --argjson facts "$FACTS_ADDED" --argjson entities "$ENTITY_COUNT" \
                      --argjson total "$TOTAL_FACTS" '
    if $type == "extract" then
        .lastRun.extract = $ts | .lastRun.factsAdded = ((.lastRun.factsAdded // 0) + $facts)
    else
        .lastRun.synthesis = $ts | .lastRun.factsAdded = 0
    end |
    .counts.entities = $entities | .counts.totalFacts = $total | .updatedAt = $ts
    ' "$STATUS_FILE")
else
    UPDATED_JSON=$(jq -n --arg ts "$TIMESTAMP" --arg type "$RUN_TYPE" \
                         --argjson facts "$FACTS_ADDED" --argjson entities "$ENTITY_COUNT" \
                         --argjson total "$TOTAL_FACTS" '
    {
        lastRun: {
            extract: (if $type == "extract" then $ts else null end),
            synthesis: (if $type == "synthesis" then $ts else null end),
            factsAdded: $facts
        },
        counts: { entities: $entities, totalFacts: $total },
        updatedAt: $ts
    }')
fi

echo "$UPDATED_JSON" > "$STATUS_FILE"

{
    echo "---"
    echo "[$TIMESTAMP] $RUN_TYPE run"
    echo "  entities: $ENTITY_COUNT"
    echo "  totalFacts: $TOTAL_FACTS"
    if [[ "$RUN_TYPE" == "extract" ]]; then echo "  factsAdded: $FACTS_ADDED"; fi
    if [[ "$RUN_TYPE" == "synthesis" ]]; then echo "  summariesRefreshed: $ENTITY_COUNT"; fi
} >> "$LOG_FILE"

echo "LOGGED: $RUN_TYPE run at $TIMESTAMP (entities: $ENTITY_COUNT, totalFacts: $TOTAL_FACTS)"
