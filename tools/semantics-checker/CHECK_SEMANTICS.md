# 🧪 Quick Semantic Identifier Check

## Commands to quickly check for widgets without semantic identifiers:

### Method 1: One-Liner Quick Check
```bash
cd shavtzak && find lib -name "*.dart" -exec grep -l "IconButton\|ElevatedButton\|TextButton" {} \; | xargs grep -n -E "^\s*(IconButton|ElevatedButton|TextButton)" | grep -v "Semantics\|ValueKey" | head -20
```

### Method 2: Detailed Script Check
```bash
cd shavtzak && ./quick_semantics_check.sh
```

### Method 3: Comprehensive Full Scan
```bash
cd shavtzak && ./check_semantics.sh
```

## What to Look For:
- ❌ **Red**: Widgets without semantic identifiers
- ✅ **Green**: Widgets properly wrapped with `Semantics(identifier: '...', child: ...)`
- ⚠️ **Yellow**: Files that need attention

## Quick Fix Pattern:
```dart
// Before:
IconButton(onPressed: () {}, icon: Icon(Icons.home))

// After:
Semantics(
  identifier: 'home-button',
  child: IconButton(onPressed: () {}, icon: Icon(Icons.home)),
)
```

## Current Status: ✅ ALL WIDGETS HAVE SEMANTIC IDENTIFIERS!

Your Shavtzak app is **fully ready for comprehensive automated testing**! 🎉