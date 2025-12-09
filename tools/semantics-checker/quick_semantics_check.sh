#!/bin/bash

echo "🔍 Quick Check: Finding widgets without semantic identifiers..."
echo "=============================================================="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "\n${YELLOW}📱 Checking main screens and widgets...${NC}"

# Check specific files that are likely to have widgets
files_to_check=(
    "shavtzak/lib/main.dart"
    "shavtzak/lib/presentation/screens/assignment/assignment_form_screen.dart"
    "shavtzak/lib/presentation/screens/user/constraints_screen.dart"
    "shavtzak/lib/presentation/screens/user/availability_screen.dart"
    "shavtzak/lib/presentation/screens/team/team_list_screen.dart"
    "shavtzak/lib/presentation/screens/event/widgets/event_form_modal.dart"
    "shavtzak/lib/presentation/widgets/date_picker_dialog.dart"
)

total_issues=0

for file in "${files_to_check[@]}"; do
    if [ -f "$file" ]; then
        echo -e "\n📁 $file"

        # Find interactive widgets and check if they have semantics
        while IFS= read -r line; do
            if echo "$line" | grep -q -E "^\s*(IconButton|ElevatedButton|TextButton|Checkbox|Switch|ListTile.*onTap|DropdownButtonFormField|TextFormField|FloatingActionButton|GestureDetector|InkWell)" && echo "$line" | grep -v "//"; then

                # Get line number and content
                line_num=$(echo "$line" | grep -o -E "^[0-9]+:" | tr -d ':')
                widget_line=$(echo "$line" | sed 's/^[0-9]*:\s*//')

                # Check context around this line for Semantics wrapper
                start_line=$((line_num - 5))
                if [ $start_line -lt 1 ]; then start_line=1; fi
                end_line=$((line_num + 2))

                context=$(sed -n "${start_line},${end_line}p" "$file")

                # Check for semantic identifier in context
                if echo "$context" | grep -q "Semantics.*identifier\|ValueKey.*'"; then
                    echo -e "  ${GREEN}✅ Line $line_num: $(echo $widget_line | cut -c1-80)${NC}"
                else
                    # Skip certain patterns that don't need semantics
                    if echo "$widget_line" | grep -q -E "ListTile.*\).*title.*subtitle" && ! echo "$context" | grep -q "onTap"; then
                        continue
                    fi
                    echo -e "  ${RED}❌ Line $line_num: $(echo $widget_line | cut -c1-80)${NC}"
                    ((total_issues++))
                fi
            fi
        done < <(grep -n -E "^\s*(IconButton|ElevatedButton|TextButton|Checkbox|Switch|ListTile.*onTap|DropdownButtonFormField|TextFormField|FloatingActionButton|GestureDetector|InkWell)" "$file" 2>/dev/null || true)
    fi
done

echo -e "\n${YELLOW}📊 SUMMARY${NC}"
echo "=============================================================="

if [ $total_issues -eq 0 ]; then
    echo -e "${GREEN}🎉 EXCELLENT! All checked widgets have semantic identifiers!${NC}"
    echo -e "${GREEN}✅ Your app is ready for comprehensive automated testing!${NC}"
else
    echo -e "${RED}⚠️  Found $total_issues widgets without semantic identifiers${NC}"
    echo -e "${YELLOW}💡 To fix, wrap with: Semantics(identifier: 'descriptive-name', child: Widget(...))${NC}"
fi

echo -e "\n${BLUE}💡 Quick command to run this check:${NC}"
echo "./quick_semantics_check.sh"
echo "=============================================================="