# CAD-managed FiveM configuration

This branch requires the matching CAD backend, database migration, game-panel frontend, and translations. Configure each server under **CAD > In-Game Integration > FiveM**. The resource fetches one resolved configuration document at startup and does not execute downloaded Lua.

`configuration/config.json` retains only the connection bootstrap values: `communityID`, `apiKey`, `serverId`, and `mode`. `configuration/updateIgnore.json` also remains local. All core and submodule feature settings come from CAD.

## Existing installations

When legacy core keys, `*_config.lua`, `*_config.dist.lua`, or `livemap_vehicle_models.json` are present, the resource:

1. Loads the CAD document and overlays every detected local value so existing behavior is preserved.
2. Sends `POST /v2/fivem/servers/{serverId}/configuration/migrate` with `{schemaVersion: 1, values: {core, plugins}}`. The endpoint stores the imported values and marks the server as awaiting migration review.
3. Logs `ERR-CORE-037` every 60 seconds until migration is completed in CAD.
4. Continues serving the local overrides to server and client scripts while the files remain.

After an administrator verifies the imported settings, the CAD migration action sends this authenticated websocket-only event:

```json
{
  "type": "EVENT_FIVEM_CONFIGURATION_MIGRATION",
  "data": {
    "serverId": 1,
    "revision": 4,
    "schemaVersion": 1,
    "templateRevision": "CATALOG_SHA256"
  }
}
```

Before deleting anything, the resource fetches the configuration again and requires the exact reviewed revision and catalog fingerprint. It then rewrites `config.json` to bootstrap values, removes legacy configuration files, preserves `updateIgnore.json`, and restarts after five seconds. Failed verification or filesystem operations cancel cleanup.

`EVENT_FIVEM_CONFIGURATION` remains the non-migration **Apply and restart** event. It follows the same server/schema/revision/fingerprint verification and restart delay but does not delete files.

There is no offline cloud cache. A new installation with no saved CAD configuration waits and retries every 60 seconds. An existing installation with local files keeps running from local overrides while upload/fetch operations retry.

## Validation

Offline contract tests cover startup loading, local precedence, migration upload, authenticated push handling, revision verification, cleanup gating, and hook/native-value reconstruction. Live release validation still requires an FXServer connected to the matching backend and CAD panel.
