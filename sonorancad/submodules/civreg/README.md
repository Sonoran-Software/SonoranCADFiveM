# Character Registration

Players use `/civreg` to open the community's live CAD character template (`7`) in-game. The form follows the template's current sections, field options, required fields, read-only fields, and dependencies, then creates the character on the player's linked CAD account.

When `frameworksupport` is enabled, supported QBCore or ESX identity values are pre-filled. If the CAD template uses custom Field Mapping IDs, update `autofillFieldIds` in `configuration/civreg_config.lua`.

Image fields are clearly marked as selfie controls. Captured portraits are submitted directly to CAD as base64 PNG or JPEG data (including the `data:image/...;base64,` prefix). Each portrait is validated against `maxSelfieBytes` before submission; the default decoded size limit is 1 MiB.

New portraits do not require a public image URL or a local image file. The old `selfieBaseUrl` option is ignored. Existing URL-based records keep their original references, so the `civreg` file route remains available for previously saved portraits. Preserve those files and their public route while existing records use them.

Run the standalone server regression tests from the repository root with `lua .codex/tests/civreg_registration_spec.lua` (Lua 5.4 or newer). They stub the FiveM and CAD boundaries and do not connect to a live CAD community.
