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
