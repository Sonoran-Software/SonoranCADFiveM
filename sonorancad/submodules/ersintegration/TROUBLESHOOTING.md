# ERS integration troubleshooting

The [ERS setup guide](https://docs.sonoransoftware.com/cad/integration-plugins/in-game-integration/available-plugins/ers) covers installation and CAD record templates. On the game server, confirm that `night_ers` is started, reports version `1.8.16` or newer, and that `ersintegration_config.lua` has `enabled = true`. Start `night_ers` before `sonorancad` when possible. The integration also recovers when `night_ers` starts or restarts later.

## Check the integration

Run `sonorancad ers` in the **server console**. The output shows the ERS resource state, detected version, enabled actions, callout catalog sync, event counts, postal source, configuration issues, and the latest failed and successful stages. No API key is included in this ERS health section.

| Status | What to check |
| --- | --- |
| `disabled in config` | Set `enabled = true` in the active `ersintegration_config.lua`, then restart `sonorancad`. |
| `night_ers is not started` | Start or restart `night_ers`. |
| `night_ers version is below 1.8.16` | Update Night ERS, then restart it. An unverified version produces a warning but does not block startup. |
| `invalid ERS configuration` | Read `configIssues` in the health output and correct the named setting. |
| `running with record configuration issues` | Callouts can still work, but record lookups need the missing `customRecords` fields and matching CAD templates. |
| `night_ers getCallouts failed` | Confirm ERS has loaded its callouts. The integration retries automatically. |
| `CAD catalog upload failed` | Check CAD API connectivity and the configured server ID. The integration retries automatically. |
| `no callouts configured in night_ers` | Confirm that callouts are enabled in ERS; the integration checks again periodically. |

If the callout catalog says `synced to CAD` but an individual callout still fails, inspect `lastFailure.stage` and `lastFailure.reason`. For a player who does not receive a callout, confirm that the player is linked to CAD, has an active CAD unit, and is on an ERS shift with a service type. Use `sonorancad getclientlog <playerId>` in the server console for the player's client messages.

## Check the action that should create the data

An ERS callout offer can create a CAD 911 call when `create911Call` is enabled. Accepting the call **inside Night ERS** can create a CAD dispatch call when `createEmergencyCall` is enabled. Using `/dn respond` on a Sonoran dispatch notice does not accept the call inside ERS. NPC character and vehicle records are created when ERS sends the character or vehicle interaction data; accepting a call alone does not guarantee those records exist. The `features` and `counters` fields in `sonorancad ers` show which of these actions are enabled and whether the corresponding ERS events reached CAD.

## Postals and record templates

ERS call locations use the CAD postals dataset when its coordinate lookup is available, including custom file mode. If that lookup fails, the integration uses the configured postal resource in resource mode, then an ERS supplied postal if present. Call creation continues with `Unknown postal` when none are available. Check `postal.lastSource`, `postal.lastReason`, and `postal.fallbacks` if CAD and the game show different postals. The CAD postals configuration must reference the same map data you expect to see in dispatch.

If a vehicle or character record fails with HTTP 409, check unique fields on the corresponding CAD record template. A duplicate value, such as an existing plate, causes CAD to reject the record even while ERS calls continue working. The support bundle records the failed stage and CAD error code.

To send the full diagnostic bundle to support, run `/sonorancad support <id>` in game or `sonorancad support <id>` in the server console using the ID supplied by Sonoran support. The bundle includes the ERS health section and structured ERS error codes `ERR-ERS-101` through `ERR-ERS-112`. For communities using database sync, the [CAD setup guide](https://docs.sonoransoftware.com/cad/integration-plugins/in-game-integration/available-plugins/ers#database-sync) explains how to include CAD API records in lookups.
