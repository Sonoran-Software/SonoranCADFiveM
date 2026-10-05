# Shared mouse placement editor

The CAD display uses this editor for station and vehicle prop placement. It has no
external resource or JavaScript library dependency. The core NUI loads `placement.js`;
the manifest loads `math.lua` and `client.lua` before submodules.

Drag either end of a red/green/blue axis to move on X/Y/Z, or a colored square to
move in a plane. Handles stay compact on screen and highlight yellow when selected.
Click **Rotate** for rotation rings, including an outer ring aligned to the view.
**Local axes / World axes** switches alignment;
**Snap** enables 1 cm movement and 5 degree rotation increments. Station placement
uses right-drag to orbit, middle-drag to pan, the wheel to move closer/farther, and
**Frame object** to bring the object into view. **Original view** restores its camera.
Vehicle placement starts with a scripted camera between the front seats, slightly
behind the driver's head, aimed at the display. Right-drag looks around by default.
Toggle **Orbit laptop** to make right-drag circle the display's current bounds
center while keeping the same distance. Switching modes keeps the current camera
pose. Middle-drag leans by up to 12 cm from the current camera anchor; orbiting or
switching modes establishes a new anchor. **Look at display**
aims toward the prop's bounds center without moving the camera; **Cabin view**
restores the starting position, aim, lens, and look-around mode. The starting field of view is
65 degrees. The wheel adjusts the scripted lens between 35 and 85 degrees without
moving the camera or prop. Gameplay camera motion and head animations do not move
the editor camera, and the player remains visible by default.
**Reset**, **Apply**, and **Cancel** are clickable. Scale is preserved, not edited.

Lens changes use `SetCamFov` on the editor's camera. Camera pose/lens values are
converted to Lua floats at the native boundary, including integer zoom limits.
Placement does not execute console commands or alter persistent gameplay camera preferences.

## Reuse from another client script

```lua
local opened, reason = exports["sonorancad"]:StartPlacementEditor({
    entity = previewObject, -- existing local object, or a network entity you control
    title = "Place a sign",
    maxDistance = 10, -- maximum movement from the initial position, metres
    -- Optional view = {position=vector3(...), rotation=vector3(...), fov=65}.
    -- Camera rotation uses order 2. Otherwise the current rendered view is used.
    -- Set view.mode='cockpit' for look/lens zoom/bounded lean instead of orbit.
    -- view.hidePlayer=true hides the local player each active frame in cockpit mode.
    -- Optional view.up is the world up vector used when aiming at the object.
    -- Optional focusOffset={x=0,y=0,z=0} is the model-local camera focus point.
    -- Optional pivotOffset={x=0,y=0,z=0} is the model-local gizmo/rotation center.
    -- These offsets are independent and default to the entity origin.
    actions = {{ id = "apply", label = "Apply sign placement" }},
    validate = function() -- optional; checked every frame and before acceptance
        return DoesEntityExist(previewObject)
    end,
    onFinish = function(result)
        if result.accepted then
            -- result.position and result.rotation are world-space {x,y,z} tables.
            -- Rotation uses GTA order 2 (ZXY). result.action is the chosen action ID.
            -- Validate permission and data on the server before persisting.
            TriggerServerEvent("my-resource:savePlacement", result.position, result.rotation)
        end
        -- The caller owns object creation/deletion and any server persistence.
    end
})
if not opened then print(reason) end
```

The export is asynchronous and returns `(true)` or `(false, reason)`. Only one
editor can be open at a time. Within SonoranCAD use `SonoranPlacementEditor.Start`,
`IsActive`, and `Cancel`; other resources can call the `CancelPlacementEditor`
export. An empty/default actions option should be omitted to get the **Apply** button.

Cancel restores the original matrix (including scale) and freeze states. Acceptance
leaves the chosen transform on the entity. The editor releases NUI focus and camera
control on either outcome; death, leaving the vehicle, entity deletion, failed
validation, or stopping the caller/editor resource cancel automatically. Handle a
cancelled result without writing to the server. Callbacks should not yield. A caller
that opens other NUI should cancel placement first.

The result also contains `entity` and `matrix = {r,f,u,p}` vectors. CAD uses a local
vehicle preview and an invisible zero-offset bone anchor to convert the chosen
world matrix into a bone-relative transform. New vehicle props start 75 cm ahead,
30 cm inboard, and 35 cm below the seated player's head, with the laptop screen
facing the player, even when the gameplay camera is outside. Existing saved prop
positions are unchanged on entry.

