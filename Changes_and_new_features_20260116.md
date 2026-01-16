# Changes and New Features - 2026-01-16

This document outlines the changes, fixes, and new features to be implemented in the Shavtzak application.

---

## 1. Remove Strikethrough on Completed Checklist Items (Summary Screen)

**Type**: UI Fix

**Screen**: Summary Screen (מסך מנהלים)

**Current Behavior**: When a checklist item is marked as complete, the text appears with a strikethrough/underline decoration.

**Desired Behavior**: Remove the strikethrough/underline text decoration from completed items. The following should be preserved:
- Checkbox with checkmark (✓) indicating completion
- Green/orange color indicators showing status

**Implementation Notes**:
- Locate the checklist item widget in the Summary Screen
- Remove `TextDecoration.lineThrough` or similar styling from completed items
- Ensure color indicators remain intact

---

## 2. Rename "Start Time" Label to "Audience Gathering Time"

**Type**: UI Label Change

**Affected Screens**:
- `/admin/events` (Event list and event modal)
- Summary Screen (מסך מנהלים)

**Change**:
- **Old Label**: "שעת התחלה" (Start Time)
- **New Label**: "שעת התכנסות קהל" (Audience Gathering Time)

**Implementation Notes**:
- This is a **label-only** change
- The underlying field name in code and database (`startTime`) remains unchanged
- Update all UI references to display the new Hebrew label

---

## 3. Add "Actual Show Start Time" Field to Events

**Type**: New Feature

**Description**: Add a new optional field to events representing when the performance/show actually begins (as opposed to audience gathering time).

**Field Details**:
- **Hebrew Name**: "שעת תחילת המופע בפועל"
- **Field Name**: `actualShowStartTime` (or similar)
- **Type**: Same type as existing time fields (e.g., `TimeOfDay`)
- **Required**: No (optional field)

**Display Locations**:
- `/admin/events` - Event list and event modal
- Summary Screen (מסך מנהלים)
- `/user/assignments` - User assignments screen

**Implementation Notes**:
- Add field to Event entity
- Add field to EventModel with Firestore serialization
- Update EventFormModal to include the new field
- Update all display locations to show the field when populated

---

## 4. Add Vehicle Details to Team Members

**Type**: New Feature

**Description**: Add vehicle information fields to team members, allowing users to store their car details.

**New Fields**:

| Field | Hebrew Name | Type | Validation | Input |
|-------|-------------|------|------------|-------|
| Vehicle Number | מספר רכב | String | 7-8 digits (0-9 only) | Numpad keyboard |
| Manufacturer | יצרן | String | From predefined list | Dropdown |
| Color | צבע | String | Free text | Text input |

**Manufacturer List Source**:
- Firebase collection: `utilities`
- Document: `Lists`
- Field: `car_manufacturers` (Array)

**Validation Rules**:
- All-or-nothing: Either ALL three fields are filled, or NONE
- No partial data allowed
- Vehicle number must be exactly 7 or 8 numeric digits

**UI Implementation**:

1. **Team Member Modal** (Admin view):
   - Display similar to birthday field
   - Show as a "fake" text field that, when tapped, opens a sub-modal
   - Sub-modal contains the three input fields
   - Use car icon

2. **User Settings** (Personal area):
   - Add a section similar to the birthday section
   - Display vehicle data with action buttons (edit/clear)
   - Use car icon

**Implementation Notes**:
- Add `VehicleInfo` class/model with the three fields
- Add `vehicleInfo` field to TeamMember entity
- Update TeamMemberModel for Firestore serialization
- Create new collection `utilities` with document `Lists` if not exists
- Populate `car_manufacturers` array in Firebase
- Create VehicleInfoModal widget
- Update user settings screen with vehicle section

---

## 5. Vehicle Information Copy Dialog

**Type**: New Feature

**Trigger**: New car icon button in `/admin/team-members` screen

**Description**: A dialog that allows admins to select team members and copy their vehicle information to the clipboard, formatted for external use (e.g., parking lists, security access).

**Dialog Flow**:

### Step 1 - Select Event
- Display list of **future events only**
- Admin selects the target event

### Step 2 - Select Team Members
Two lists with checkboxes for multi-selection:

1. **Primary List** (top): Team members who are:
   - Assigned to the selected event, AND
   - Have ALL vehicle detail fields filled in

