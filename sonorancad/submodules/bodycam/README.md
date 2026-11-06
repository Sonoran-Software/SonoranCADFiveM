# Bodycam overlay artwork

The bodycam HUD uses a generic camera housing, a separate logo, and a blinking red
status light. The light keeps its one-second cycle: on for 80%, off for 20%.
The camera and battery symbols are decorative; they do not report battery charge
or whether a saved recording is in progress.

## Choose a logo

The images are in `sonorancad/core/client_nui/img/`:

| File | Appearance |
| --- | --- |
| `bodycam_logo_gold.png` | Muted gold outside, CAD red arrow inside (default) |
| `bodycam_logo_standard.png` | Standard CAD red and white |
| `bodycam_logo.png` | Optional active override supplied by the server owner |

To use red and white, **copy** `bodycam_logo_standard.png` to `bodycam_logo.png` in that same
directory, then restart the `sonorancad` resource. Use the same process for a
custom logo. Keep the bundled variants under their original names.

To return to the default, remove your optional `bodycam_logo.png` and restart the
resource. A missing or invalid override automatically falls back to the default
gold logo. No Lua configuration changes are required.

Custom logos should be tightly cropped transparent PNGs, preferably square and
at least 282 × 282 pixels. Both bundled variants use the same vector geometry and
transparent bounds, so swapping them does not move or resize the mark. Other
aspect ratios fit inside the same badge area without stretching.

## Automatic updates

Existing installations receive the new housing and default logo automatically;
existing bodycam configuration files continue to work without new settings.

`bodycam_logo.png` is deliberately **not distributed** in releases. The updater
replaces files present in the release ZIP and leaves this optional file alone,
preserving your selection across updates. The reserved filename is also ignored
by Git. Do not add it to release archives or commit it to the repository.

The housing, logo, and light share a single 1536 × 1024 coordinate system in
`core/client_nui/bodycam_screen.html`. This keeps them aligned at every HUD size
and screen corner. The old separate `light_off.png` layer is no longer used.

## Save clips to Copium

Recorded clips normally go to the CAD, which keeps them for 24 hours. With
[Copium](https://copium.pics), clips are saved to your Copium team's storage
instead and their links are registered with the CAD, so they stay attached to
records and don't use the CAD's daily recording allowance.

1. Install and start the `copium` resource (copium.pics → Apps → FiveM).
2. In Copium, make a team key (Teams → your server → Integrations) and paste it
   into the copium resource's `config.lua` as `Config.Token`.
3. In `configuration/bodycam_config.lua`, set `recording.copium.enabled = true`
   and restart.

By default each clip is also locked in the team's evidence locker (when the team
has it turned on); set `recording.copium.evidence = false` to skip that. Clips
are filed under `bodycam/<unit number>` in the team's storage. Their links stay
public, because CAD viewers don't have Copium accounts.

If the copium resource isn't running, or saving or registering a clip fails,
the clip is uploaded to the CAD as usual and the server console says why. The
clip limits (120 seconds, 6 MB) are the same either way. Older
`bodycam_config.lua` files without a `copium` section keep uploading to the CAD.

## Artwork sources

Both logo variants are rendered from the exact icon paths in the official
[Sonoran CAD vector artwork](https://sonoransoftware.com/assets/images/logos/CAD_VECTOR.eps)
on the [branding page](https://sonoransoftware.com/branding).
The gold variant uses `#C89B3C` outside and CAD red `#ED1C24` inside.
Editable SVG sources and the housing generation prompts are retained under
`.codex/artwork/bodycam/` in the development repository.
