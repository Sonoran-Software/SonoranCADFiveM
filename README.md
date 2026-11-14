# SonoranCAD FiveM Integration

The Sonoran CAD FiveM integration core includes many drag-and-drop integration scripts for your gaming server.

## Installation

Please view the [installation guide](https://info.sonorancad.com/integration-plugins/in-game-integration/fivem-installation) for more details.

For a new installation, copy `sonorancad/config.example.json` to `sonorancad/config.json` and enter your API key and numeric server ID. When updating, keep your existing `config.json`; the archive includes only the example file. Existing legacy installations migrate their credentials automatically.

## Updating from v3.x.x?

See our documentation [here](https://sonoran.link/cadupdate).

## API Resources

Sonoran CAD's API offers direct access to your CAD data, making it very useful to use for integration with various scripts. Detailed API and push event information can be found [here](https://info.sonorancad.com/sonoran-cad/api-integration/api-endpoints/).

## FiveM Linking v2

The FiveM resource now uses the CAD link flow on API v2.

- Players link with `/link`.
- Third-party resources can read the CAD community ID, server ID, and linked `communityUserId` through exports documented in [sonorancad/LINKING_V2.md](sonorancad/LINKING_V2.md).
- Tablet/iframe integrations can forward SSO data through the server events documented in [sonorancad/LINKING_V2.md](sonorancad/LINKING_V2.md).

## Copium storage

Bodycam clips and printed record PDFs automatically use a running `copium`
resource. Install Copium 1.3.2 or newer from copium.pics → Apps → FiveM, configure its
`Config.Token` with a Copium team key, and start it. The CAD checks for Copium
on each upload and uses its normal storage or print link when Copium is stopped
or saving fails.

Optional settings are read from the CAD-managed plugin configuration:
`bodycam.recording.copium` and `recordPrinter.copium`.
These control the storage folder (`path`) and evidence locking (`evidence`).
Bodycam clips default to the `bodycam` folder with evidence locking enabled;
printed records default to `records` with evidence locking disabled. Set the relevant
`copium.enabled = false` to opt out. Older configs without these sections
auto-detect Copium; an existing explicit `false` must be changed to `true` to
enable it. See the [bodycam guide](sonorancad/submodules/bodycam/README.md#save-clips-to-copium)
for clip limits and public-link behavior. Printed PDFs also use public links
so players can open them without a Copium account.

## Development Bounties
Get PAID to contribute to the open source project!!!

Sonoran Software offers 💵CASH💵 for contributing to the open source integration framework plugin library. Check out more information [here](https://info.sonorancad.com/sonoran-cad/developer-bounties).

## Developing: Working with submodules
If you are developing this source code we utilize git submodules in order to bundle 3rd party resources and external CAD submodules. In order to "clone" the submodules you will need to run some additional git commands each time you pull. 

The commands below will clone the git submodules and ensure your submodules are synced to the commit hash/branch/tag you have selected in your git CLI/GUI/IDE (ie. VS Code). When cloning the repo your first time, this will sync to the commit hashes pushed to the repo. Updating the branch of the submodules in your IDE will change what code is pulled for that particular submodule.

After Cloning Repository
Run the following commands after cloning to ensure the git submodule files are cloned...

```bash
git submodule sync
git submodule update --init --recursive
git submodule update --remote --merge
```

### Resetting Git Submodule links to commited links
If you want to ensure git submodules are pulling the code specified by what has been commited to the repo, run this command before the commands listed above:
```bash
git submodule deinit -f --all
```
