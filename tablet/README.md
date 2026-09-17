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
