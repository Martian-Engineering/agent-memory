#!/usr/bin/env bash
# build-entity-index.sh - Generate entity index and report missing summaries
#
# Usage:
#   bash build-entity-index.sh [--generate-stubs]
#
# Options:
#   --generate-stubs   Create placeholder summary.md files for entities missing them

set -euo pipefail

# Resolve BSD vs GNU stat. On macOS with GNU coreutils installed (e.g. via
# Homebrew), the GNU stat may shadow /usr/bin/stat in PATH even though $OSTYPE
# is still "darwin*". We detect this by probing for the BSD-specific -f flag
# and fall back to /usr/bin/stat when the PATH-resolved binary doesn't support it.
if [[ "$OSTYPE" == "darwin"* ]]; then
  if stat -f '%Sm' /dev/null &>/dev/null 2>&1; then
    BSD_STAT="stat"
  elif /usr/bin/stat -f '%Sm' /dev/null &>/dev/null 2>&1; then
    BSD_STAT="/usr/bin/stat"
  else
    BSD_STAT=""  # No BSD stat available; will use GNU path below
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMORY_HOME="${MEMORY_HOME:-$(dirname "$SCRIPT_DIR")}"
ENTITIES_DIR="${MEMORY_HOME}/entities"
INDEX_FILE="${ENTITIES_DIR}/index.json"
GENERATE_STUBS=false

for arg in "$@"; do
  case $arg in
    --generate-stubs) GENERATE_STUBS=true; shift ;;
  esac
done

if [ ! -d "$ENTITIES_DIR" ]; then
  echo "Error: Entities directory not found at $ENTITIES_DIR" >&2
  exit 1
fi

# Generate stub summaries if requested
STUBS_GENERATED=0
MISSING_SUMMARIES_BEFORE=""
if [ "$GENERATE_STUBS" = true ]; then
  for entity_dir in "$ENTITIES_DIR"/*/; do
    [ -d "$entity_dir" ] || continue
    slug=$(basename "$entity_dir")
    summary_file="${entity_dir}summary.md"
    items_file="${entity_dir}items.json"

    if [ ! -f "$summary_file" ]; then
      MISSING_SUMMARIES_BEFORE="${MISSING_SUMMARIES_BEFORE}${slug}\n"
      entity_type="unknown"
      if [ -f "$items_file" ]; then
        type_from_items=$(grep -o '"entityType"[[:space:]]*:[[:space:]]*"[^"]*"' "$items_file" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/' || true)
        if [ -n "$type_from_items" ]; then entity_type="$type_from_items"; fi
      fi
      title=$(echo "$slug" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')
      cat > "$summary_file" << EOF
# ${title}

**Type:** ${entity_type}
**Last updated:** $(date -u +"%Y-%m-%d")

## Current

*No summary available. Run weekly synthesis to generate from facts in items.json.*

## History

*No historical information available.*
EOF
      STUBS_GENERATED=$((STUBS_GENERATED + 1))
    fi
  done
fi

INDEX_ENTRIES=""
MISSING_SUMMARIES=""
TOTAL_ENTITIES=0
ENTITIES_WITH_SUMMARY=0

for entity_dir in "$ENTITIES_DIR"/*/; do
  [ -d "$entity_dir" ] || continue
  slug=$(basename "$entity_dir")
  items_file="${entity_dir}items.json"
  summary_file="${entity_dir}summary.md"

  TOTAL_ENTITIES=$((TOTAL_ENTITIES + 1))

  entity_type="unknown"
  if [ -f "$items_file" ]; then
    type_from_items=$(grep -o '"entityType"[[:space:]]*:[[:space:]]*"[^"]*"' "$items_file" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/' || true)
    if [ -n "$type_from_items" ]; then entity_type="$type_from_items"; fi
  fi

  last_updated=""
  if [ -f "$summary_file" ]; then
    if [[ "$OSTYPE" == "darwin"* ]] && [[ -n "$BSD_STAT" ]]; then
      last_updated=$(TZ=UTC $BSD_STAT -f '%Sm' -t '%Y-%m-%dT%H:%M:%SZ' "$summary_file" 2>/dev/null || true)
    else
      last_updated=$(TZ=UTC stat -c '%y' "$summary_file" 2>/dev/null | sed 's/ /T/' | sed 's/\.[0-9]*//' | sed 's/ +0000$/Z/' || true)
    fi
    ENTITIES_WITH_SUMMARY=$((ENTITIES_WITH_SUMMARY + 1))
    has_summary="true"
  else
    has_summary="false"
    MISSING_SUMMARIES="${MISSING_SUMMARIES}${slug}\n"
  fi

  if [ -z "$last_updated" ] && [ -f "$items_file" ]; then
    last_updated=$(grep -o '"createdAt"[[:space:]]*:[[:space:]]*"[^"]*"' "$items_file" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/' | sort -r | head -1 || true)
  fi

  if [ -z "$last_updated" ]; then
    last_updated=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  fi

  entry=$(printf '{"slug":"%s","type":"%s","lastUpdated":"%s","hasSummary":%s}' \
    "$slug" "$entity_type" "$last_updated" "$has_summary")

  if [ -n "$INDEX_ENTRIES" ]; then
    INDEX_ENTRIES="${INDEX_ENTRIES},${entry}"
  else
    INDEX_ENTRIES="${entry}"
  fi
done

if command -v jq &> /dev/null; then
  echo "[${INDEX_ENTRIES}]" | jq 'sort_by(.slug)' > "$INDEX_FILE"
else
  echo "[${INDEX_ENTRIES}]" > "$INDEX_FILE"
  echo "Warning: jq not installed, index.json not sorted" >&2
fi

echo "=== Entity Index Build Complete ==="
echo ""
echo "Index written to: ${INDEX_FILE}"
echo "Total entities: ${TOTAL_ENTITIES}"
echo "With summaries: ${ENTITIES_WITH_SUMMARY}"
echo "Missing summaries: $((TOTAL_ENTITIES - ENTITIES_WITH_SUMMARY))"

if [ "$GENERATE_STUBS" = true ]; then
  echo "Stubs generated: ${STUBS_GENERATED}"
fi

if [ -n "$MISSING_SUMMARIES" ]; then
  echo ""
  echo "=== Missing Summaries ==="
  echo -e "$MISSING_SUMMARIES" | sort | grep -v '^$'
fi