2. **Secondary List** (bottom): Team members who:
   - Have all vehicle details filled in, BUT
   - Are NOT assigned to the selected event

### Completion
- Format selected members' information: Full name + vehicle details
- Copy formatted text to device clipboard
- Show confirmation message

**Implementation Notes**:
- Create new dialog widget similar to `ManualAssignmentFlowDialog`
- Query assignments for selected event
- Filter team members by vehicle info completeness
- Implement clipboard copy functionality
- Design appropriate output format for the copied text

---

## 6. Permanent Member Icon Consistency

**Type**: UI Enhancement

**Description**: Replace the checkmark indicating permanent members with a dedicated icon, and use this icon consistently across all team member lists in the app.

**Current State**:
- `/admin/team-members` shows a checkmark for permanent members (`isPermanent: true`)

**Changes**:

1. **Replace** the checkmark in `/admin/team-members` with a new permanent member icon

2. **Add** the same icon to all other team member lists:
   - Team member selection in event assignment flow
   - Manual assignment dialog (Step 2 - team member selection)
   - Vehicle information copy dialog (from feature #5)
   - Any other location where team members are listed

**Implementation Notes**:
- Choose an appropriate icon (e.g., `Icons.verified_user`, `Icons.badge`, or custom)
- Create a reusable widget or helper for displaying the icon
- Audit all team member list widgets and add the icon
- Ensure consistent positioning and styling across all instances

---

## 7. Role Management System

**Type**: New Feature (Major)

**Access**: New settings/gear icon in `/admin/events` screen

**Description**: Allow admins to dynamically manage roles instead of having them hardcoded.

**Capabilities**:

| Action | Description |
|--------|-------------|
| Add Role | Create a new role type with a Hebrew name |
| Delete Role | Remove an existing role type |
| Rename Role | Change a role's display name |
| Toggle Visibility | Set whether role appears in event quota configuration |

**Important Behavior**:
- **Disabling visibility** does NOT affect existing assignments
- It only controls whether the role appears as an option when setting up quotas for new/edited events
- Existing assignments with disabled roles remain intact

**Validation**:
- Role names must be unique (block duplicate names)

**Implementation Notes**:
- This is a **significant architectural change**
- Move roles from hardcoded `RoleType` enum to dynamic database storage
- Create new Firestore collection for roles (e.g., `roles`)
- Each role document: `{ id, name, hebrewName, isVisible, createdAt }`
- Update all role-related code to fetch from database instead of enum
- Create RoleManagementDialog widget
- Add RoleBloc for state management
- Update EventFormModal to use dynamic roles
- Update all role dropdowns and displays
- Ensure backward compatibility with existing assignments
- Consider migration strategy for existing enum-based roles

**Warning**: This feature requires careful implementation to avoid breaking existing functionality.

---

## 8. Preserve Event Filter After Assignment Creation

**Type**: Bug Fix

**Screen**: `/admin/assignments`

**Current (Buggy) Behavior**: When an event filter is active and an admin creates a new assignment, the filter gets cleared/reset.

**Desired Behavior**: The event filter should **persist** after creating an assignment. The admin should remain viewing the filtered list.

**Implementation Notes**:
- Locate the assignment creation completion handler
- Remove or bypass the code that clears the filter
- Ensure filter state is preserved in AssignmentBloc after successful assignment creation
- Test that filter persists for both successful and cancelled assignment flows

---

## Implementation Priority

Suggested order based on complexity and dependencies:

### Phase 1 - Simple Changes
1. **Item 1**: Remove strikethrough (UI fix)
2. **Item 2**: Rename label (UI fix)
3. **Item 8**: Preserve filter (Bug fix)

### Phase 2 - New Fields
4. **Item 3**: Actual show start time (New field)

### Phase 3 - Vehicle Features
5. **Item 4**: Vehicle details for team members (New feature)
6. **Item 5**: Vehicle copy dialog (New feature, depends on #4)

### Phase 4 - UI Consistency
7. **Item 6**: Permanent member icon (UI enhancement)

### Phase 5 - Major Feature
8. **Item 7**: Role management system (Major architectural change)

---

## Notes

- All UI text should be in Hebrew
- All layouts should respect RTL direction
- Test in both test and production environments
- Ensure real-time updates work correctly for new features
- Follow existing patterns in the codebase (Clean Architecture, BLoC pattern)
