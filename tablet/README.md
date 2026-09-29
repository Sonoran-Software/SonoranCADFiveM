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

### Moving or deleting station displays

Run `/caddisplay` on foot to open **Station CAD Displays**, select the placement,
then use **Edit Selected Display** or **Delete
Selected Display**. Station management does not require a compatible vehicle.

Station and vehicle placement use a mouse gizmo. Drag colored axes or plane handles
to move, click **Rotate** for rotation rings, and use the mouse wheel/right-drag to
zoom/orbit. **Frame object** centers the view. Click **Save station display** to
finish station placement. Vehicle placement offers **Apply to this vehicle** and,
for vehicle administrators, **Save for this vehicle model**. **Cancel** discards
the preview. Stop the vehicle before editing. The reusable editor API is documented
in `sonorancad/core/placement/README.md`.

With restricted ACE permissions, you need menu access (`sonoran.caddisplay`) and
station management (`sonoran.caddisplay.world`) using the default configuration.
Vehicle placement admin access alone does not grant station management. For an
existing `group.admin` group, a server administrator can grant these in `server.cfg`:

```cfg
add_ace group.admin sonoran.caddisplay allow
add_ace group.admin sonoran.caddisplay.world allow
```

Use your actual admin group and configured ACE names. Framework mode uses the
configured admin jobs; custom mode uses permission check type `1` for station
management. Station displays must also have `worldDisplays.enabled = true`.

### Screen alignment

The standard `prop_laptop_jimmy` works without adding an `interaction` section:
the client includes the default corners, enables interaction, and uses a 900 ms
transition. Explicit settings in your config override these defaults.

To calibrate a screen in game:

1. Close the tablet. Stand within 3 metres of a station display, or sit in the
   stationary vehicle containing the attached laptop or configured built-in screen.
2. Run `/caddisplay calibrate` (use your configured command name if different).
   You need menu permission plus station or vehicle display administration permission
   for the selected target.
3. Follow the numbered markers **1 top-left, 2 top-right, 3 bottom-right,
   4 bottom-left**, viewed from the front. Aim with the mouse and click to place
   the selected marker on the target's collision; Tab selects the next marker.
4. Fine-tune with arrows (model X/Z) and Page Up/Down (model Y/depth). Hold Shift
   for smaller movements, or Ctrl to move all four corners together. Inspect the
   screen from different viewing angles to check depth. Models without an existing
   profile start with a placeholder rectangle in front of the camera.
5. R restores the starting corners. F flattens corner 4 onto the plane of corners
   1-3. Enter validates and applies the profile locally; Backspace cancels.
6. Press G to test the live CAD alignment. Copy the printed F8 block into your
   active `caddisplay_config.lua` to keep it for everyone, then restart `sonorancad`.
   Replace the existing model entry when present, keeping one profile per model.
   Prop blocks belong inside `interaction.models` (numeric model hashes are valid);
   built-in screen blocks belong inside that vehicle's `builtinScreens` entry.

Calibration does not save server files or change other players' screens. Local
test profiles last until the resource restarts. Collision can differ from the
visible screen, so use the manual adjustments when click placement misses the
bezel. The editor handles entity rotation and scale when exporting model coordinates.

The optional `interaction` section in `caddisplay_config.lua` controls this mode:

- `enabled = false` disables laptop camera interaction; `/tablet open` remains available.
- `transitionMs` sets the camera transition duration (default 900 ms). Entry eases
  position, rotation, and field of view from the player's current camera; CAD fades
  in after the camera settles. Exit eases position, rotation, and field of view
  over the same duration, following the gameplay camera as the player/vehicle moves.
- `models[modelName].corners` defines four model-local screen corners in metres,
  ordered **top-left, top-right, bottom-right, bottom-left**, looking at the screen.
  Coordinates describe the visible screen area inside the bezel, not the whole prop.
- A `builtinScreens` entry can supply `interaction = { corners = { ... } }`.
  Its corners are relative to the vehicle origin. A texture name or texture size
  alone cannot locate a custom vehicle's monitor in 3D.

The standard `prop_laptop_jimmy` has an approximate starting profile even with an
older configuration. Its corners have been adjusted from an in-game screenshot;
confirm the fit against the actual asset in FiveM before release. If your active
config includes the earlier laptop corners or `transitionMs = 450`, copy the updated
values from `caddisplay_config.dist.lua`; explicit local settings still take precedence.
Custom props and built-in vehicle screens without profiles report which profile is
missing. G never silently opens the handheld tablet in place of the laptop view.
The projection follows entity rotation/scale and screen resolution; the iframe's
viewport uses the screen's aspect ratio. The focused camera matches the screen's
roll so its top edge appears level even when the laptop or vehicle is tilted.
Normal tablet dimensions and position are preserved when you exit.

For branch testing, copy both resources from the feature branch and restart them.
The built-in Sonoran updater installs published release archives; it does not
install unreleased branch commits. Pressing G with the current client code prints
`[caddisplay] G interaction (laptop camera)` in F8, followed by the profile result
and camera-start status. These lines help distinguish old client files, missing
profiles, disabled interaction, and a camera that starts but fails to display CAD.

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
