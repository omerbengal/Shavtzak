#!/bin/bash

echo "🔍 Checking for Flutter widgets without semantic identifiers..."
echo "================================================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
total_files=0
files_with_issues=0
total_widgets=0
widgets_without_semantics=0

# Function to check a single file
check_file() {
    local file=$1
    local has_semantics=false
    local has_widgets=false
    local widgets_without_sem=0
    local temp_file=$(mktemp)

    # Extract all interactive widgets (excluding commented lines)
    grep -n -E "^\s*(IconButton|ElevatedButton|TextButton|Checkbox|Switch|CheckboxListTile|SwitchListTile|ListTile|DropdownButtonFormField|TextFormField|FloatingActionButton|GestureDetector|InkWell)" "$file" | grep -v "//" > "$temp_file"

    if [ -s "$temp_file" ]; then
        has_widgets=true
        ((total_files++))

        echo -e "\n${BLUE}📁 Checking: $file${NC}"

        while IFS= read -r line; do
            line_num=$(echo "$line" | cut -d: -f1)
            widget_line=$(echo "$line" | cut -d: -f2-)

            # Check if widget is wrapped with Semantics or has semantic identifier
            # Look for Semantics widget wrapping OR semantic identifiers in the widget chain
            widget_has_semantics=false

            # Check if this widget is wrapped in Semantics (look backwards a few lines)
            start_line=$((line_num - 10))
            if [ $start_line -lt 1 ]; then start_line=1; fi

            # Extract context around this widget
            context=$(sed -n "${start_line},${line_num}p" "$file")

            # Check for Semantics wrapper
            if echo "$context" | grep -q "Semantics.*identifier"; then
                widget_has_semantics=true
            fi

            # Check if widget has ValueKey (also acceptable for testing)
            if echo "$context" | grep -q "ValueKey.*'"; then
                widget_has_semantics=true
            fi

            # Special case: ignore ListTile without onTap
            if echo "$widget_line" | grep -q "ListTile" && ! echo "$context" | grep -q "onTap\|GestureDetector\|InkWell"; then
                widget_has_semantics=true
            fi

            # Special case: ignore TextFormField without specific patterns
            if echo "$widget_line" | grep -q "TextFormField" && echo "$context" | grep -v -E "controller|validator|onChanged"; then
                widget_has_semantics=true
            fi

            ((total_widgets++))

            if [ "$widget_has_semantics" = false ]; then
                echo -e "  ${RED}❌ Line $line_num: $widget_line${NC}"
                ((widgets_without_sem++))
                ((widgets_without_semantics))
            else
                echo -e "  ${GREEN}✅ Line $line_num: $widget_line${NC}"
            fi
        done < "$temp_file"

        if [ $widgets_without_sem -gt 0 ]; then
            ((files_with_issues++))
            echo -e "  ${YELLOW}⚠️  Found $widgets_without_sem widgets without semantic identifiers${NC}"
        fi
    fi

    rm "$temp_file"
}

# Export function for find command
export -f check_file
export RED GREEN YELLOW BLUE NC total_files files_with_issues total_widgets widgets_without_semantics

echo -e "${BLUE}🔎 Scanning Flutter files for interactive widgets...${NC}"

# Find all relevant Dart files and check them
find shavtzak/lib -name "*.dart" -print0 | while IFS= read -r -d '' file; do
    # Skip if file doesn't contain interactive widgets
    if grep -q -E "IconButton|ElevatedButton|TextButton|Checkbox|Switch|CheckboxListTile|SwitchListTile|ListTile|DropdownButtonFormField|TextFormField|FloatingActionButton|GestureDetector|InkWell" "$file" && ! grep -q "//.*\(IconButton\|ElevatedButton\|TextButton\|Checkbox\|Switch\|CheckboxListTile\|SwitchListTile\|ListTile\|DropdownButtonFormField\|TextFormField\|FloatingActionButton\|GestureDetector\|InkWell\)" "$file"; then
        check_file "$file"
    fi
done

echo -e "\n${BLUE}📊 SUMMARY${NC}"
echo "================================================================"
echo "📁 Files with interactive widgets: $total_files"
echo "⚠️  Files with issues: $files_with_issues"
echo "🎯 Total interactive widgets: $total_widgets"
echo "❌ Widgets without semantics: $widgets_without_semantics"

if [ $widgets_without_semantics -eq 0 ]; then
    echo -e "\n${GREEN}🎉 EXCELLENT! All interactive widgets have semantic identifiers!${NC}"
    echo -e "${GREEN}✅ Your app is fully ready for comprehensive automated testing!${NC}"
else
    echo -e "\n${RED}⚠️  ACTION REQUIRED: $widgets_without_semantics widgets need semantic identifiers${NC}"
    echo -e "${YELLOW}💡 Add Semantics(identifier: 'descriptive-name', child: Widget(...)) wrappers${NC}"
fi

echo "================================================================"