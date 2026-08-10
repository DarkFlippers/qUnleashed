# Apps

## Catalog / firmware API compatibility

The device reports its API as `major.minor`. The firmware FAP loader enforces
the major version only, so the working mode is resolved against the catalog SDK
list (`GET /sdk`, filtered by hardware target) and picked automatically — the
user is never asked. `CatalogMode` is the result:

| Situation | Example (device / catalog) | Mode |
|---|---|---|
| Exact API present in catalog | 87.1 / 87.1 | `normal` |
| Same major, catalog has minor ≤ device | 87.6 / 87.1 | `normal`, silently uses 87.1 |
| Catalog behind the firmware, Flibler available | 87.0 / 87.5, 88.0 / max 87.1 | `sourceBuild`: apps are compiled from source |
| Catalog behind the firmware, no builder | 88.0 / max 87.1 | `nearestApi`: installs builds of the closest API the catalog has |
| Device 2+ majors ahead, no builder | 89.x / max 87.1 | `managerOnly` |
| Device older than the whole catalog | 86.x / 87+ | `managerOnly` |
| Catalog failed or timed out (`kCatalogTimeout`) | — | `managerOnly` |

The builder counts as available when the backend chosen in the Flibler settings
can run: this computer on desktop, or a build server that answers its status
endpoint (cached for a few minutes, see `AssemblerController.builderAvailable`).
Settings → Apps overrides the decision (`CatalogModePreference`), the catalog
header shows the resolved mode as a badge, and `managerOnly` also disables the
catalog button in the apps manager.

The API sent to the server is always one the catalog knows; the device API is
kept for local checks (installed apps and updates compare major strictly and
require device minor ≥ app minor).

## Flibler build server status codes

The remote builder (`lib/pages/asembler/remote/remote_build_service.dart`)
maps these to user-facing errors; 404 and 409 depend on the endpoint:

| Code | When |
|---|---|
| 200 / 201 | OK / a new build was created |
| 400 | broken JSON, invalid `target`/`api`/`channel`, forbidden bundle host or index URL |
| 401 | authorization headers missing or unparsable |
| 403 | bad signature, expired timestamp, foreign User-Agent |
| 404 | dead bundle link (submit); unknown job or another client's job |
| 409 | this client already has a build in progress (submit); artifact not ready / build failed (artifact); cancelling a non-queued build |
| 410 | artifact of a finished build expired from the cache |
| 429 | build queue is full |
| 500 | unhandled server error (global handler — JSON `detail` + server log) |
| 502 / 504 | bundle host unavailable / timed out |
