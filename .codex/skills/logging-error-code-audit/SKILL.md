---
name: logging-error-code-audit
description: Audit SonoranCAD-style Lua repositories for `errorLog`/`logError` and `warnLog`/`logWarn` calls that are missing registered structured error or warning codes. Use when Codex needs to scan logging callsites, add new code keys to `sonorancad/core/logging.lua`, update the local `errors.md` registry, or compare the repo registry against an external documentation page of error codes.
---

# Logging Error Code Audit

Use the bundled scanner first. Do not hand-audit the repo unless the scanner output is obviously wrong.

## Workflow

1. Run `scripts/audit_log_codes.py <repo-root>`.
2. Review every finding grouped by file and logging function.
3. For each real issue:
   - add a stable key to `WarningCodes` or `ErrorCodes` in `sonorancad/core/logging.lua`
   - prefer the existing namespace style such as `ERR-CORE-*`, `ERR-PLUG-*`, `WRN-CORE-*`
   - reuse an existing key when multiple callsites describe the same support issue
4. Patch the Lua callsites so the first argument is the new or existing code key.
5. Update the repo-level `errors.md` so every new key has:
   - code
   - internal key
   - meaning
   - first troubleshooting step
6. If an external docs page also needs validation, compare the local `errors.md` codes against that page after the source-of-truth changes are complete.

## Conventions

- Treat `warnLog` as valid when it uses either a warning key or an error key. The runtime intentionally allows warning-level paths to surface `ERR-*` codes for real support issues.
- Treat `errorLog` and `logError` as valid only when they use a registered error key.
- A raw string message as the first argument is not a code, even if it looks descriptive.
- A variable first argument is suspect unless the code path is clearly passing a preformatted coded message.

## Script

Run:

```powershell
python .codex/skills/logging-error-code-audit/scripts/audit_log_codes.py <repo-root>
```

Useful flags:

```powershell
python .codex/skills/logging-error-code-audit/scripts/audit_log_codes.py <repo-root> --format json
python .codex/skills/logging-error-code-audit/scripts/audit_log_codes.py <repo-root> --include "submodules/**/*.lua"
python .codex/skills/logging-error-code-audit/scripts/audit_log_codes.py <repo-root> --logging-file "sonorancad/core/logging.lua"
```

## Output Interpretation

- `raw_message_literal`: first argument is a quoted message, not a registered key.
- `raw_expression`: first argument is an expression, concatenation, format call, or variable.
- `unknown_code_key`: first argument is a quoted identifier, but it is not registered in `logging.lua`.

Fix `unknown_code_key` by either registering the key or correcting the typo. Fix the other two by introducing or reusing a proper code key and moving the human message into the second argument.
