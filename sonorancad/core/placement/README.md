# Shared mouse placement editor

The CAD display uses this editor for station and vehicle prop placement. It has no
external resource or JavaScript library dependency. The core NUI loads `placement.js`;
the manifest loads `math.lua` and `client.lua` before submodules.

Drag a red/green/blue axis to move on X/Y/Z, or a colored square to move in a plane.
Click **Rotate** for rotation rings. **Local axes / World axes** switches alignment;
**Snap** enables 1 cm movement and 5 degree rotation increments. Right-drag orbits
the camera, the wheel zooms, and **Frame object** brings the object into view.
**Reset**, **Apply**, and **Cancel** are clickable. Scale is preserved, not edited.

## Reuse from another client script

```lua
local opened, reason = exports["sonorancad"]:StartPlacementEditor({
    entity = previewObject, -- existing local object, or a network entity you control
    title = "Place a sign",
    maxDistance = 10, -- maximum movement from the initial position, metres
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
world matrix into a bone-relative transform. `SonoranPlacementMath.relative` and
`rotation(matrix, 0)` produce the existing attachment format without subtracting
Euler angles. No attachment or server persistence policy is built into the editor.

## NUI contract

All messages require the current numeric `session`. Browser messages are accepted
only from the actual FiveM parent frame and its exact origin; stale sessions are ignored.

* Game → UI `placement_editor`: `enabled`, `session`, and, when enabled, `title`
  and `actions = [{id,label}]`. Hiding releases pointer state.
* Game → UI `placement_frame`: `session`, `mode` (`move`/`rotate`), `space`
  (`local`/`world`), `snap`, world `position`/`rotation`, and `handles`.
  Each handle has `id` (`x/y/z/xy/xz/yz`), `kind` (`axis/plane/ring`), and normalized
  projected `points`. `false` points are not visible and break rendered paths.
* UI → `placementInput`: JSON `{session, action, ...}`. Actions: `mode` with
  `value`; `space`, `snap`, `reset`, `focus`, `cancel`; `finish` with an advertised
  `choice`; `down` with `handle,x,y`; `drag` with `x,y`; `up`; and `camera` with
  normalized `dx,dy` and signed `zoom`. Callback replies `{ok:boolean}`. Pointer
  coordinates must be finite and in [0,1]; the server save path remains separate.

Mouse events are ordered and coalesced under callback latency so stale drag events
cannot overtake release or Apply. Switching tools clears the active drag.

## Verification

Run `lua tablet/tests/placement-editor.test.lua` from the repository root. The
optional `tablet/tests/placement-ui.browser.cjs` uses Playwright/Edge; provide
`PLAYWRIGHT_MODULE` if Playwright is installed outside the normal Node resolution
path. Real in-game bone placement, camera clipping, and NUI latency need FiveM QA.
