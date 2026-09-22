# CAD-managed configuration (feature draft)

This branch requires the matching `feat/5M-config` backend, database migration, frontend, and translations. Configure each server in **CAD → In-Game Integration → FiveM**, then Save before starting this resource. An unsaved server waits and retries every 60 seconds.

Local `configuration/config.json` now contains only `communityID`, `apiKey`, `serverId`, and `mode`. Keep `updateIgnore.json` as well. Feature configuration comes from the authenticated V2 endpoint; it is never executed as remote Lua. There is no offline cache.

To preserve existing customized settings, keep the old local files temporarily, run `sonoran_config_export` in the **server console**, and import `filestore/configuration-import.json` in CAD. Review and Save. Unsupported customized Lua functions stop export and require migration into a reviewed named hook. Existing files are not deleted by the migration command, and credentials are excluded from its output.

**Apply and restart** sends a server-specific push event. The resource fetches and verifies the requested saved revision before restarting itself after five seconds. Online players may lose active CAD/camera interactions. A disconnected push connection must be retried; saved settings load at the next startup regardless.

For branch testing, disable automatic updates in CAD so a future master release cannot replace this draft. No production version promotion is included. Test an actual FXServer with the matching test backend before release.

The full schema/storage/API design and raw SQL are in the backend repository's `FIVEM_CONFIGURATION.md` and `SauceCAD_2_Backend/migrations/2026-09-21_fivem_configurations.sql`.

Offline checks: `python -m unittest discover -s tests -p test_remote_configuration.py` (requires Python and `lupa`).
