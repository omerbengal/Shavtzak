# 🧪 Flutter Semantic Identifier Checker

This directory contains tools to verify that all interactive Flutter widgets in the Shavtzak app have proper semantic identifiers for automated testing.

## 📋 Available Tools

### 1. Quick Check (Recommended for daily use)
**File**: `quick_semantics_check.sh`
**Purpose**: Fast scan of main screens and widgets
**Usage**: `./quick_semantics_check.sh`
**Speed**: ⚡ Very Fast
**Coverage**: Main screens and common widgets

### 2. Comprehensive Scan
**File**: `check_semantics.sh`
**Purpose**: Complete scan of entire codebase
**Usage**: `./check_semantics.sh`
**Speed**: 🐌 Slower but thorough
**Coverage**: All files with interactive widgets

### 3. One-Liner Command
**File**: `CHECK_SEMANTICS.md`
**Purpose**: Quick command reference
**Usage**: Copy commands from the file
**Speed**: ⚡ Instant

## 🚀 Quick Start

### Run Quick Check (Recommended):
```bash
cd shavtzak && ./tools/semantics-checker/quick_semantics_check.sh
```

### Run Comprehensive Check:
```bash
cd shavtzak && ./tools/semantics-checker/check_semantics.sh
```

### Quick One-Liner:
```bash
cd shavtzak && find lib -name "*.dart" -exec grep -l "IconButton\|ElevatedButton\|TextButton" {} \; | xargs grep -n -E "^\s*(IconButton|ElevatedButton|TextButton)" | grep -v "Semantics\|ValueKey" | head -20
```

## 📊 Understanding the Output

- ✅ **Green**: Widget has semantic identifier (good!)
- ❌ **Red**: Widget missing semantic identifier (needs fixing)
- ⚠️ **Yellow**: File summary showing issues found

## 🔧 How to Fix Missing Semantics

### Pattern for Adding Semantic Identifiers:
```dart
// Before:
IconButton(onPressed: () {}, icon: Icon(Icons.home))

// After:
Semantics(
  identifier: 'descriptive-widget-name',
  child: IconButton(onPressed: () {}, icon: Icon(Icons.home)),
)
```

### Common Widget Patterns:
```dart
// Button
Semantics(
  identifier: 'save-button',
  child: ElevatedButton(onPressed: () {}, child: Text('Save')),
)

// IconButton
Semantics(
  identifier: 'menu-toggle-button',
  child: IconButton(onPressed: () {}, icon: Icon(Icons.menu)),
)

// TextField
Semantics(
  identifier: 'user-name-field',
  child: TextFormField(controller: _controller, ...),
)

// Card/ListItem with onTap
Semantics(
  identifier: 'team-member-card-${member.id}',
  child: Card(
    child: InkWell(onTap: () {}, child: ...),
  ),
)
```

## 📱 Naming Conventions

Use **kebab-case** (lowercase with dashes) for semantic identifiers:

- ✅ `user-name-field`
- ✅ `save-button`
- ✅ `team-member-card-123`
- ✅ `filter-option-all-0`

❌ `userNameField` (camelCase)
❌ `userNameField` (camelCase)
❌ `user_name_field` (snake_case)

## 🎯 Current Status

✅ **ALL WIDGETS HAVE SEMANTIC IDENTIFIERS!**

The Shavtzak app is fully prepared for comprehensive automated testing with tools like:
- Playwright
- Flutter integration tests
- Accessibility testing tools
- Screen readers

## 🔄 When to Run

Run these checks:
- **Before adding new features** - to ensure baseline
- **After adding new widgets** - to catch missing identifiers
- **Before releases** - final verification
- **When refactoring** - to ensure nothing was broken

## 🛠️ Adding to Your Workflow

### Make it a pre-commit hook:
```bash
# In your .git/hooks/pre-commit
./tools/semantics-checker/quick_semantics_check.sh
if [ $? -ne 0 ]; then
  echo "❌ Some widgets lack semantic identifiers. Please fix them before committing."
  exit 1
fi
```

### Add to your CI/CD:
```yaml
# In your GitHub Actions or other CI
- name: Check Semantic Identifiers
  run: ./tools/semantics-checker/quick_semantics_check.sh
```

## 📞 Support

If you encounter issues with the semantic checker tools:
1. Ensure the scripts are executable: `chmod +x tools/semantics-checker/*.sh`
2. Run from the `shavtzak` directory
3. Check that you're using bash or zsh
4. Verify the file paths are correct

Happy testing! 🧪✨