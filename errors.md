# SonoranCAD Error and Warning Codes

This document is generated from the canonical error and warning definitions in [sonorancad/core/logging.lua](/C:/Users/jodan/Documents/GitHub/SonoranCADFiveM/sonorancad/core/logging.lua). If a code changes there, this file should be updated to match.

Each entry includes:
- `Key`: internal identifier used in code
- `Code`: support-facing error code shown to users/logs
- `Meaning`: what the error or warning is telling you
- `Potential Fix`: the first thing to check or change

Warnings use a `WRN-*` prefix. Errors use an `ERR-*` prefix. Some warning-level log paths still intentionally reference `ERR-*` codes when the condition represents a real support issue even if the integration can keep running.

## Core Errors

### ERR-CORE-001
- `Key`: `STEAM_ERROR`
- `Meaning`: SonoranCAD is configured to use Steam identifiers, but the FXServer Steam Web API key is missing.
- `Potential Fix`: Set `steam_webapiKey` in your server configuration or switch `primaryIdentifier` away from `steam`.

### ERR-CORE-002
- `Key`: `PORT_MISSING_ERROR`
- `Meaning`: The configured CAD server entry could not be found for the active `serverId`.
- `Potential Fix`: Verify the `serverId` in `config.json`/convars and confirm that the same server exists in the CAD server list.

### ERR-CORE-003
- `Key`: `PORT_CONFIG_ERROR`
- `Meaning`: The game server port does not match the port configured in CAD.
- `Potential Fix`: Align the FXServer `netPort` with the CAD server entry, or allow the integration to auto-correct the CAD entry.

### ERR-CORE-004
- `Key`: `MAP_CONFIG_ERROR`
- `Meaning`: The live map port configured in CAD does not match the server configuration.
- `Potential Fix`: Update the CAD map/listener port for the affected `serverId` so it matches the actual server port.

### ERR-CORE-005
- `Key`: `PORT_OUTBOUND_ERROR`
- `Meaning`: The detected outbound IP does not match the configured CAD IP.
- `Potential Fix`: Update the CAD server IP/outbound IP settings to the actual public IP used by the server.

### ERR-CORE-006
- `Key`: `PORT_OUTBOUND_MISMATCH`
- `Meaning`: SonoranCAD detected an IP mismatch between runtime networking and CAD configuration.
- `Potential Fix`: Review `mapIp`, `outboundIp`, and `differingOutbound` in the CAD server entry and correct them.

### ERR-CORE-007
- `Key`: `CONFIG_ERROR`
- `Meaning`: The core configuration could not be loaded or parsed.
- `Potential Fix`: Ensure `sonorancad/configuration/config.json` exists, is valid JSON, and is not accidentally named something like `config.json.json`.

### ERR-CORE-008
- `Key`: `API_ERROR`
- `Meaning`: The integration could not retrieve version information from the CAD API.
- `Potential Fix`: Check the API key, community ID, outbound connectivity, and SonoranCAD API status, then restart the resource.

### ERR-CORE-010
- `Key`: `ERROR_ABORT`
- `Meaning`: Startup was aborted because one or more critical errors were encountered.
- `Potential Fix`: Review earlier `ERR-*` entries in the console/log buffer, correct the first critical failure, and restart the resource.

### ERR-CORE-011
- `Key`: `PLUGIN_DEPENDENCY_ERROR`
- `Meaning`: A submodule was enabled but one of its required dependencies was not loaded.
- `Potential Fix`: Install/start the missing dependency resource or disable the submodule that requires it.

### ERR-CORE-012
- `Key`: `PLUGIN_VERSION_MISMATCH`
- `Meaning`: A submodule requires a newer version of another plugin/resource than is currently available.
- `Potential Fix`: Update the named plugin/resource to the required version or disable the dependent submodule until versions match.

### ERR-CORE-013
- `Key`: `PLUGIN_CONFIG_OUTDATED`
- `Meaning`: A submodule configuration file is older than the current template version.
- `Potential Fix`: Compare your local submodule `*_config.lua` version against the required `*_config.dist.lua` version, copy over the missing settings, then restart the submodule.

### ERR-CORE-014
- `Key`: `PLUGIN_CORE_OUTDATED`
- `Meaning`: A plugin requires a newer SonoranCAD core than the one currently installed.
- `Potential Fix`: Update the SonoranCAD core resource to the required version.

### ERR-CORE-015
- `Key`: `CUSTOM_POSTALS_FILE_NOT_FOUND`
- `Meaning`: The configured custom postals file could not be found.
- `Potential Fix`: Place the referenced file in the expected postals directory or update the config to point to the correct filename.

### ERR-CORE-016
- `Key`: `POSTAL_RESOURCE_MISSING`
- `Meaning`: The configured postal resource name does not exist on the server.
- `Potential Fix`: Correct the resource name in config or install the missing postal resource.

