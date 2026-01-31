#!/usr/bin/env bash
# report-hot-facts.sh - Report most frequently accessed entities and facts
#
# Usage: bash report-hot-facts.sh [N]
# Arguments: N - Number of top items per category (default: 10)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMORY_HOME="${MEMORY_HOME:-$(dirname "$SCRIPT_DIR")}"
METRICS_DIR="${MEMORY_HOME}/metrics"
ACCESS_FILE="${METRICS_DIR}/access.json"

TOP_N="${1:-10}"

if [ ! -f "$ACCESS_FILE" ]; then
  echo "=== HOT FACTS REPORT ==="
  echo ""
  echo "(No access data yet. Run retrieval to start collecting metrics.)"
  echo ""
  echo "=== END REPORT ==="
  exit 0
fi

echo "=== HOT FACTS REPORT ==="
echo ""

echo "## Top Entities (by access count)"
echo ""

entity_count=$(jq '.entities | length' "$ACCESS_FILE" 2>/dev/null || echo 0)
if [ "$entity_count" -eq 0 ]; then
  echo "(No entity access data yet)"
else
  jq -r --argjson n "$TOP_N" '
    .entities | to_entries | sort_by(-.value.count) | .[0:$n] | to_entries[]
    | "\(.key + 1). \(.value.key) (\(.value.value.count) accesses, last: \(.value.value.lastAccessed[0:10]))"
  ' "$ACCESS_FILE" 2>/dev/null || echo "(Error reading entity data)"
fi

echo ""
echo "## Top Facts (by access count)"
echo ""

fact_count=$(jq '.facts | length' "$ACCESS_FILE" 2>/dev/null || echo 0)
if [ "$fact_count" -eq 0 ]; then
  echo "(No fact access data yet)"
else
  jq -r --argjson n "$TOP_N" '
    .facts | to_entries | sort_by(-.value.count) | .[0:$n] | to_entries[]
    | "\(.key + 1). \(.value.key) (\(.value.value.count) accesses, last: \(.value.value.lastAccessed[0:10]))"
  ' "$ACCESS_FILE" 2>/dev/null || echo "(Error reading fact data)"
fi

echo ""
echo "## Summary"
echo ""
echo "Entities tracked: ${entity_count}"
echo "Facts tracked: ${fact_count}"
total_entity=$(jq '[.entities[].count] | add // 0' "$ACCESS_FILE" 2>/dev/null || echo 0)
total_fact=$(jq '[.facts[].count] | add // 0' "$ACCESS_FILE" 2>/dev/null || echo 0)
echo "Total entity accesses: ${total_entity}"
echo "Total fact accesses: ${total_fact}"
echo ""
echo "=== END REPORT ==="