The vehicle adapter samples its camera anchor once: lateral position is the
midpoint of valid, separated front-seat bones, falling back to the vehicle
centerline; forward position is 25 cm behind the seated head; height is 3 cm above
the head. All offsets use the vehicle's basis. The camera initially aims at the
transformed model bounds center with vehicle up, and the same model-local bounds
center anchors the gizmo. Rotating about `pivotOffset` compensates the entity
origin so the chosen center stays fixed. `focusOffset` controls camera aim
independently.

Another rendered scripted camera blocks entry with a notification. If another
scripted camera takes over during placement, the editor cancels and destroys
only its own camera without switching off the incoming view. Entry checks for an
existing rendered script camera; active sessions require `GetRenderingCam()` to
remain the editor's camera, including before accepting input. Handles are available on the first editor
frame; there is no gameplay-camera preparation period.
`SonoranPlacementMath.relative` and
`rotation(matrix, 0)` produce the existing attachment format without subtracting
Euler angles. No attachment or server persistence policy is built into the editor.

## NUI contract

All messages require the current numeric `session`. Browser messages are accepted
only from the actual FiveM parent frame and its exact origin; stale sessions are ignored.

* Game → UI `placement_editor`: `enabled`, `session`, and, when enabled, `title`,
  `cameraMode` (`cockpit`/`orbit`), `cameraOrbit`, `cameraZoom`, `ready`, and `actions = [{id,label}]`.
  Camera mode selects the control hints/button labels. While `ready=false`, only
  Cancel is enabled. Hiding releases pointer state.
* Game → UI `placement_frame`: `session`, `mode` (`move`/`rotate`), `space`
  (`local`/`world`), `snap`, world `position`/`rotation`, projected `pivot`, optional
  `selected` handle ID, `cameraOrbit`, `cameraZoom`, `ready`, and `handles`. The scripted editor
  sends `ready=true` and `cameraZoom=true` from entry.
  Each handle has `id` (`x/y/z/xy/xz/yz/view`), `kind` (`axis/plane/ring`), and normalized
  projected `points`. `false` points are not visible and break rendered paths.
* UI → `placementInput`: JSON `{session, action, ...}`. Actions: `mode` with
  `value`; `space`, `snap`, `reset`, `focus`, `view`, `cancel`; `finish` with an advertised
  `choice`; `down` with `handle,x,y`; `drag` with `x,y`; `up`; and `camera` with
  normalized `dx,dy`, signed `zoom`, and optional `pan=true` for middle-drag.
  In cockpit mode `orbit` toggles between looking around and circling the display;
  `cameraOrbit` reports its current state (false by default). Camera input controls
  look/orbit, lens zoom, and bounded lean; `focus` changes aim without moving the
  camera. Other sessions use orbit, dolly zoom, and pan.
  `cameraZoom=false` disables the wheel.
  `view` restores the initial camera and clears the cockpit orbit toggle. Callback replies `{ok:boolean}`. Pointer
  coordinates must be finite and in [0,1]; the server save path remains separate.

Mouse events are ordered and coalesced under callback latency so stale drag events
cannot overtake release or Apply. Switching tools clears the active drag.
Handle projection through `SonoranPlacementMath.project` and drag rays through
`cameraRay` use the same scripted camera pose, FOV, and aspect ratio. Applying a
transform updates engine coordinates before the matrix so frozen previews move too.
Vehicle entry emits a `[placement] Cabin camera` diagnostic with the vehicle-local
camera offset and starting FOV to help verify framing on custom models. The first
rendered frame also logs `Cabin view ready` with the actual camera pose, requested
and actual FOV, and pivot depth. Handles scale with actual positive camera depth;
pivots within 2 cm of the camera plane or behind it have no visible handles.

## Verification

Run `lua tablet/tests/placement-editor.test.lua` from the repository root. The
optional `tablet/tests/placement-ui.browser.cjs` uses Playwright/Edge; provide
`PLAYWRIGHT_MODULE` if Playwright is installed outside the normal Node resolution
path. Real in-game bone placement, camera clipping, and NUI latency need FiveM QA.
Custom vehicle interiors need a visual check that the cabin anchor clears the
seats and roof and that the laptop and its center gizmo remain visible.