### ERR-CORE-017
- `Key`: `POSTAL_RESOURCE_STOPPED`
- `Meaning`: The postal resource exists but is not started.
- `Potential Fix`: Add the postal resource to your startup config and ensure it starts before players connect.

### ERR-CORE-018
- `Key`: `POSTAL_RESOURCE_BAD_STATE`
- `Meaning`: The postal resource is present but in an invalid/bad runtime state.
- `Potential Fix`: Inspect that resource for startup errors, fix them, and restart it before starting SonoranCAD features that rely on it.

### ERR-CORE-019
- `Key`: `POSTAL_FILE_READ_ERROR`
- `Meaning`: SonoranCAD could not read the configured postal data file.
- `Potential Fix`: Verify the file exists, is readable by the server process, and is valid for the selected postal mode.

### ERR-CORE-020
- `Key`: `POSTAL_CUSTOM_RESOURCE_FILE_ERROR`
- `Meaning`: A custom postal resource did not expose the expected postal file metadata.
- `Potential Fix`: Add the expected `postal_file` metadata to that resource’s `fxmanifest.lua` or use a supported postal resource.

### ERR-CORE-021
- `Key`: `IDCARD_RESOURCE_NOT_STARTED`
- `Meaning`: The `sonoran_idcard` resource is installed but not running.
- `Potential Fix`: Use `exec sonorancad.cfg` and make sure `sonorancad.cfg` contains `ensure sonoran_idcard` before `ensure sonorancad`.

### ERR-CORE-022
- `Key`: `IDCARD_RESOURCE_MISSING`
- `Meaning`: The `sonoran_idcard` resource could not be found.
- `Potential Fix`: Use the bundled `sonorancad.cfg`, confirm it contains `ensure sonoran_idcard`, and install the resource with the exact name `sonoran_idcard`.

### ERR-CORE-023
- `Key`: `IDCARD_RESOURCE_BAD_STATE`
- `Meaning`: The ID card resource exists but is not in a usable runtime state.
- `Potential Fix`: Use `exec sonorancad.cfg`, confirm it contains `ensure sonoran_idcard`, and fix the startup errors reported by `sonoran_idcard`.

### ERR-CORE-024
- `Key`: `INCORRECT_WKWARS2X_VERSION`
- `Meaning`: The installed `wk_wars2x` resource version is incompatible with this integration.
- `Potential Fix`: Replace it with the supported version from Sonoran Software’s repository.

### ERR-CORE-025
- `Key`: `CAD_API_DISABLED`
- `Meaning`: API sending is disabled by configuration or a runtime toggle.
- `Potential Fix`: Re-enable API sending in config/convars or stop using features that require outbound CAD API requests.

### ERR-CORE-026
- `Key`: `UPDATE_CHILD_PERMISSION`
- `Meaning`: Auto-update failed because FiveM child-process permission was not granted.
- `Potential Fix`: Run `exec sonorancad.cfg` or add the required child-process ACE/permission for SonoranCAD’s updater.

### ERR-CORE-027
- `Key`: `INVALID_API_MODE`
- `Meaning`: The configured SonoranCAD API mode was invalid and the resource fell back to production.
- `Potential Fix`: Set `mode` to a supported value such as `production` or `development`.

### ERR-CORE-028
- `Key`: `FILE_WRITE_FAILED`
- `Meaning`: The resource failed to write a required file to disk.
- `Potential Fix`: Check folder permissions, available disk space, and whether the target path is writable by the server process.

### ERR-CORE-029
- `Key`: `CAD_API_REQUEST_FAILED`
- `Meaning`: A request to the SonoranCAD API failed.
- `Potential Fix`: Check the related support ref, then verify API key, community ID, payload validity, network connectivity, and CAD API availability.

### ERR-CORE-030
- `Key`: `TABLET_RESOURCE_NOT_STARTED`
- `Meaning`: The `tablet` resource is installed but not running.
- `Potential Fix`: Use `exec sonorancad.cfg` and make sure `sonorancad.cfg` contains `ensure tablet` before `ensure sonorancad`.

### ERR-CORE-031
- `Key`: `TABLET_RESOURCE_MISSING`
- `Meaning`: The `tablet` resource could not be found.
- `Potential Fix`: Use the bundled `sonorancad.cfg`, confirm it contains `ensure tablet`, and install the resource with the exact name `tablet`.

### ERR-CORE-032
- `Key`: `TABLET_RESOURCE_BAD_STATE`
- `Meaning`: The `tablet` resource exists but is not in a usable runtime state.
- `Potential Fix`: Use `exec sonorancad.cfg`, confirm it contains `ensure tablet`, and fix the startup errors reported by `tablet`.

### ERR-CORE-033
- `Key`: `LOCAL_NETWORK_TIMEOUT`
- `Meaning`: The local server network timed out while connecting to SonoranCAD.
- `Potential Fix`: If you are seeing this routinely, contact your server host. The network may be overwhelmed or experiencing degraded performance. This suggests your FiveM server is getting timeouts and connection drops.

