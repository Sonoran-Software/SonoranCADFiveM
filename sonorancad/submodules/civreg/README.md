# Character Registration

At startup, CivReg reads the CAD database sync configuration. When character database sync is disabled, players use `/civreg` to open the community's live CAD character template (`7`) and create a character on the linked CAD account.

When both database sync and its character mapping are enabled, CivReg switches to database mode. It adds a nullable `sonoran_mugshot MEDIUMTEXT` column to the standard QBCore `players` table or ESX `users` table on every resource start. `/civreg` refreshes the active framework character's portrait, and the CAD `EVENT_CHAR_SELECTED` push event refreshes the exact selected sync record. It does not create an API character in this mode. Configure CAD DB Sync to map `sonoran_mugshot` to the character template's image field.

When `frameworksupport` is enabled, supported QBCore or ESX identity values are pre-filled. If the CAD template uses custom Field Mapping IDs, update `autofillFieldIds` in `configuration/civreg_config.lua`.

Image fields are clearly marked as selfie controls in API mode. Captured portraits are submitted directly to CAD as base64 PNG or JPEG data (including the `data:image/...;base64,` prefix). Database mode stores the same data URL in `sonoran_mugshot`. Each portrait is validated against `maxSelfieBytes`; the default decoded size limit is 1 MiB.

New portraits do not require a public image URL or a local image file. The old `selfieBaseUrl` option is ignored. Existing URL-based records keep their original references, so the `civreg` file route remains available for previously saved portraits. Preserve those files and their public route while existing records use them.

Run the standalone server regression tests from the repository root with `lua .codex/tests/civreg_registration_spec.lua`, `lua .codex/tests/civreg_database_sync_spec.lua`, and `lua .codex/tests/linking_account_uuid_spec.lua` (Lua 5.4 or newer). They stub the FiveM, CAD, and SQL boundaries and do not connect to a live CAD community or database.
