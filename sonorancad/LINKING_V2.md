# Sonoran CAD Linking V2

This resource now uses Sonoran CAD API v2 and the bundled `Sonoran.lua` client for CAD linking.

## Player Flow

- Players run `/link` in-game.
- The resource opens a NUI popup with a `Link CAD` button.
- The server creates a 4-character Sonoran CAD community link code for the player's `communityUserId`.
- The button opens the player's external browser to `sonorancad.com/id?code=...`.
- While the popup is open, the resource checks link status every 10 seconds.
- Link codes expire after 10 minutes.
- ForceReg can keep the popup open until the player is linked.

## Config

The core link flow is configured in `sonorancad/configuration/config.json`:

- `linkCommand`
- `requireLink`
- `autoOpenLinkPopup`
- `freezeUntilLinked`
- `allowPopupCloseWhenUnlinked`
- `linkPollIntervalMs`
- `linkPopupTitleText`
- `linkButtonText`

## Third-Party Exports

Other resources can read the configured CAD community ID and server ID directly from this resource:

```lua
local communityId = exports.sonorancad:getCommunityId()
local serverId = exports.sonorancad:getServerId()
```

Compatibility aliases are also exported:

```lua
local communityId = exports.sonorancad:getCadCommunityId()
local serverId = exports.sonorancad:getCadServerId()
```

If a resource needs the linked CAD user for a player:

```lua
local communityUserId = exports.sonorancad:getPlayerCommunityUserId(source)
```

The customer must still provide their CAD API key in the normal SonoranCAD config. Third-party resources should not try to fetch the API key from this resource.
The values returned by `getCommunityId()` and `getServerId()` come from `communityID` and `serverId` in the Sonoran CAD FiveM core config.

## Tablet / SSO Hook

The tablet and other iframe-based UIs can forward an SSO/session identifier into the resource:

```lua
TriggerServerEvent("SonoranCAD::Tablet::AssociateSsoData", sessionId, username)
```

The resource then attempts to associate that SSO data with the player's FiveM identifier through the v2 CAD link flow.
The iframe bridge validates the incoming `session` / `username` payload before forwarding it to the server.

Tablet link status can be checked with:

```lua
TriggerServerEvent("SonoranCAD::Tablet::CheckLinkStatus")
```

Client status events:

- `SonoranCAD::Tablet::LinkFound`
- `SonoranCAD::Tablet::LinkMissing`