### ERR-CORE-034
- `Key`: `LOCAL_NETWORK_CONNECT_TIMEOUT`
- `Meaning`: The local server connection to SonoranCAD timed out.
- `Potential Fix`: If you are seeing this routinely, contact your server host. Check the server host, firewall, proxy, or upstream network connection for connection setup delays or blocked outbound traffic.

### ERR-CORE-035
- `Key`: `CAD_RECORD_UNIQUE_CONFLICT`
- `Meaning`: A CAD record create or edit request failed because one of the fields marked unique already has the same value on another record.
- `Potential Fix`: Find the unique field value in the record payload, choose a value that is not already used, or update the existing CAD record instead of creating a duplicate.

### ERR-CORE-900
- `Key`: `UNHANDLED_SERVER_ERROR`
- `Meaning`: An unexpected server-side error occurred and was normalized into a generic coded failure.
- `Potential Fix`: Use the support ref in the logs to find the exact exception details and fix the underlying code path or bad input.

### ERR-CORE-901
- `Key`: `UNHANDLED_WARNING`
- `Meaning`: A warning occurred that did not map to a more specific registered error code.
- `Potential Fix`: Review the warning text and support ref in logs; usually this indicates degraded behavior rather than a full failure.

### ERR-CORE-902
- `Key`: `INVALID_COMMAND_ARGUMENT`
- `Meaning`: A command was called with missing or invalid arguments.
- `Potential Fix`: Re-run the command with the documented arguments, or update the calling script/UI if it is sending malformed parameters.

### ERR-CORE-903
- `Key`: `FEATURE_UNAVAILABLE`
- `Meaning`: The requested feature cannot be completed in the current state.
- `Potential Fix`: Confirm required caches, resources, and dependent subsystems are available, then retry.

### ERR-CORE-904
- `Key`: `MALFORMED_PAYLOAD`
- `Meaning`: SonoranCAD received incomplete or invalid structured data.
- `Potential Fix`: Validate the event payload, HTTP body, or NUI/client request that triggered the error.

### ERR-CORE-905
- `Key`: `PERMISSION_DENIED`
- `Meaning`: The user or command source does not have permission for the requested action.
- `Potential Fix`: Grant the necessary ACE permission or disable the permission gate for that feature if appropriate.

### ERR-CORE-906
- `Key`: `CLIENT_RUNTIME_ERROR`
- `Meaning`: A client-side runtime or NUI/browser-side error was caught and sanitized before it could dump raw error details to the player console.
- `Potential Fix`: Check the matching support ref in the server/client logs, then verify the affected UI/runtime dependency is loaded and the triggering state is valid.

## CAD Errors

### ERR-CAD-101
- `Key`: `PLAYER_NOT_LINKED`
- `Meaning`: The player does not have a linked CAD account.
- `Potential Fix`: Run the configured link command, complete the link flow, and verify the link exists in CAD.

### ERR-CAD-102
- `Key`: `PLAYER_NOT_ONLINE`
- `Meaning`: The player is linked but not currently logged into a CAD unit/profile.
- `Potential Fix`: Log into an eligible CAD profile before using the feature.

### ERR-CAD-103
- `Key`: `PLAYER_NOT_IN_CAD`
- `Meaning`: The player must be both linked and active in CAD before the feature can be used.
- `Potential Fix`: Link the account first, then log into a valid CAD character/unit.

## Support Errors

### ERR-SUP-101
- `Key`: `SUPPORT_INVALID_ID`
- `Meaning`: The provided support upload/request ID was invalid.
- `Potential Fix`: Use the correct numeric support request ID from Sonoran support.

### ERR-SUP-102
- `Key`: `SUPPORT_UPLOAD_FAILED`
- `Meaning`: Support logs could not be uploaded.
- `Potential Fix`: Retry the upload, then verify outbound API access and the validity of the support request ID.

### ERR-SUP-103
- `Key`: `SUPPORT_UPLOAD_SUCCESS`
- `Meaning`: Support logs were uploaded successfully.
- `Potential Fix`: No action required; provide the generated support reference and upload context to support if requested.

## Smart Signs Errors

### ERR-SS-101
- `Key`: `SMARTSIGNS_PLAN_REQUIRED`
- `Meaning`: Smart Signs authentication failed because the CAD community does not have access to the required Smart Signs feature or plan.
- `Potential Fix`: Verify the CAD community has the required Smart Signs access or subscription, then retry Smart Signs authentication.

### ERR-SS-102
- `Key`: `SMARTSIGNS_AUTH_FAILED`
- `Meaning`: Smart Signs authentication failed because SonoranCAD could not authorize the configured community/server.
- `Potential Fix`: Check the SonoranCAD API key, community ID, and server ID configured for the Smart Signs resource.

