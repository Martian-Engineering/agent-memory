#!/bin/bash
# setup.sh — Bootstrap the Three-Layer Memory System
#
# Usage:
#   bash setup.sh [MEMORY_HOME]
#
# Arguments:
#   MEMORY_HOME — Where to create the memory directory (default: ./memory)
#
# This script:
#   1. Creates the full directory tree
#   2. Copies templates into place
#   3. Makes pipeline scripts executable
#   4. Prints next steps

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMORY_HOME="${1:-./memory}"

echo "🧠 Setting up Three-Layer Memory System"
echo "   Location: $MEMORY_HOME"
echo ""

# Create directory structure
mkdir -p "$MEMORY_HOME/entities"
mkdir -p "$MEMORY_HOME/checkpoints"
mkdir -p "$MEMORY_HOME/metrics"
mkdir -p "$MEMORY_HOME/logs"
mkdir -p "$MEMORY_HOME/pipelines"

# Copy templates
if [ ! -f "$MEMORY_HOME/entities/README.md" ]; then
  cp "$SCRIPT_DIR/templates/entities/README.md" "$MEMORY_HOME/entities/"
fi

if [ ! -f "$MEMORY_HOME/entities/index.json" ]; then
  cp "$SCRIPT_DIR/templates/entities/index.json" "$MEMORY_HOME/entities/"
fi

# Create MEMORY.md (Layer 3) if it doesn't exist
MEMORY_MD="$(dirname "$MEMORY_HOME")/MEMORY.md"
if [ ! -f "$MEMORY_MD" ]; then
  cp "$SCRIPT_DIR/templates/MEMORY-template.md" "$MEMORY_MD"
  echo "   Created: $MEMORY_MD"
fi

# Copy pipeline scripts
for script in "$SCRIPT_DIR"/pipelines/*.sh; do
  [ -f "$script" ] || continue
  dest="$MEMORY_HOME/pipelines/$(basename "$script")"
  cp "$script" "$dest"
  chmod +x "$dest"
done

# Copy prompt templates
for prompt in "$SCRIPT_DIR"/prompts/*.md; do
  [ -f "$prompt" ] || continue
  dest="$MEMORY_HOME/pipelines/$(basename "$prompt")"
  cp "$prompt" "$dest"
done

# Create .gitkeep files for empty dirs
touch "$MEMORY_HOME/checkpoints/.gitkeep"
touch "$MEMORY_HOME/metrics/.gitkeep"
touch "$MEMORY_HOME/logs/.gitkeep"

# Create gitignore for runtime files
cat > "$MEMORY_HOME/metrics/.gitignore" << 'EOF'
# Access metrics are runtime state, not tracked in git
access.json
EOF

echo ""
echo "✅ Memory system initialized!"
echo ""
echo "Directory structure:"
echo "  $MEMORY_HOME/"
echo "    entities/          ← Layer 1: Knowledge graph"
echo "      index.json       ← Entity metadata index"
echo "      README.md        ← Schema documentation"
echo "    checkpoints/       ← Session state snapshots"
echo "    metrics/           ← Access frequency tracking"
echo "    logs/              ← Maintenance logs"
echo "    pipelines/         ← All scripts + prompt templates"
echo ""
echo "  $MEMORY_MD           ← Layer 3: Tacit knowledge"
echo ""
echo "Next steps:"
echo "  1. Add your first entity:"
echo "     bash $MEMORY_HOME/pipelines/add-fact.sh alice person \"Alice is the lead engineer\" manual"
echo ""
echo "  2. Set MEMORY_HOME for your agent:"
echo "     export MEMORY_HOME=\"$(cd "$MEMORY_HOME" && pwd)\""
echo ""
echo "  3. Set up extraction (see prompts/extract-facts.md)"
echo "  4. Set up synthesis (see prompts/weekly-synthesis.md)"
echo ""
echo "  5. Retrieve context on session start:"
echo "     bash $MEMORY_HOME/pipelines/retrieve-memory.sh \"your query\""
