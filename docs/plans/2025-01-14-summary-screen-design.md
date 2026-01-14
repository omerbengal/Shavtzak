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
1. **Top:** High-level overview with 3 pie charts (fits in viewport)
2. **Bottom:** Expandable detail tiles for deeper information

---

## Section 1: High-Level Overview (Top)

All 3 charts visible at once, responsive layout that fits within viewport.

### Layout Behavior
- **Desktop/tablet:** 3 charts in a single row
- **Mobile:** 3 charts stacked vertically, each ~1/3 of screen height
- Charts resize responsively to fit without scrolling

### Chart 1: Events Overview
- **Type:** Pie chart
- **Data:** Upcoming events by staffing status
  - Fully staffed (green)
  - Partially staffed (orange)
  - No quotas defined (gray)
- **Legend:** Small legend below chart

### Chart 2: Staffing Status
- **Type:** Donut chart
- **Data:** All role slots across upcoming events
  - Filled (green)
  - Empty / Unfilled (red)
- **Center:** Percentage filled shown in center

### Chart 3: Checklist Compliance
- **Type:** Pie chart
- **Data:** Checklist items for upcoming events
  - Completed (green)
  - Pending / Not completed (orange)
- **Center:** Percentage completed shown in center

---

## Section 2: Expandable Detail Tiles (Bottom)

### Tile 1: Upcoming Events Breakdown
- **Collapsed state:**
  - Count of upcoming events
  - List of next 3-5 events with brief status

- **Expanded state:**
  - Full list of upcoming events
  - Each row shows:
    - Event name
    - Date and location
    - Color-coded background (green/orange based on staffing)
    - Small progress bar showing % staffed

### Tile 2: Staffing Gaps
- **Collapsed state:**
  - Total number of unfilled roles across all upcoming events

- **Expanded state:**
  - List of unfilled roles, grouped by either:
    - Role type (paramedic, commander, etc.) OR
    - By event (Event A needs 2 medics, Event B needs 1 commander)

### Tile 3: Checklist Status
- **Collapsed state:**
  - Overall checklist completion percentage
  - Count of pending items

- **Expanded state:**
  - List of upcoming events with:
    - Event name
    - Checklist progress (X/Y items completed)
    - Color-coded row (green = all done, orange = in progress)

---

## Technical Notes

- Uses existing BLoCs: `EventBloc`, `TeamBloc`, `ChecklistBloc`
- All data from real-time Firestore streams
- Charts use `fl_chart` package (already in dependencies for other screens)
- RTL layout (Hebrew)
- Existing placeholder screen: `lib/presentation/screens/summary/summary_screen.dart`
