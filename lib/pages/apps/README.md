# Apps

## Catalog / firmware API compatibility

The device reports its API as `major.minor`. The firmware FAP loader enforces
the major version only, so the catalog mode is resolved against the catalog SDK
list (`GET /sdk`, filtered by hardware target):

| Situation | Example (device / catalog) | Behavior |
|---|---|---|
| Exact API present in catalog | 87.1 / 87.1 | normal |
| Same major, catalog has minor ≤ device | 87.6 / 87.1 | normal, silently uses 87.1 |
| Same major, only higher minors | 87.0 / 87.5 | warning dialog, candidate 87.5 |
| Device one major ahead of catalog | 88.0 / max 87.1 | warning dialog, candidate 87.1 |
| Device 2+ majors ahead | 89.x / max 87.1 | incompatible: apps manager only, no updates, wait for the catalog |
| Device older than the whole catalog | 86.x / 87+ | incompatible: apps manager only, no updates, update the firmware |

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
