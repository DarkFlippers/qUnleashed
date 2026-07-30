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