### ERR-SS-103
- `Key`: `SMARTSIGNS_HELPER_STARTED`
- `Meaning`: The `smartsigns_sonoran_helper` resource was started directly, but it is only intended for Smart Signs internal update handling.
- `Potential Fix`: Remove `ensure smartsigns_sonoran_helper` or `start smartsigns_sonoran_helper` from the server startup config and start only the main Smart Signs resource.

## Bodycam Errors

### ERR-BC-101
- `Key`: `BODYCAM_FORCEOFF_PERMISSION`
- `Meaning`: The user attempted to use the bodycam force-off command without permission.
- `Potential Fix`: Grant the configured bodycam force-off ACE permission to the appropriate staff group.

### ERR-BC-102
- `Key`: `BODYCAM_CHILD_PERMISSION`
- `Meaning`: Bodycam recording could not start because child-process permission was missing.
- `Potential Fix`: Add the required child-process permission or use the bundled `sonorancad.cfg` permissions.

### ERR-BC-104
- `Key`: `BODYCAM_F8_PERMISSION`
- `Meaning`: The bodycam keybind commands are blocked by ACE permissions.
- `Potential Fix`: Allow `command.SonoranCAD::bodycam::Keybind` and `command.SonoranCAD::bodycam::RecordingKeybind` for the intended player group.

### ERR-BC-105
- `Key`: `BODYCAM_NOT_ON_DUTY`
- `Meaning`: The player must be online in CAD before toggling bodycam.
- `Potential Fix`: Log into CAD duty first, then toggle bodycam again.

### ERR-BC-106
- `Key`: `BODYCAM_UPLOAD_TOKEN_INVALID`
- `Meaning`: The bodycam upload token was rejected or expired.
- `Potential Fix`: Refresh the upload configuration from the server, verify the API auth context, and retry the upload.

### ERR-BC-107
- `Key`: `BODYCAM_UPLOAD_INIT_FAILED`
- `Meaning`: Bodycam upload setup failed before file chunks could be accepted.
- `Potential Fix`: Check temp file creation, upload parameters, and server write permissions.

### ERR-BC-108
- `Key`: `BODYCAM_UPLOAD_CHUNK_FAILED`
- `Meaning`: A bodycam upload chunk could not be appended to the target file.
- `Potential Fix`: Check disk permissions, disk space, and whether the temporary recording path is writable.

### ERR-BC-109
- `Key`: `BODYCAM_UPLOAD_INCOMPLETE`
- `Meaning`: The upload completed request arrived before all expected chunks were received.
- `Potential Fix`: Retry the upload and inspect client/network interruptions that may have dropped chunks.

### ERR-BC-110
- `Key`: `BODYCAM_TURN_FAILED`
- `Meaning`: TURN credentials for bodycam streaming could not be retrieved.
- `Potential Fix`: Verify the CAD API is reachable, the API key is valid, and TURN-related config overrides are correct.

### ERR-BC-111
- `Key`: `BODYCAM_RECORDINGS_UNWRITABLE`
- `Meaning`: The bodycam recordings directory could not be written by the server process, so upload setup or clip finalization could not save the recording file.
- `Potential Fix`: Set `sonorancad/submodules/bodycam` and its `recordings` directory to permission mode `777`, then retry the upload.

### ERR-BC-112
- `Key`: `BODYCAM_RECORDING_ACTIVE`
- `Meaning`: A start-recording request was ignored because a recording was already in progress.
- `Potential Fix`: Stop the active recording before starting another one, or debounce duplicate start requests in the caller/UI.

### ERR-BC-113
- `Key`: `BODYCAM_RECORDING_BLOCKED`
- `Meaning`: Bodycam recording was blocked by privacy override or invalid runtime state.
- `Potential Fix`: Remove the privacy override or restore the bodycam/stream state required for recording.

### ERR-BC-114
- `Key`: `BODYCAM_RECORDING_INACTIVE`
- `Meaning`: A stop or cancel request was made when there was no active recording to stop. If a pending start was cancelled, the error includes initialization, display, stream readiness, and last stream-reason details.
- `Potential Fix`: Review the included state details to identify why the pending start was not ready, or suppress duplicate stop/cancel requests in the caller/UI.

### ERR-BC-115
- `Key`: `BODYCAM_RECORDING_FAILED`
- `Meaning`: The bodycam recording pipeline failed before the clip could be finalized successfully.
- `Potential Fix`: Review the support ref, then verify the bodycam stream, recorder pipeline, duration/size limits, and upload handoff path.

### ERR-BC-116
- `Key`: `BODYCAM_NOT_WORN`
- `Meaning`: The player attempted to enable bodycam without matching the configured clothing/bodycam requirements.
- `Potential Fix`: Equip the required bodycam clothing/components or relax the configured clothing validation.

### ERR-BC-117
- `Key`: `BODYCAM_WATCH_ACTIVE`
- `Meaning`: Bodycam disable was blocked because the bodycam is currently being watched.
- `Potential Fix`: Stop the remote watch session first, or use an authorized force-off flow if policy allows it.

