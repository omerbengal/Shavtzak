# Event Assignments Share Image Design

## Context

Admins can open `EventAssignmentsDialog` from the event summary flow to view all assignments for one event. The current dialog is useful for inspection, but it is a scrollable list. On a phone, sharing the visible dialog to WhatsApp requires multiple screenshots when the event has many assignments.

The requested workflow is image-first: an admin should be able to produce one shareable event-assignment image for WhatsApp. If direct browser sharing is unavailable, the fallback should still support a screenshot/image workflow, not a formatted text list.

Current code context:

- Main widget: `shavtzak/lib/presentation/screens/event/widgets/event_assignments_dialog.dart`
- Current entry point: `EventSummaryTile` opens `EventAssignmentsDialog.withAssignments(...)`
- Assignment data already includes populated `teamMember`, `roleType`, `notes`, and semantic label data after labels are applied.

## Goals

- Add an image-first share action to the event assignments dialog.
- Preserve the current detailed dialog for browsing, calling, labels, statuses, and notes.
- Generate a compact RTL share card that can contain the entire event assignment summary in one image.
- Keep the generated image readable on phone screens and suitable for WhatsApp.
- Use the active grouping mode from the dialog: role grouping or label grouping.
- Keep all behavior client-side. This is a Flutter Web UI feature and should not require Cloud Functions deployment.
- Preserve complete note text even when that makes the generated PNG taller.

## Non-Goals

- Do not replace the existing detailed assignments dialog.
- Do not export to Google Sheets.
- Do not add phone numbers, alternate phones, or phone indicators to the generated image.
- Do not add assignment status chips to the generated image.
- Do not fall back to a text-based assignment list.
- Do not truncate note text.

## Share Image Content

The generated image contains:

- Event name.
- Event date or date range.
- Relevant event times, using the same event time fields already shown elsewhere in the app.
- Event location.
- Assignments grouped by the dialog's active mode:
  - Role mode: sections by role.
  - Label mode: sections by semantic label, with roles nested inside each label as in the current dialog.
- Member names only inside assignment rows.
- Numbered note markers after names for assignments that have notes, formatted visually as superscript-style `(1)`, `(2)`, `(3)`, and so on.
- A notes section below the assignment grid. Each note line starts with the same number and includes the member name plus the full note text.
- A small footer such as `נוצר משבצק`.

The generated image does not contain:

- Status chips for pending or declined assignments.
- Phone icons.
- Phone numbers.
- Alternate phone indicators.
- Text truncation for notes.

## UX Flow

1. Admin opens the event assignments dialog from the event summary screen.
2. The dialog still shows the current interactive list.
3. The dialog header adds a share/image icon button with a Hebrew tooltip such as `שתף תמונת שיבוצים`.
4. When tapped, the app builds a dedicated share card from the currently loaded assignments, active grouping mode, labels, roles, and event details.
5. The app attempts native image sharing first.
6. If native image sharing is unavailable, the app attempts copying the PNG image to the clipboard where the browser supports image clipboard writes.
7. If both direct actions are unavailable or fail, the app opens a clean screenshot mode showing only the generated share card, with minimal controls outside the screenshot area. The user can then take one device screenshot manually.

The fallback screenshot mode is part of the feature, not an error state. It should be clear and calm, with a close action and no overlay covering the card.

Because note text is not truncated, unusually long notes can make the generated PNG taller than a phone viewport. The generated image must still include the full text. Screenshot mode should fit the whole card on screen when practical, but it must not hide, shorten, or rewrite note content.

## Architecture

### Share Card Widget

Create a reusable widget responsible only for the generated image layout, for example:

`EventAssignmentsShareCard`

Inputs:

- `Event event`
- `List<Assignment> assignments`
- `List<Role> activeRoles`
- `List<AssignmentLabel> labels`
- Current grouping mode

Responsibilities:

- Apply the same role and label ordering rules as `EventAssignmentsDialog`.
- Build numbered note references deterministically from visual assignment order.
- Render the RTL card with stable spacing and compact typography.
- Exclude all interactive-only UI such as phone buttons and status chips.

### Image Capture

Wrap the share card in a `RepaintBoundary` with a `GlobalKey`, then capture it to PNG bytes using Flutter rendering APIs. The capture should use a high enough pixel ratio for WhatsApp readability on modern phones.

The capture target should be the share card only, not the full dialog.

### Web Sharing Service

Add a small client-side service for web image sharing, for example:

`AssignmentShareImageService`

Responsibilities:

- Accept PNG bytes and filename metadata.
- Try Web Share API file sharing with feature detection.
- Try image clipboard write with feature detection.
- Report a result enum such as `shared`, `copiedImage`, or `needsManualScreenshot`.

Flutter's built-in `ClipboardData` supports plain text, so image clipboard support must use web interop rather than `Clipboard.setData`.

References:

- Flutter `ClipboardData` currently supports plain text: https://api.flutter.dev/flutter/services/ClipboardData-class.html
- MDN Web Share API file sharing: https://developer.mozilla.org/docs/Web/API/Navigator/share
- MDN Clipboard image writes with `ClipboardItem`: https://developer.mozilla.org/en-US/docs/Web/API/Clipboard/write

## Data Flow

The share action should use the same loaded data already displayed in the dialog:

1. `EventAssignmentsDialog` receives or loads assignments.
2. Labels are applied through the existing assignment-label stream.
3. Roles come from `RoleBloc`.
4. The share button is enabled only when assignments, roles, labels, and event details are available.
5. The share card receives normalized data and creates the visual layout.
6. The capture service converts the card to PNG.
7. The web sharing service tries direct sharing/copying.
8. If needed, the dialog opens screenshot mode with the same card rendered visibly.

Because the share image needs event date, times, and location, the dialog should receive the full `Event` object or an explicit event-details value object. Passing only `eventName` is no longer sufficient for the share feature.

## Error Handling

- If assignments are empty, show the existing empty state and keep the share action disabled.
- If image capture fails, show screenshot mode if the share card can still be rendered.
- If native share is unavailable or rejected, try image clipboard copy.
- If image clipboard copy is unavailable or rejected, open screenshot mode.
- If the user cancels native sharing, do not show a scary error. Return to the dialog or screenshot mode depending on platform behavior.

## Testing And Verification

Implementation should be verified with:

- `flutter analyze` from `shavtzak/`.
- Manual mobile browser test for role-grouped image.
- Manual mobile browser test for label-grouped image.
- Manual test for assignments with no notes.
- Manual test for assignments with several full notes.
- Manual test for unusually long notes, verifying the PNG includes the full note text.
- Manual test for multi-day event header.
- Manual test that status, phone, and alternate-phone details do not appear in the generated image.
- Manual test that screenshot mode shows a clean card without dialog chrome covering it.

No Cloud Functions deployment is required for this client-only feature.
