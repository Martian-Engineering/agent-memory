#!/bin/bash
# add-fact-validated.sh - Validated fact ingestion wrapper
#
# This wrapper adds validation layers on top of add-fact.sh:
# 1. Deduplication - rejects near-duplicate facts
# 2. Contradiction detection - supersedes old facts when values change
# 3. Write rules - rejects low-signal facts
#
# Usage: add-fact-validated.sh <entity-slug> <entity-type> "<fact>" <source> [sourceRef]
#
# Example:
#   add-fact-validated.sh alice person "Alice got promoted to VP" conversation
#
# Output explains whether the fact was:
# - ADDED: New fact added successfully
# - DEDUPE: Rejected as near-duplicate of existing fact
# - SUPERSEDED: Added and marked an older fact as historical
# - REJECTED: Rejected for failing write rules

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMORY_HOME="${MEMORY_HOME:-$(dirname "$SCRIPT_DIR")}"
ENTITIES_DIR="${MEMORY_HOME}/entities"
ADD_FACT_SCRIPT="${SCRIPT_DIR}/add-fact.sh"

# Similarity threshold for deduplication (0.0 to 1.0)
# 0.7 = 70% word overlap triggers duplicate detection
SIMILARITY_THRESHOLD=0.7

# Minimum fact length (characters)
MIN_FACT_LENGTH=15

# ─────────────────────────────────────────────────────────────────────────────
# Input validation
# ─────────────────────────────────────────────────────────────────────────────

if [ $# -lt 4 ]; then
    echo "Usage: add-fact-validated.sh <entity-slug> <entity-type> <fact> <source> [sourceRef]"
    echo "Example: add-fact-validated.sh alice person \"Alice got promoted to VP\" conversation"
    exit 1
fi

ENTITY="$1"
ENTITY_TYPE="$2"
CONTENT="$3"
SOURCE="$4"
SOURCE_REF="${5:-}"

ENTITY_DIR="$ENTITIES_DIR/$ENTITY"
ITEMS_FILE="$ENTITY_DIR/items.json"

# ─────────────────────────────────────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────────────────────────────────────

# Normalize text for comparison: lowercase, remove punctuation, collapse whitespace
normalize_text() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' ' ' | tr -s ' ' | xargs
}

# Calculate Jaccard similarity between two strings (word-based)
# Returns a float between 0 and 1
jaccard_similarity() {
    local text1="$1"
    local text2="$2"

    # Normalize both texts
    local norm1=$(normalize_text "$text1")
    local norm2=$(normalize_text "$text2")

    # Convert to sorted word lists
    local words1=$(echo "$norm1" | tr ' ' '\n' | sort -u)
    local words2=$(echo "$norm2" | tr ' ' '\n' | sort -u)

    # Calculate intersection and union sizes
    local intersection=$(comm -12 <(echo "$words1") <(echo "$words2") | wc -l | tr -d ' ')
    local union_count=$(echo -e "$words1\n$words2" | sort -u | wc -l | tr -d ' ')

    # Avoid division by zero
    if [ "$union_count" -eq 0 ]; then
        echo "0.0"
        return
    fi

    # Calculate Jaccard similarity using awk for floating point
    awk "BEGIN {printf \"%.2f\", $intersection / $union_count}"
}