### ERR-BC-118
- `Key`: `BODYCAM_SOUND_LEVEL_INVALID`
- `Meaning`: The requested bodycam sound level was not a valid number within the accepted range.
- `Potential Fix`: Pass a numeric value greater than `0` and less than or equal to `1`.

### ERR-BC-119
- `Key`: `BODYCAM_UPLOAD_FAILED`
- `Meaning`: The finalized bodycam clip failed to upload to CAD.
- `Potential Fix`: Check API connectivity, auth, upload endpoint availability, and the support ref for the upload failure context.

### ERR-BC-120
- `Key`: `BODYCAM_RECORDING_START_TIMEOUT`
- `Meaning`: A recording start request timed out while waiting for bodycam initialization, display activation, or the client media stream to become ready.
- `Potential Fix`: Review the state details printed with the error and the matching `[bodycam-recording]` server warning. Verify bodycam initialization, CAD duty state, TURN connectivity, and the reported NUI stream reason.

## CAD Display Errors

### ERR-CD-101
- `Key`: `CADDISPLAY_F8_PERMISSION`
- `Meaning`: CAD display keybind commands are blocked by ACE permissions.
- `Potential Fix`: Grant the listed CAD display command permissions to players who should be able to use them.

## Call Errors

### ERR-CALL-101
- `Key`: `CALL_MISSING_DETAILS`
- `Meaning`: A call-related command was used without the required details.
- `Potential Fix`: Re-run the command with the required message, description, or argument payload.

### ERR-CALL-102
- `Key`: `CALL_SEND_FAILED`
- `Meaning`: A call could not be sent to CAD.
- `Potential Fix`: Check the support ref, then verify CAD API availability, call payload validity, and that API sending is enabled.

### ERR-CALL-103
- `Key`: `CALL_TEMPLATE_INVALID`
- `Meaning`: The configured call template file is missing or invalid.
- `Potential Fix`: Verify the template file exists, is valid JSON, and matches the configured filename/path.

### ERR-CALL-104
- `Key`: `PANIC_F8_PERMISSION`
- `Meaning`: The panic keybind command is blocked by ACE permissions.
- `Potential Fix`: Allow `command.panic` for the intended players in ACE permissions.

## Vehicle Registration Errors

### ERR-VR-101
- `Key`: `VEHREG_NO_CHARACTER`
- `Meaning`: No active CAD character was found for the vehicle registration action.
- `Potential Fix`: Log into a CAD character first, then retry the registration action.

### ERR-VR-102
- `Key`: `VEHREG_CREATE_FAILED`
- `Meaning`: The vehicle registration record could not be created in CAD.
- `Potential Fix`: Check record template/config values, payload data, and CAD API availability.

### ERR-VR-103
- `Key`: `VEHREG_PLATE_TAKEN`
- `Meaning`: The requested plate is already registered in CAD.
- `Potential Fix`: Choose a different plate or locate and update the existing CAD registration record.

## Unit Status Errors

### ERR-US-101
- `Key`: `UNITSTATUS_INVALID_STATUS`
- `Meaning`: The requested unit status does not exist in configuration or is outside the supported range.
- `Potential Fix`: Use a configured status name/number and verify `unitstatus` status mappings in its config file.

## API WebSocket Errors

### ERR-WS-101
- `Key`: `APIWS_DEPENDENCY_MISSING`
- `Meaning`: The SignalR dependency required for API WebSocket connectivity is missing.
- `Potential Fix`: Install the missing package in the `sonorancad` resource, typically `@microsoft/signalr`, and restart the resource.

### ERR-WS-102
- `Key`: `APIWS_AUTH_FAILED`
- `Meaning`: The API WebSocket hub rejected authentication.
- `Potential Fix`: Verify `communityID`, `apiKey`, and `serverId`, then confirm the key is valid for the target community.

### ERR-WS-103
- `Key`: `APIWS_CONFIG_MISSING`
- `Meaning`: The API WebSocket connection could not start because required config values were missing.
- `Potential Fix`: Ensure `communityID`, `apiKey`, and `serverId` are all present and loaded before WebSocket startup.

### ERR-WS-104
- `Key`: `APIWS_CONNECTION_FAILED`
- `Meaning`: The API WebSocket transport could not establish a connection.
- `Potential Fix`: Check outbound HTTPS/WebSocket connectivity, API URL correctness, and firewall/proxy rules.

### ERR-WS-105
- `Key`: `APIWS_RECONNECT_FAILED`
- `Meaning`: Reconnect attempts to the API WebSocket hub are repeatedly failing.
- `Potential Fix`: Treat this like a persistent connectivity or auth problem; review the first connection failure and fix that root cause.

