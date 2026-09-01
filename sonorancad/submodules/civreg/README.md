# Character Registration

Players use `/civreg` to open the community's live CAD character template (`7`) in-game. The form follows the template's current sections, field options, required fields, read-only fields, and dependencies, then creates the character on the player's linked CAD account.

When `frameworksupport` is enabled, supported QBCore or ESX identity values are pre-filled. If the CAD template uses custom Field Mapping IDs, update `autofillFieldIds` in `configuration/civreg_config.lua`.

Image fields are clearly marked as selfie controls. A captured portrait is stored in `sonorancad/filestore/civreg` and the public image URL is saved on the CAD character record. The module derives the URL from the CAD server's public IP and listener port by default. Servers using HTTPS, a proxy, or a custom public hostname should set `selfieBaseUrl`, for example:

```lua
selfieBaseUrl = "https://play.example.com/civreg"
```
