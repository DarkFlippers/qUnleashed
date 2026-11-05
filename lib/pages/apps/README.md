# Apps

## Server selection and clients

Settings → Apps chooses Official, one of `CatalogServer.community`, or a custom
HTTP(S) domain. A bare domain uses HTTPS. The setting stores an origin, without
an API path, credentials, query or fragment. New installations use qUnleashed.
Add further known domains to `data/catalog_server.dart`; a custom domain is
remembered separately as the selected origin. Every community/custom origin
must implement v1; Official uses v0. There is no endpoint probing.

`data/catalog_api.dart` keeps the stable API reference the backend uses. Each
request captures its origin and firmware filters. The protocol implementations
live in `data/api/catalog_v0_api.dart` and `catalog_v1_api.dart`. The v0 client
retains Archivarius paths and bodies, including `POST /1/application` with
`applications`; v1 uses `POST /application/lookup` with `ids`.

Both protocols use the same catalog page and detail page. Official (v0) has
the apps only, so the page shows no section tabs there and no popularity
sorts; categories have no folders on v0, so none appear. Everything v0 lacks
is absent because its data is, not drawn differently. The v1 catalog adds menu
styles, CLI plugins, animation previews, author cards, search and download
counts.
Catalog and Manager remain the two top-level views; ATP is served by the server
rather than downloaded and unpacked by the client.

## Contract with the current server

The server checkout is `.system/server` at the repository root. Its current
working source is the reference, including its uncommitted changes. Relevant
files are `app/api/routers/v1/catalog.py`, `search.py`, `authors.py`, `plan.py`,
`app/api/schemas/catalog.py` and `app/api/views/v1/card.py`.

| Request | Response / use |
|---|---|
| `GET /api/v1/status` | `sdk[] {version, target, api, channel}` |
| `GET /api/v1/{root}/category` | Categories with `parent_id`, icon, color, counts |
| `GET /api/v1/{root}` | Cards; filters: `target`, `api`, `category_id`, `query`, `author_id`, sorting and pagination |
| `POST /api/v1/application/lookup` | `{ids: [...], target, api}` → installed items with their apps |
| `GET /api/v1/{root}/{idOrAlias}?app=...` | Detail, with the selected external app in front |
| `GET /api/v1/search?query=...` | `{items, totals, authors}` across families |
| `GET /api/v1/authors` and `/authors/{id}` | Author summaries and family counts |
| `GET /api/v1/{root}/version/{vid}/build/compatible` | Signed `.fap` or `.fal` |
| `GET /api/v1/animations/version/{vid}/plan` | Files and dolphin manifest entry to install |
| `GET /api/v1/animations/version/{vid}/file/{name}` | Signed preview / installation file |
| `GET /api/v1/{root}/version/{vid}/bundle` | Signed source ZIP |

`{root}` is `application`, `menustyles` or `animations`. Animations omit firmware
filters. Public downloads serve existing builds; they do not enqueue builds.

Cards keep v0 fields and add `family`, `install_path`, `authors`, `stats` and
`app_count`. Detail and lookup additionally carry `app` and `apps[]`; list cards
carry only the count. Each app has `id`, `appid`, `version_id`, `install_path`,
`bundle_uri`, `status` and optional `build {api, size}`. Its texts and screenshots
come from the shared `current_version`. There is no `/meta` endpoint and no
`variants` response field. An app picker changes the selected file and version,
while preserving these shared texts. Update checks follow the installed app,
including secondary apps of the same item.

Signed downloads verify Ed25519 over SHA-256. Release builds supply the trusted
public keys through `--dart-define=QU_SIGNING_KEYS=kid:public_key_hex,...`, matching
the server's signing key. Unknown or missing signatures fail installation.

`test/fixtures/catalog/v1.json` contains responses exported from this server's
FastAPI test client with its real views and schema validation. The only rewritten
value is the temporary firmware repository path. `catalog_api_contract_test.dart`
serves these answers over local HTTP and checks decoding, request parameters,
app selection, update identity and installation plans. It also checks the v0
request paths/body and signed artifact verification.

## Catalog / firmware API compatibility

The device reports its API as `major.minor`. The firmware FAP loader enforces
the major version only, so the working mode is resolved against the catalog SDK
list (`GET /api/v0/sdk` on Official, `/api/v1/status.sdk` on our servers,
filtered by hardware target) and picked automatically — the
user is never asked. `CatalogMode` is the result:

| Situation | Example (device / catalog) | Mode |
|---|---|---|
| Exact API present in catalog | 87.1 / 87.1 | `normal` |
| Same major, catalog has minor ≤ device | 87.6 / 87.1 | `normal`, silently uses 87.1 |
| Same major, catalog only has a newer minor | 88.19 / 88.23 | `normal`, uses 88.23 |
| Catalog behind the firmware, Flibler available | 88.0 / max 87.1 | `sourceBuild`: apps are compiled from source |
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
kept for local checks (installed apps and updates compare the major only, as
the firmware loader does).

## Flibler build server status codes

The remote builder (`lib/services/assembler/remote_build_service.dart`)
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