### ERR-WS-106
- `Key`: `APIWS_PUSH_EVENT_FAILED`
- `Meaning`: A push event delivered over the WebSocket connection could not be decoded or processed.
- `Potential Fix`: Validate the incoming event payload shape and inspect the support ref for the handler that failed.

### ERR-WS-107
- `Key`: `APIWS_SEND_FAILED`
- `Meaning`: A message could not be sent over the API WebSocket connection.
- `Potential Fix`: Confirm the WS connection is active and authenticated before sending unit/call updates.

## Plugin Loader Errors

### ERR-PLUG-101
- `Key`: `PLUGIN_VERSION_FILE_LOAD_FAILED`
- `Meaning`: The local plugin version file could not be loaded from disk.
- `Potential Fix`: Confirm `sonorancad/version.json` exists and is readable.

### ERR-PLUG-102
- `Key`: `PLUGIN_VERSION_FILE_PARSE_FAILED`
- `Meaning`: The local plugin version file exists but could not be parsed.
- `Potential Fix`: Repair malformed JSON in `version.json` or replace it from a clean release.

### ERR-PLUG-103
- `Key`: `PLUGIN_UPDATER_RESPONSE_INVALID`
- `Meaning`: The remote updater responded with invalid or unusable data.
- `Potential Fix`: Retry later and verify outbound network access to GitHub/raw content endpoints.

### ERR-PLUG-104
- `Key`: `PLUGIN_NOT_FOUND`
- `Meaning`: A requested plugin or submodule could not be found locally.
- `Potential Fix`: Verify the plugin name, installation path, and that its config/resource files exist.

### ERR-PLUG-105
- `Key`: `PLUGIN_MANIFEST_ENTRY_MISSING`
- `Meaning`: A local submodule was not present in the remote updater manifest.
- `Potential Fix`: If it is a custom submodule, this may be expected; otherwise update to an official supported submodule build.

### ERR-PLUG-106
- `Key`: `PLUGIN_MANIFEST_VERSION_MISSING`
- `Meaning`: A remote updater manifest entry was missing a version field.
- `Potential Fix`: Replace the manifest source with a valid upstream release or retry after the remote manifest is corrected.

### ERR-PLUG-107
- `Key`: `PLUGIN_CONFIG_VERSION_MISSING`
- `Meaning`: A plugin config did not declare its current config version.
- `Potential Fix`: Update the plugin config from the latest `*_config.dist.lua` and ensure the version field is present.

### ERR-PLUG-108
- `Key`: `PLUGIN_CONFIG_BACKUP_FAILED`
- `Meaning`: The plugin updater could not create a config backup before modifying files.
- `Potential Fix`: Check write permissions for the SonoranCAD configuration directory and available disk space.

### ERR-PLUG-109
- `Key`: `PLUGIN_CONFIG_PARSE_FAILED`
- `Meaning`: A plugin or submodule configuration file could not be parsed, compiled, or executed safely.
- `Potential Fix`: Repair the matching `*_config.lua` file so it defines a valid `local config = {}` table and contains no Lua syntax/runtime errors.

## Civilian Integration Errors

### ERR-CIV-101
- `Key`: `CIV_NO_CHARACTERS_FOUND`
- `Meaning`: No CAD character records were found for the player.
- `Potential Fix`: Ensure the player is linked and has at least one valid CAD character, or enable custom IDs if you want a fallback.

### ERR-CIV-102
- `Key`: `CIV_CUSTOM_IDS_DISABLED`
- `Meaning`: The server has disabled custom civilian IDs.
- `Potential Fix`: Enable `allowCustomIds` in the civ integration config if that workflow should be allowed.

### ERR-CIV-103
- `Key`: `CIV_REFRESH_DISABLED`
- `Meaning`: Manual character cache refresh is disabled.
- `Potential Fix`: Enable the purge/refresh option in config if players should be allowed to force-refresh ID data.

### ERR-CIV-104
- `Key`: `CIV_UNKNOWN_SUBCOMMAND`
- `Meaning`: An invalid civilian ID command subcommand was used.
- `Potential Fix`: Use `/id help` and re-run the command with a supported subcommand.

### ERR-CIV-105
- `Key`: `CIV_NO_NEARBY_PLAYERS`
- `Meaning`: The player attempted to show an ID but no nearby viewers were found.
- `Potential Fix`: Move closer to another player and retry the `show` action.

## Additional Call/Dispatch Errors

### ERR-CALL-105
- `Key`: `CALL_CREATE_FAILED`
- `Meaning`: A dispatch call create operation failed before returning a valid call ID.
- `Potential Fix`: Inspect the payload fields sent to CAD and verify API availability and permissions.

### ERR-CALL-106
- `Key`: `CALL_UNEXPECTED_RESPONSE`
- `Meaning`: CAD returned a success path without the expected data, such as a missing call ID.
- `Potential Fix`: Review the API response body and confirm the integration and API versions are compatible.

