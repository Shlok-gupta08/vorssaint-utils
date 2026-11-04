# Dynamic Island settings organization

The redesign keeps the existing preference keys and saved extension button IDs,
labels, positions and order. Six workspaces replace the nested task sidebar:
Quick setup; Design & displays; Content & buttons; Activities & alerts;
Behavior; Privacy. Specialist editors are secondary choices within their workspace.

Quick setup exposes everyday choices. Content uses a searchable page library and
an inspector; page ordering and previews are available on demand. Controls only
contains button configuration. Music activity visibility, player suppression and
pause timing live together in Activities. Fitting and dormant call support stay
inside Advanced disclosures.

The workspace fills its viewport. Related groups flow into one, two or three
columns as space permits, placing the next group in the shorter column instead
of reserving blank space under a shorter card. Navigation uses up to six columns. No detail pane has a fixed maximum width. Every navigation button uses
the same full-label hit area, including transparent padding. The development
probe dispatches three padding clicks to an owned test window and renders all
editors at 540, 900, 1440 and 2048 points without desktop input.

| Task | Options retained |
| --- | --- |
| Appearance | Expanded scale, presets, custom width/height, translucent background, outline |
| Displays | Per-display inclusion and live activity, shape, automatic/single/pointer placement, full-screen policy, hidden until hover, physical-camera and capsule fitting |
| Pages & controls | All existing pages, page order and inclusion, individual feature settings, Control Center contents and order |
| Extensions | Existing graphical editor, left/right/bottom placement, button names, actions, reordering, removal, graphical resize handles |
| Live activities | Resting content, menu coverage, music display/pause hold, Keep Awake, links to timer/calendar/download/agent/watch activity configuration |
| Notifications | System notification inclusion, native banner suppression, permissions, every existing feedback source |
| Interaction | Click/hover opening, preview/expand behavior, delay, gestures, haptics, reopening destination, open-current-activity behavior |
| Routing | Separate-window vs island destinations, menu bar icon, quick panel, clipboard, shelf, captures, scratchpad |
| Privacy & lock screen | Capture visibility, lock-screen island and lock/unlock sounds |

## Customization contract

`NotchCustomizationCatalog` supplies the extension chooser. Pages are sourced
from `NotchModule.allCases`; actions are sourced from `NotchControlItem`.
Page-backed controls declare `destinationModule` so the chooser lists each page
once, with genuine actions in their own group. Older saved action identifiers
remain decodable even when the chooser offers their canonical page equivalent.

Control Center now supports links to all other island pages and the actionable
utilities from the quick panel, plus starting dictation, clipboard
history, and camera preview. Side and bottom buttons use the same activation
path and availability checks as Control Center. Volume and brightness are also
available to add as buttons that open Controls.

Unavailable choices remain visible with an explanation and a setup route.
Background-only services are not presented as one-shot actions. Hosted utilities
require the quick panel feature, and page links require that page to be included.

New controls are opt-in. Migration and old-backup normalization add their IDs to
the hidden set without changing existing visible controls. Explicit additions
are recorded in the order and preserved by future imports and launches.