# Check if similarity is above threshold
is_similar() {
    local similarity="$1"
    awk "BEGIN {exit !($similarity >= $SIMILARITY_THRESHOLD)}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Validation: Write rules (low-signal detection)
# ─────────────────────────────────────────────────────────────────────────────

TRANSIENT_PATTERNS=(
    "is tired"
    "is busy"
    "is working on"
    "had lunch"
    "had dinner"
    "had breakfast"
    "is eating"
    "feels like"
    "seems like"
    "might be"
    "maybe"
    "probably"
    "i think"
    "not sure"
    "is going to"
    "plans to"
    "wants to"
    "thinking about"
    "considering"
)

check_write_rules() {
    local content="$1"
    local content_lower=$(echo "$content" | tr '[:upper:]' '[:lower:]')

    # Rule 1: Minimum length
    if [ ${#content} -lt $MIN_FACT_LENGTH ]; then
        echo "REJECTED: Fact too short (${#content} chars < $MIN_FACT_LENGTH minimum)"
        return 1
    fi

    # Rule 2: Check for transient/vague patterns
    for pattern in "${TRANSIENT_PATTERNS[@]}"; do
        if [[ "$content_lower" == *"$pattern"* ]]; then
            echo "REJECTED: Contains transient/vague pattern: '$pattern'"
            return 1
        fi
    done

    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Validation: Deduplication
# ─────────────────────────────────────────────────────────────────────────────

check_duplicate() {
    local content="$1"
    local items_file="$2"

    if [ ! -f "$items_file" ]; then
        return 0
    fi

    local active_facts=$(jq -r '.[] | select(.status == "active") | .content' "$items_file" 2>/dev/null)

    while IFS= read -r existing_fact; do
        [ -z "$existing_fact" ] && continue

        local similarity=$(jaccard_similarity "$content" "$existing_fact")
        if is_similar "$similarity"; then
            echo "DEDUPE: New fact is ${similarity} similar to existing: \"${existing_fact:0:60}...\""
            return 1
        fi
    done <<< "$active_facts"

    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Validation: Contradiction detection
# ─────────────────────────────────────────────────────────────────────────────

ANCHOR_PATTERNS=(
    "works at"
    "employed at"
    "employed by"
    "job at"
    "position at"
    "role at"
    "lives in"
    "lives at"
    "address:"
    "address is"
    "moved to"
    "email:"
    "email is"
    "phone:"
    "phone is"
    "phone number"
    "title is"
    "title:"
    "married to"
    "partner is"
    "dating"
    "uses browser"
    "uses editor"
    "switched to"
    "started using"
)

find_contradictions() {
    local content="$1"
    local items_file="$2"

    if [ ! -f "$items_file" ]; then
        return
    fi

    local content_lower=$(echo "$content" | tr '[:upper:]' '[:lower:]')

    local matched_anchors=()
    for anchor in "${ANCHOR_PATTERNS[@]}"; do
        if [[ "$content_lower" == *"$anchor"* ]]; then
            matched_anchors+=("$anchor")
        fi
    done

    if [ ${#matched_anchors[@]} -eq 0 ]; then
        return
    fi

    local facts_json=$(jq -c '.[] | select(.status == "active")' "$items_file" 2>/dev/null)

    while IFS= read -r fact_json; do
        [ -z "$fact_json" ] && continue

        local fact_content=$(echo "$fact_json" | jq -r '.content')
        local fact_id=$(echo "$fact_json" | jq -r '.id')
        local fact_content_lower=$(echo "$fact_content" | tr '[:upper:]' '[:lower:]')

        for anchor in "${matched_anchors[@]}"; do
            if [[ "$fact_content_lower" == *"$anchor"* ]]; then
                local similarity=$(jaccard_similarity "$content" "$fact_content")
                if ! is_similar "$similarity"; then
                    echo "$fact_id|$anchor|$fact_content"
                fi
            fi
        done
    done <<< "$facts_json"
}

mark_historical() {
    local items_file="$1"
    local old_fact_id="$2"

    jq --arg id "$old_fact_id" \
       '(.[] | select(.id == $id)) |= . + {status: "historical"}' \
       "$items_file" > "${items_file}.tmp"
    mv "${items_file}.tmp" "$items_file"
}

set_supersedes() {
    local items_file="$1"
    local new_fact_id="$2"
    local old_fact_id="$3"

    jq --arg new_id "$new_fact_id" --arg old_id "$old_fact_id" \
       '(.[] | select(.id == $new_id)) |= . + {supersedes: $old_id}' \
       "$items_file" > "${items_file}.tmp"
    mv "${items_file}.tmp" "$items_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main logic
# ─────────────────────────────────────────────────────────────────────────────

# Step 1: Check write rules
write_rule_result=$(check_write_rules "$CONTENT") || write_rule_exit=$?
write_rule_exit=${write_rule_exit:-0}
if [ "$write_rule_exit" -ne 0 ]; then
    echo "$write_rule_result"
    exit 1
fi

# Step 2: Check for duplicates
dedupe_result=$(check_duplicate "$CONTENT" "$ITEMS_FILE") || dedupe_exit=$?
dedupe_exit=${dedupe_exit:-0}
if [ "$dedupe_exit" -ne 0 ]; then
    echo "$dedupe_result"
    exit 0  # Not an error, just skip
fi

# Step 3: Check for contradictions
contradictions=$(find_contradictions "$CONTENT" "$ITEMS_FILE")

# Step 4: Add the fact
add_output=$("$ADD_FACT_SCRIPT" "$ENTITY" "$ENTITY_TYPE" "$CONTENT" "$SOURCE" "$SOURCE_REF")
new_fact_id=$(echo "$add_output" | grep -oE '[a-f0-9-]{36}' | head -1)

# Step 5: If contradictions found, mark old facts as historical
if [ -n "$contradictions" ]; then
    echo "SUPERSEDED: Added fact $new_fact_id"

    while IFS='|' read -r old_id anchor old_content; do
        [ -z "$old_id" ] && continue

        mark_historical "$ITEMS_FILE" "$old_id"
        set_supersedes "$ITEMS_FILE" "$new_fact_id" "$old_id"
        echo "  - Marked historical (anchor: '$anchor'): \"${old_content:0:50}...\""
    done <<< "$contradictions"
else
    echo "ADDED: $add_output"
fi