### ERR-DISP-101
- `Key`: `DISPATCH_CALL_NOT_FOUND`
- `Meaning`: A dispatch action referenced a call that was not present in cache.
- `Potential Fix`: Verify the call ID is current and that call cache synchronization is working before retrying the action.

## ERS Integration Errors

### ERR-ERS-101
- `Key`: `ERS_MAPPING_FAILED`
- `Meaning`: ERS field mapping logic failed while converting ERS data into CAD payload fields.
- `Potential Fix`: Review custom mapping functions and field names in the ERS integration config for nil values or bad return types.

### ERR-ERS-102
- `Key`: `ERS_PAYLOAD_MALFORMED`
- `Meaning`: An ERS event payload was missing required top-level fields or had an invalid structure.
- `Potential Fix`: Validate the ERS event payload contract and adjust any custom hooks that modify it.

### ERR-ERS-103
- `Key`: `ERS_COORDS_MISSING`
- `Meaning`: An ERS event did not provide usable coordinates for the CAD action.
- `Potential Fix`: Ensure the originating ERS event includes proper coordinates and that any transform step preserves them.

### ERR-ERS-104
- `Key`: `ERS_CALL_ID_INVALID`
- `Meaning`: ERS attempted to update or attach to a call using an invalid stored call ID.
- `Potential Fix`: Check the local saved-call cache and ensure the create-call step succeeded before later actions reference it.

### ERR-ERS-105
- `Key`: `ERS_RESOURCE_NOT_STARTED`
- `Meaning`: The Night ERS resource required by the integration is not started.
- `Potential Fix`: Start the ERS resource before enabling the ERS integration submodule.

## Framework Errors

### ERR-FW-101
- `Key`: `FRAMEWORK_RESOURCE_MISSING`
- `Meaning`: A required framework resource like `qb-core` or `es_extended` is not running.
- `Potential Fix`: Start the configured framework resource and verify the integration is targeting the correct framework.

### ERR-FW-102
- `Key`: `FRAMEWORK_IDENTITY_MISSING`
- `Meaning`: Framework identity or player data could not be retrieved.
- `Potential Fix`: Check that the player is fully loaded into the framework and that the expected identity export/event is available.

### ERR-FW-103
- `Key`: `FRAMEWORK_QUERY_INVALID`
- `Meaning`: A framework SQL query or parameter set was invalid and was rejected before execution.
- `Potential Fix`: Ensure the query is a non-empty string and the parameters are passed as a key/value table rather than an array.

## Locations/Livemap Errors

### ERR-LOC-101
- `Key`: `LOCATIONS_CONFIG_MISSING`
- `Meaning`: The locations/livemap vehicle model config file could not be found.
- `Potential Fix`: Restore the missing config file or update the configured path to a valid file.

### ERR-LOC-102
- `Key`: `LOCATIONS_CONFIG_INVALID`
- `Meaning`: The locations/livemap config file exists but could not be decoded.
- `Potential Fix`: Repair malformed JSON in the vehicle model configuration file.

### ERR-LOC-103
- `Key`: `LOCATIONS_CLIENT_ERROR`
- `Meaning`: A client reported an error while sending location data.
- `Potential Fix`: Check client logs for the specific failure and verify required dependencies like postals and location hooks are configured.

### ERR-LOC-104
- `Key`: `POSTALS_RESOURCE_UNAVAILABLE`
- `Meaning`: A client-side feature requested postal data, but the configured postal source was unavailable.
- `Potential Fix`: Start the configured postal resource or switch to a valid postal mode/source in config.

### ERR-LOC-105
- `Key`: `POSTALS_FILE_INVALID`
- `Meaning`: The configured client-side postal file was missing or invalid.
- `Potential Fix`: Restore the referenced postal file, validate its JSON, and confirm the configured filename is correct.

### ERR-LOC-106
- `Key`: `POSTALS_LOOKUP_FAILED`
- `Meaning`: Client-side postal lookup failed at runtime, but SonoranCAD continued sending location updates without a postal prefix.
- `Potential Fix`: Check the configured postal resource or custom postal file for runtime errors, malformed data, or missing exports.

## Record Printer Errors

### ERR-RP-101
- `Key`: `RECORDPRINTER_UNIT_MISSING`
- `Meaning`: Record printer could not resolve the player to an active CAD unit.
- `Potential Fix`: Ensure the player is logged into CAD and present in the unit cache before printing.

### ERR-RP-102
- `Key`: `RECORDPRINTER_DIRECTORY_FAILED`
- `Meaning`: Record printer could not create or resolve its output directory.
- `Potential Fix`: Check write permissions and folder creation behavior for the record printer output path.

### ERR-RP-103
- `Key`: `RECORDPRINTER_SAVE_FAILED`
- `Meaning`: Record printer failed to save the generated PDF.
- `Potential Fix`: Verify write permissions, disk space, and that the generated PDF data is valid.

