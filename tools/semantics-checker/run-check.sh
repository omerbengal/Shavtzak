#!/bin/bash

# Flutter Semantic Identifier Checker - Entry Point
# This script provides an easy interface to run semantic checks

echo "🧪 Flutter Semantic Identifier Checker"
echo "===================================="
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Change to project root
cd "$PROJECT_ROOT"

# Show menu
echo "Select check type:"
echo "1) Quick check (recommended) - Fast scan of main screens"
echo "2) Comprehensive check - Complete scan of entire codebase"
echo "3) One-liner quick command"
echo "4) Show help"
echo ""

read -p "Enter choice (1-4): " choice

case $choice in
  1)
    echo ""
    echo "🚀 Running quick semantic check..."
    echo "===================================="
    "$SCRIPT_DIR/quick_semantics_check.sh"
    ;;
  2)
    echo ""
    echo "🔍 Running comprehensive semantic check..."
    echo "========================================"
    "$SCRIPT_DIR/check_semantics.sh"
    ;;
  3)
    echo ""
    echo "⚡ Quick one-liner command:"
    echo "==========================="
    echo "find lib -name \"*.dart\" -exec grep -l \"IconButton\\|ElevatedButton\\|TextButton\" {} \\; | xargs grep -n -E \"^\\s*(IconButton|ElevatedButton|TextButton)\" | grep -v \"Semantics\\|ValueKey\" | head -20"
    echo ""
    echo "Running it now..."
    echo "==========================="
    find lib -name "*.dart" -exec grep -l "IconButton\|ElevatedButton\|TextButton" {} \; | xargs grep -n -E "^\s*(IconButton|ElevatedButton|TextButton)" | grep -v "Semantics\|ValueKey" | head -20
    ;;
  4)
    echo ""
    echo "📖 Help Documentation"
    echo "====================="
    if [ -f "$SCRIPT_DIR/README.md" ]; then
      cat "$SCRIPT_DIR/README.md"
    else
      echo "README.md not found in $SCRIPT_DIR"
    fi
    ;;
  *)
    echo "Invalid choice. Please select 1-4."
    exit 1
    ;;
esac

echo ""
echo "✨ Done! You can also run these commands directly:"
echo "   ./tools/semantics-checker/run-check.sh"
echo "   ./tools/semantics-checker/quick_semantics_check.sh"
echo "   ./tools/semantics-checker/check_semantics.sh"