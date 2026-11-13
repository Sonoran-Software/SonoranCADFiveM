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

Configure the core link flow through the FiveM configuration in CAD:

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

The customer provides `apiKey` and `serverId` in the resource-root `config.json`. Third-party resources should not try to fetch the API key from this resource.
The community ID comes from CAD; the server ID comes from the resource-root `config.json`.

## Tablet / CAD Iframe Account Link

The tablet validates the CAD iframe's `scad:account-link` message and forwards the account and secret UUIDs to the server:

```lua
TriggerServerEvent("SonoranCAD::Tablet::SetCommunityLink", accountUuid, secretUuid)
```

The server derives the player's `communityUserId` from the configured FiveM identifier and calls the v2 `setCommunityLinkV2` endpoint. The account UUID and secret UUID are validated server-side; the secret is not logged or persisted.

The legacy `SonoranCAD::Tablet::AssociateSsoData` event remains available for compatibility with older external tablet integrations, but new integrations should use the account-link event above.

Tablet link status can be checked with:

```lua
TriggerServerEvent("SonoranCAD::Tablet::CheckLinkStatus")
```

Client status events:

- `SonoranCAD::Tablet::LinkFound`
- `SonoranCAD::Tablet::LinkMissing`