### ERR-RP-104
- `Key`: `RECORDPRINTER_SHARE_INVALID`
- `Meaning`: Record printer rejected a share request because the URL or target list was invalid.
- `Potential Fix`: Validate the shared URL and ensure at least one valid target player or identifier is supplied.

## Sonrad Errors

### ERR-SR-101
- `Key`: `SONRAD_CALLCOMMANDS_MISSING`
- `Meaning`: Sonrad attempted an action that depends on the `callcommands` submodule.
- `Potential Fix`: Enable/start the `callcommands` submodule before using Sonrad panic/call features.

### ERR-SR-102
- `Key`: `SONRAD_CONFIG_MISSING`
- `Meaning`: Critical Sonrad configuration values are missing.
- `Potential Fix`: Update `sonrad_config.lua` from the latest template and fill in the missing required values.

## Additional CAD Display Errors

### ERR-CD-102
- `Key`: `CADDISPLAY_FRAMEWORK_UNAVAILABLE`
- `Meaning`: CAD display could not access the configured framework export.
- `Potential Fix`: Confirm the selected framework resource is started and that its export name matches the integration config.

### ERR-CD-103
- `Key`: `CADDISPLAY_PLACEMENT_INVALID`
- `Meaning`: CAD display placement data could not be loaded or parsed.
- `Potential Fix`: Repair the placement file JSON/Lua data or delete bad saved placement data so defaults can be rebuilt.

### ERR-CD-104
- `Key`: `CADDISPLAY_VEHICLE_UNIDENTIFIED`
- `Meaning`: CAD display could not determine what vehicle the player was targeting.
- `Potential Fix`: Retry while targeting a valid supported vehicle and verify the display interaction logic has correct entity context.

## Kick Module Errors

### ERR-KICK-101
- `Key`: `KICK_QUEUE_UNAVAILABLE`
- `Meaning`: The kick module could not queue a CAD logout/kick for the player.
- `Potential Fix`: Ensure the player is linked and currently represented by an active unit before the kick action runs.

## Warning Codes

### WRN-CORE-001
- `Key`: `INVALID_API_MODE`
- `Meaning`: The configured SonoranCAD API mode was invalid, so the resource fell back to production mode.
- `Potential Fix`: Set `mode` to a supported value such as `production` or `development`.

### WRN-CORE-002
- `Key`: `DEPRECATED_DEBUGPRINT`
- `Meaning`: Deprecated logging helper `debugPrint` was used somewhere in the runtime path.
- `Potential Fix`: Replace `debugPrint(...)` calls with `debugLog(...)` in custom integrations or older submodule code.

### WRN-CORE-003
- `Key`: `JSON_DECODE_FAILED`
- `Meaning`: SonoranCAD failed to decode a JSON string and continued with a default or empty value.
- `Potential Fix`: Validate the JSON source that triggered the warning and correct malformed payload or file contents.

### WRN-CORE-004
- `Key`: `JSON_ENCODE_FAILED`
- `Meaning`: SonoranCAD failed to encode a Lua value into JSON and continued with a fallback value.
- `Potential Fix`: Check the table being encoded for unsupported values such as functions, userdata, or recursive structures.

### WRN-CORE-005
- `Key`: `APIKEY_CONVAR_UNINITIALIZED`
- `Meaning`: SonoranCAD started before the bundled convar setup from `sonorancad.cfg` initialized the API key path.
- `Potential Fix`: Use `exec sonorancad.cfg` and make sure it runs before `ensure sonorancad`.

### WRN-CORE-006
- `Key`: `OLD_FXSERVER_VERSION`
- `Meaning`: The running FXServer build is older than the version this SonoranCAD release was tested against.
- `Potential Fix`: Update FXServer to the tested version or newer before troubleshooting feature regressions.

### WRN-CAD-101
- `Key`: `PLAYER_IDENTIFIER_MISSING`
- `Meaning`: A player connected without the configured primary identifier, so some CAD features may not work for that player.
- `Potential Fix`: Ensure the configured identifier type is actually available on your server and that the player is connecting through the expected identity provider.

### WRN-CAD-102
- `Key`: `PLAYER_LINK_REQUIRED`
- `Meaning`: A player attempted a CAD-linked workflow without having a linked CAD account.
- `Potential Fix`: Have the player run the configured link command, complete the link flow, and retry after the CAD link exists.

### WRN-WS-101
- `Key`: `LEGACY_HTTP_PUSH_EVENT`
- `Meaning`: SonoranCAD received a legacy HTTP push event on `/event` while WebSocket push delivery is preferred.
- `Potential Fix`: Review your CAD/server push-event configuration and move the server onto the API WebSocket push path where available.

### WRN-CORE-900
- `Key`: `UNHANDLED_WARNING`
- `Meaning`: A warning was logged without a more specific registered warning code, so it was normalized into the generic warning bucket.
- `Potential Fix`: Use the support ref and warning text in logs to identify the exact caller, then register a dedicated warning code if the condition needs clearer support guidance.
