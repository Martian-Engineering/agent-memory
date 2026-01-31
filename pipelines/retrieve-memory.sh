#!/usr/bin/env bash
# retrieve-memory.sh - Tiered memory retrieval for context injection
#
# Usage:
#   bash retrieve-memory.sh "<user query>"
#
# Environment:
#   MEMORY_HOME              — Root of memory directory (default: auto-detect from script location)
#   RECENCY_HALF_LIFE_DAYS   — Half-life for decay scoring (default: 30)
#
# Retrieval stages (cascading):
#   1. Select relevant entity summaries using entities/index.json
#   2. Load those summaries and check if sufficient
#   3. If insufficient, search items.json for matching facts
#   4. If still insufficient, fall back to daily notes
#
# Output:
#   A compact "memory context" block suitable for injection into prompts.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMORY_HOME="${MEMORY_HOME:-$(dirname "$SCRIPT_DIR")}"
ENTITIES_DIR="${MEMORY_HOME}/entities"
INDEX_FILE="${ENTITIES_DIR}/index.json"
METRICS_DIR="${MEMORY_HOME}/metrics"
ACCESS_FILE="${METRICS_DIR}/access.json"

# ========================================
# Helper: Log access to metrics file
# ========================================
log_access() {
  local access_type="$1"
  local key="$2"

  mkdir -p "$METRICS_DIR"
  [ -f "$ACCESS_FILE" ] || echo '{"entities":{},"facts":{}}' > "$ACCESS_FILE"

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local tmp_file="${ACCESS_FILE}.tmp"

  if [ "$access_type" = "entity" ]; then
    jq --arg key "$key" --arg ts "$now" '
      .entities[$key] = {
        count: ((.entities[$key].count // 0) + 1),
        lastAccessed: $ts
      }
    ' "$ACCESS_FILE" > "$tmp_file" && mv "$tmp_file" "$ACCESS_FILE"
  elif [ "$access_type" = "fact" ]; then
    jq --arg key "$key" --arg ts "$now" '
      .facts[$key] = {
        count: ((.facts[$key].count // 0) + 1),
        lastAccessed: $ts
      }
    ' "$ACCESS_FILE" > "$tmp_file" && mv "$tmp_file" "$ACCESS_FILE"
  fi
}

# Thresholds
MIN_ENTITIES=1
MIN_TOTAL_RESULTS=3
MAX_SUMMARIES=5
MAX_FACTS=10
MAX_DAILY_SNIPPETS=5
DAILY_NOTES_LOOKBACK_DAYS=7

# Recency scoring
RECENCY_HALF_LIFE_DAYS="${RECENCY_HALF_LIFE_DAYS:-30}"

# ========================================
# Stopwords for query synthesis
# ========================================
STOPWORDS=(
  "a" "an" "the" "and" "or" "but" "in" "on" "at" "to" "for"
  "of" "with" "by" "from" "as" "is" "was" "are" "were" "been"
  "be" "have" "has" "had" "do" "does" "did" "will" "would"
  "could" "should" "may" "might" "must" "shall" "can" "need"
  "it" "its" "this" "that" "these" "those" "i" "you" "he" "she"
  "we" "they" "what" "which" "who" "whom" "where" "when" "why" "how"
  "all" "each" "every" "both" "few" "more" "most" "other" "some"
  "such" "no" "not" "only" "same" "so" "than" "too" "very"
  "just" "also" "now" "here" "there" "then" "once" "any" "about"
  "me" "my" "your" "his" "her" "our" "their" "if" "because"
)

is_stopword() {
  local word="$1"
  for sw in "${STOPWORDS[@]}"; do
    if [ "$word" = "$sw" ]; then return 0; fi
  done
  return 1
}

synthesize_query() {
  local query="$1"
  local result=()
  for word in $query; do
    if ! is_stopword "$word"; then
      if [ ${#word} -ge 2 ]; then
        result+=("$word")
      fi
    fi
  done
  echo "${result[*]}"
}

# ========================================
# Helper: Recency score (exponential decay)
# score = e^(-λ * days_old) where λ = ln(2)/half_life
# ========================================
recency_score() {
  local timestamp="$1"
  local now_epoch days_old score

  now_epoch=$(date +%s)

  if [[ "$timestamp" =~ ^[0-9]+$ ]]; then
    local ts_epoch="$timestamp"
  else
    if [[ "$OSTYPE" == "darwin"* ]]; then
      ts_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" +%s 2>/dev/null || \
                 date -j -f "%Y-%m-%d" "$timestamp" +%s 2>/dev/null || echo "$now_epoch")
    else
      ts_epoch=$(date -d "$timestamp" +%s 2>/dev/null || echo "$now_epoch")
    fi
  fi

  days_old=$(( (now_epoch - ts_epoch) / 86400 ))
  [ $days_old -lt 0 ] && days_old=0

  score=$(awk -v days="$days_old" -v half_life="$RECENCY_HALF_LIFE_DAYS" \
    'BEGIN { lambda = 0.693147 / half_life; printf "%.3f", exp(-lambda * days) }')

  echo "$score"
}

# ========================================
# Usage check
# ========================================
if [ $# -lt 1 ]; then
  echo "Usage: bash $(basename "$0") \"<user query>\"" >&2
  exit 1
fi

QUERY="$1"
QUERY_LOWER=$(echo "$QUERY" | tr '[:upper:]' '[:lower:]')
SYNTHESIZED_QUERY=$(synthesize_query "$QUERY_LOWER")

if [ -z "$SYNTHESIZED_QUERY" ]; then
  SYNTHESIZED_QUERY="$QUERY_LOWER"
fi

IFS=' ' read -ra QUERY_TERMS <<< "$SYNTHESIZED_QUERY"

matches_query() {
  local text="$1"
  local text_lower
  text_lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')
  for term in "${QUERY_TERMS[@]}"; do
    if [ ${#term} -lt 3 ]; then continue; fi
    if [[ "$text_lower" == *"$term"* ]]; then return 0; fi
  done
  return 1
}

# ========================================
# Stage 1: Find relevant entities from index
# ========================================
MATCHED_ENTITIES_WITH_SCORES=""
ENTITY_SUMMARIES=""
ENTITY_COUNT=0

if [ -f "$INDEX_FILE" ]; then
  while IFS= read -r line; do
    slug=$(echo "$line" | cut -d'|' -f1)
    type=$(echo "$line" | cut -d'|' -f2)
    last_updated=$(echo "$line" | cut -d'|' -f3)

    if matches_query "$slug" || matches_query "$type"; then
      score=$(recency_score "$last_updated")
      MATCHED_ENTITIES_WITH_SCORES="${MATCHED_ENTITIES_WITH_SCORES}${score}|${slug}\n"
    fi
  done < <(jq -r '.[] | "\(.slug)|\(.type)|\(.lastUpdated)"' "$INDEX_FILE" 2>/dev/null || true)
fi

SORTED_ENTITIES=""
if [ -n "$MATCHED_ENTITIES_WITH_SCORES" ]; then
  SORTED_ENTITIES=$(echo -e "$MATCHED_ENTITIES_WITH_SCORES" | sort -t'|' -k1 -rn | grep -v '^$')
fi

# ========================================
# Stage 2: Load summaries for matched entities
# ========================================
if [ -n "$SORTED_ENTITIES" ]; then
  while IFS='|' read -r score slug; do
    [ -n "$slug" ] || continue
    if [ $ENTITY_COUNT -ge $MAX_SUMMARIES ]; then break; fi

    summary_file="${ENTITIES_DIR}/${slug}/summary.md"
    if [ -f "$summary_file" ]; then
      summary_content=$(head -50 "$summary_file" 2>/dev/null || true)
      if [ -n "$summary_content" ]; then
        ENTITY_SUMMARIES="${ENTITY_SUMMARIES}### ${slug} (recency: ${score})\n${summary_content}\n\n"
        ENTITY_COUNT=$((ENTITY_COUNT + 1))
        log_access "entity" "$slug"
      fi
    fi
  done <<< "$SORTED_ENTITIES"
fi

STAGE2_SUFFICIENT=false
if [ $ENTITY_COUNT -ge $MIN_ENTITIES ]; then
  STAGE2_SUFFICIENT=true
fi

# ========================================
# Stage 3: Search items.json for matching facts
# ========================================
MATCHING_FACTS=""
FACT_COUNT=0
TOTAL_RESULTS=$ENTITY_COUNT
FACTS_WITH_SCORES=""

if [ "$STAGE2_SUFFICIENT" = false ] || [ $TOTAL_RESULTS -lt $MIN_TOTAL_RESULTS ]; then
  for items_file in "${ENTITIES_DIR}"/*/items.json; do
    [ -f "$items_file" ] || continue
    entity_slug=$(basename "$(dirname "$items_file")")

    while IFS= read -r fact_json; do
      [ -n "$fact_json" ] || continue
      content=$(echo "$fact_json" | jq -r '.content // empty' 2>/dev/null || true)
      status=$(echo "$fact_json" | jq -r '.status // "active"' 2>/dev/null || true)
      fact_id=$(echo "$fact_json" | jq -r '.id // empty' 2>/dev/null || true)
      created_at=$(echo "$fact_json" | jq -r '.createdAt // empty' 2>/dev/null || true)

      if [ "$status" = "historical" ]; then continue; fi

      if [ -n "$content" ] && matches_query "$content"; then
        if [ -n "$created_at" ]; then
          score=$(recency_score "$created_at")
        else
          score="0.500"
        fi
        safe_content=$(echo "$content" | tr '|' '/')
        FACTS_WITH_SCORES="${FACTS_WITH_SCORES}${score}|${entity_slug}|${fact_id}|${safe_content}\n"
      fi
    done < <(jq -c '.[]' "$items_file" 2>/dev/null || true)
  done

  if [ -n "$FACTS_WITH_SCORES" ]; then
    while IFS='|' read -r score entity_slug fact_id content; do
      [ -n "$content" ] || continue
      if [ $FACT_COUNT -ge $MAX_FACTS ]; then break; fi
      MATCHING_FACTS="${MATCHING_FACTS}- [${entity_slug}] (${score}) ${content}\n"
      FACT_COUNT=$((FACT_COUNT + 1))
      if [ -n "$fact_id" ]; then
        log_access "fact" "${entity_slug}/${fact_id}"
      fi
    done < <(echo -e "$FACTS_WITH_SCORES" | sort -t'|' -k1 -rn)
  fi
fi

TOTAL_RESULTS=$((ENTITY_COUNT + FACT_COUNT))
STAGE3_SUFFICIENT=false
if [ $TOTAL_RESULTS -ge $MIN_TOTAL_RESULTS ]; then
  STAGE3_SUFFICIENT=true
fi

# ========================================
# Stage 4: Fall back to daily notes
# ========================================
DAILY_SNIPPETS=""
DAILY_COUNT=0

if [ "$STAGE3_SUFFICIENT" = false ]; then
  for i in $(seq 0 $((DAILY_NOTES_LOOKBACK_DAYS - 1))); do
    if [[ "$OSTYPE" == "darwin"* ]]; then
      date_str=$(date -v-${i}d +"%Y-%m-%d")
    else
      date_str=$(date -d "-${i} days" +"%Y-%m-%d")
    fi

    daily_file="${MEMORY_HOME}/${date_str}.md"

    if [ -f "$daily_file" ] && [ $DAILY_COUNT -lt $MAX_DAILY_SNIPPETS ]; then
      score=$(recency_score "$date_str")
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        [[ "$line" =~ ^#+ ]] && continue
        if matches_query "$line"; then
          DAILY_SNIPPETS="${DAILY_SNIPPETS}- [${date_str}] (${score}) ${line}\n"
          DAILY_COUNT=$((DAILY_COUNT + 1))
          if [ $DAILY_COUNT -ge $MAX_DAILY_SNIPPETS ]; then break 2; fi
        fi
      done < "$daily_file"
    fi
  done
fi

# ========================================
# Output
# ========================================
echo "=== MEMORY CONTEXT ==="
echo ""
echo "Query: \"$QUERY\" → synthesized: \"$SYNTHESIZED_QUERY\""
echo ""

if [ $ENTITY_COUNT -gt 0 ]; then
  echo "## Entities (${ENTITY_COUNT} matched)"
  echo ""
  echo -e "$ENTITY_SUMMARIES"
fi

if [ $FACT_COUNT -gt 0 ]; then
  echo "## Facts (${FACT_COUNT} matched)"
  echo ""
  echo -e "$MATCHING_FACTS"
fi

if [ $DAILY_COUNT -gt 0 ]; then
  echo "## Daily Notes (${DAILY_COUNT} snippets)"
  echo ""
  echo -e "$DAILY_SNIPPETS"
fi

if [ $ENTITY_COUNT -eq 0 ] && [ $FACT_COUNT -eq 0 ] && [ $DAILY_COUNT -eq 0 ]; then
  echo "(No matching memory found for query: \"$QUERY\")"
  echo ""
fi

echo "=== END MEMORY CONTEXT ==="
