#!/bin/bash
# add-edge.sh — Append an atomic fact with a structured edge to an entity's items.json
#
# Usage: add-edge.sh <entity-slug> <entity-type> "<fact>" <predicate> <object> <source> [sourceRef]
#
# Example:
#   add-edge.sh alice person "Alice works at Acme Corp" works_at acme-corp conversation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMORY_HOME="${MEMORY_HOME:-$(dirname "$SCRIPT_DIR")}"
ENTITIES_DIR="${MEMORY_HOME}/entities"

if [ $# -lt 6 ]; then
    echo "Usage: add-edge.sh <entity-slug> <entity-type> <fact> <predicate> <object> <source> [sourceRef]"
    echo ""
    echo "Arguments:"
    echo "  entity-slug  — Subject entity slug (e.g., alice)"
    echo "  entity-type  — Type: person|company|project|organization"
    echo "  fact         — Human-readable fact content"
    echo "  predicate    — Relationship: works_at, married_to, parent_of, etc."
    echo "  object       — Target entity slug (e.g., acme-corp)"
    echo "  source       — Source: conversation|meeting|transcript|manual"
    echo "  sourceRef    — Optional reference (session key, meeting id)"
    exit 1
fi

SUBJECT="$1"
ENTITY_TYPE="$2"
CONTENT="$3"
PREDICATE="$4"
OBJECT="$5"
SOURCE="$6"
SOURCE_REF="${7:-}"

ENTITY_DIR="$ENTITIES_DIR/$SUBJECT"
ITEMS_FILE="$ENTITY_DIR/items.json"

# Validate subject entity exists (or will be created)
if [ ! -d "$ENTITY_DIR" ]; then
    echo "Creating new entity directory: $SUBJECT"
fi

# Validate object entity exists
OBJECT_DIR="$ENTITIES_DIR/$OBJECT"
if [ ! -d "$OBJECT_DIR" ]; then
    echo "WARNING: Object entity '$OBJECT' does not exist in entities/"
    echo "Creating edge anyway — ensure entity is created before graph queries."
fi

# Validate predicate format (snake_case)
if [[ ! "$PREDICATE" =~ ^[a-z][a-z0-9_]*$ ]]; then
    echo "ERROR: Predicate must be snake_case (e.g., works_at, married_to)"
    echo "Got: $PREDICATE"
    exit 1
fi

# Create entity directory if needed
mkdir -p "$ENTITY_DIR"

# Generate fact ID
FACT_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Create items.json if it doesn't exist
if [ ! -f "$ITEMS_FILE" ]; then
    echo "[]" > "$ITEMS_FILE"
fi

# Build fact JSON with edge structure
FACT=$(jq -n \
    --arg id "$FACT_ID" \
    --arg content "$CONTENT" \
    --arg source "$SOURCE" \
    --arg sourceRef "$SOURCE_REF" \
    --arg createdAt "$CREATED_AT" \
    --arg entityType "$ENTITY_TYPE" \
    --arg subject "$SUBJECT" \
    --arg predicate "$PREDICATE" \
    --arg object "$OBJECT" \
    '{
        id: $id,
        content: $content,
        source: $source,
        sourceRef: $sourceRef,
        entityType: $entityType,
        createdAt: $createdAt,
        status: "active",
        supersedes: null,
        edge: {
            subject: $subject,
            predicate: $predicate,
            object: $object
        }
    }')

# Append to items.json
jq --argjson fact "$FACT" '. += [$fact]' "$ITEMS_FILE" > "${ITEMS_FILE}.tmp"
mv "${ITEMS_FILE}.tmp" "$ITEMS_FILE"

echo "Added edge fact $FACT_ID to $SUBJECT"
echo "  Edge: $SUBJECT --[$PREDICATE]--> $OBJECT"
