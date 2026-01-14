# Summary Screen (מסך מנהלים) Design

**Date:** 2025-01-14
**Route:** `/summary` (and `/test/summary`)
**Target User:** Producer / "Big Boss" - manager of all events

---

## Purpose

High-level dashboard for the person overseeing all events. Shows macro-level metrics, not day-to-day operational details. Not for handling pending requests (that's for team leads).

---

## Layout Structure

Two sections stacked vertically:
1. **Top:** High-level overview with 3 pie/donut charts (fits in viewport)
2. **Bottom:** Expandable detail tiles for deeper information

---

## Section 1: High-Level Overview (Top)

All 3 charts visible at once, responsive layout that fits within viewport.

### Layout Behavior
- **Desktop/tablet (≥600px):** 3 charts in a single row
- **Mobile (<600px):** 3 charts stacked vertically, each ~30% of screen height
- Charts resize responsively to fit without scrolling

### Chart 1: Events Overview (Pie Chart)
- **Data:** Upcoming events by staffing status (3 categories)
  - Fully staffed (green) - all role slots filled
  - Not fully staffed (orange) - includes both partial AND zero assignments
  - No quotas defined (gray)
- **Legend:** Small legend below chart

### Chart 2: Staffing Status (Donut Chart)
- **Data:** All role slots across upcoming events
  - Filled (green)
  - Unfilled (red)
- **Center:** Percentage filled shown in center (e.g., "78%")
- **Donut hole:** ~60% of radius for readability

### Chart 3: Checklist Compliance (Donut Chart)
- **Data:** Checklist items for upcoming events
  - Completed (green)
  - Pending / Not completed (orange)
- **Center:** Percentage completed shown in center

### Empty State
If no upcoming events exist, show centered message "אין אירועים קרובים" instead of charts.

---

## Section 2: Event Summary Tiles (Bottom)

Scrollable ListView below charts. **Each event is its own expandable tile** showing combined staffing and checklist status.

### Per-Event Tile Design

**Collapsed state:**
- **Title:** Event name
- **Subtitle line 1:** Date range (or single date) | Location
- **Subtitle line 2:** Two status indicators:
  - Staffing: "מאויש במלואו" (green) or "X תפקידים חסרים" (orange)
  - Checklist: "צ'קליסט הושלם" (green) or "X פריטים ממתינים" (orange)
- **Background color:** Green if fully staffed + no pending checklist, orange otherwise

**Expanded state:**
- **Missing roles section** (if not fully staffed):
  - Header: "תפקידים חסרים"
  - Role chips showing missing roles: "חובש (2)", "מפקד (1)"
- **Checklist section** (if event has checklist items):
  - Header: "צ'קליסט (X/Y)"
  - List of checklist items with checkboxes (pending first, then completed)
- **All good state** (if fully staffed + checklist complete):
  - Green checkmark icon with "הכל מוכן!"

### Date Range Formatting
- Single day events: "15/1/2025"
- Same month range: "15-17/1/2025"
- Cross-month range: "15/1 - 2/2/2025"
- Cross-year range: "30/12/2024 - 2/1/2025"

---

## Technical Implementation

### Architecture
- **No new BLoC needed** - uses MultiBlocListener with existing BLoCs
- Consumes: `EventBloc`, `AssignmentBloc`, `ChecklistBloc`
- Computed metrics calculated on each rebuild using helper methods

### File Structure
```
lib/presentation/screens/summary/
├── summary_screen.dart              # Main screen
├── widgets/
│   ├── events_overview_chart.dart       # Chart 1: Events by status
│   ├── staffing_status_chart.dart       # Chart 2: Filled vs unfilled slots
│   ├── checklist_compliance_chart.dart  # Chart 3: Checklist completion
│   └── event_summary_tile.dart          # Per-event expandable tile
```

### Dependencies
- `fl_chart: ^0.69.0` - for pie/donut charts

### Color Constants
- Green: `Colors.green.shade400`
- Orange: `Colors.orange.shade400`
- Red: `Colors.red.shade400`
- Gray: `Colors.grey.shade400`

### Responsive Breakpoint
- `MediaQuery.of(context).size.width >= 600` → horizontal chart layout
- Below 600 → vertical stacked layout
