# tablet
View your CAD in-game with our tablet resource!

The tablet command defaults to `/tablet`. To change it, add `setr sonorantablet_command "yourcommand"` to your server configuration.

## Installation

[Click to view the installation guide.](https://info.sonorancad.com/integration-submodules/integration-submodules/available-submodules/tablet)

## Linking

This tablet expects the player to link their CAD account in-game with `/link`.

- If the account is not linked, the tablet shows a retry banner.
- The retry flow checks CAD link status instead of prompting for any manual identifier entry.
- Tablet SSO data is forwarded to the main `sonorancad` resource for CAD account association.
- The server-side event names and FiveM exports are documented in `sonorancad/LINKING_V2.md`.

## Using an in-world CAD display

With the CAD display submodule enabled, press its interaction key (default **G**)
near a station laptop or while seated in a vehicle with a display. Once control is
granted, the camera moves toward the screen and the existing live CAD iframe fits
inside it. Click and type normally; your CAD login and current page stay loaded.
Use **Exit computer** below the screen to return to the game. Escape also closes
when the tablet's outer page has keyboard focus; the exit button works even when
focus is inside the CAD iframe.

You do not need to run `/tablet` first. `/tablet` shows command help, while
`/tablet open` opens the separate handheld tablet. Close the handheld tablet before
pressing **G** to use a laptop. If the laptop view cannot start, its notification
explains why; export/native errors are also printed in F8 with a `[caddisplay]` prefix.

Both `sonorancad` and `tablet` must be updated together. This uses a screen-aligned
NUI iframe for the interacting player. Other players continue to see the existing
periodic screenshot texture; this does not stream a live CAD session to spectators.
Control requests still use the display's existing ownership/accept/deny flow.
Death, leaving the vehicle, losing ownership, removal of the display, or stopping
either resource closes the focused view and restores the camera and input.

### Screen alignment

The optional `interaction` section in `caddisplay_config.lua` controls this mode:

- `enabled = false` keeps the normal tablet presentation.
- `transitionMs` sets the camera transition duration (default 450 ms).
- `models[modelName].corners` defines four model-local screen corners in metres,
  ordered **top-left, top-right, bottom-right, bottom-left**, looking at the screen.
  Coordinates describe the visible screen area inside the bezel, not the whole prop.
- A `builtinScreens` entry can supply `interaction = { corners = { ... } }`.
  Its corners are relative to the vehicle origin. A texture name or texture size
  alone cannot locate a custom vehicle's monitor in 3D.

The standard `prop_laptop_jimmy` has an approximate starting profile even with an
older configuration. Calibrate it against the actual asset in FiveM before release.
Custom props and built-in vehicle screens without profiles open the normal tablet.
The projection follows entity rotation/scale and screen resolution; the iframe's
viewport uses the screen's aspect ratio. Normal tablet dimensions and position are
preserved when you exit.

### Validation

From the repository root, run `node --test tablet/tests/*.test.js` and
`lua tablet/tests/display-session.test.lua`. These cover projection math, NUI
lifecycle, and mocked camera/input cleanup. They do not validate FiveM rendering.
The regression tests also cover FiveM's parent-window message delivery and the
G-command ownership flow for station and vehicle displays.

In-game QA should cover clicking/typing/scrolling in the CAD, exact bezel alignment,
16:9 and ultrawide resolutions, rotated/scaled station props, passenger use in a
moving vehicle, accepted/denied ownership transfers, repeated open/close, death,
display deletion, and restarting either resource during entry and exit transitions.

## Notepad sync relay

The tablet owns the authenticated CAD iframe used by `sonoran-notepad`. Validated
`scad:notepad:get` and `scad:notepad:set` messages arrive through the local
`SonoranCAD::Tablet::NotepadSyncRequest` event and are queued until the current CAD
iframe finishes loading. Responses return through the local
`SonoranCAD::Tablet::NotepadSyncResponse` event. The relay derives the current iframe
origin, requires the iframe window as the message source, and never posts notepad
messages to a wildcard origin. Note objects and metadata are forwarded unchanged.

Sync availability requires both the server-confirmed community link and a responsive
CAD iframe session. The iframe's validated `scad:account-link` event is used as the
login signal, and a read-only `scad:notepad:get` probe after each iframe load confirms
that the current page can service the notepad API. Until both checks pass, SET messages
are rejected locally so `sonoran-notepad` can continue in local-only mode.
