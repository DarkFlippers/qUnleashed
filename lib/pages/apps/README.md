# Apps

## Server selection and clients

Settings → Apps chooses Official, one of `CatalogServer.community`, or a custom
HTTP(S) domain. A bare domain uses HTTPS. The setting stores an origin, without
an API path, credentials, query or fragment. New installations use qUnleashed.
Add further known domains to `data/catalog_server.dart`; a custom domain is
remembered separately as the selected origin. The protocol is a setting of its
own (`CatalogProtocol`): a community/custom origin is spoken to in v1 unless
v0 is picked, and then the app treats it exactly as it treats Official, which
speaks v0 only. There is no endpoint probing. A switch of either is a different
`AppsCatalogApi.endpoint`, which is what every screen compares to drop what it
read from the last catalog.

`data/catalog_api.dart` keeps the stable API reference the backend uses. Each
request captures its origin and firmware filters. The protocol implementations
live in `data/api/catalog_v0_api.dart` and `catalog_v1_api.dart`. The v0 client
retains Archivarius paths and bodies, including `POST /1/application` with
`applications`; v1 uses `POST /{root}/lookup` with `ids`, each installed app
under its own family's root.

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
| `GET /api/v1/status` | `sdk[] {version, target, api, channel}`, `dev_catalog` |
| `GET /api/v1/{root}/category` | Categories with `parent_id`, icon, color, counts |
| `GET /api/v1/{root}` | Cards; filters: `target`, `api`, `category_id`, `query`, `author_id`, sorting and pagination |
| `POST /api/v1/{root}/lookup` | `{ids: [...], target, api}` → installed items with their apps |
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

Ids are Archivarius's shape on both protocols: an entry's `id` and every
version id are 24-hex ObjectIds, derived on the server from its own names, so
they survive a rebuilt database. The readable names stay in `alias`, `appid`
and `apps[].id` (what `app=` takes). Every built file comes with
`X-QU-Build-Api`, the API of the tree it was built in, a remote build's as
well; a server that leaves it out fails the install, as one whose status has
no `dev_catalog` does.

Signed downloads verify Ed25519 over SHA-256. Release builds supply the trusted
public keys through `--dart-define=QU_SIGNING_KEYS=kid:public_key_hex,...`, matching
the server's signing key. Unknown or missing signatures fail installation.

`test/fixtures/catalog/v1.json` contains responses exported from this server's
FastAPI test client with its real views and schema validation. The only rewritten
value is the temporary firmware repository path. `catalog_api_contract_test.dart`
serves these answers over local HTTP and checks decoding, request parameters,
app selection, update identity and installation plans. It also checks the v0
request paths/body and signed artifact verification.

## The installed-app manifest (`.fim`)

`/ext/apps_manifests/<alias>.fim` for apps and CLI commands,
`/ext/apps_data/loader/manifests/<alias>.fim` for menu styles; animations have
none. The official apps read the same files: they need `UID`, `Version UID`
and `Path`, ignore keys they do not know, and send every `UID` back to
Archivarius, which answers a batch holding one id that is not an ObjectId with
a 422 for all of it. So ours keeps their keys and their meaning, and adds its
own after them (`models/manifest.dart`):

```
Filetype: Flipper Application Installation Manifest
Version: 1
Full Name: ProtoPirate Extra
Icon: <base64>                  the catalog icon, v0 and v1 alike
Version Build API: 87.1         X-QU-Build-Api; built here, the file's .fapmeta; Official, as its app
UID: <ObjectId of the entry>
Version UID: <ObjectId of the installed app's version>
Path: /ext/apps/Sub-GHz/proto_pirate_extra.fap
DevCatalog: true                always written, false too (the official app leaves false out): `dev_catalog` from our status, false on Official
App ID: proto_pirate_extra
App Version: 3.0.2
Family: app                     app | cli | stl
Catalog: qunleashed.aperturefox.ru
```

A key without a value is left out, never written empty. Manifests are read over
BLE one by one, so each key is a short line. Updates are looked up per `Family`
and only on the server `Catalog` names; one from another catalog says so in the
manager instead of reading as current. `App ID` and `App Version` are written
for whoever reads the device; this app does not read them back.

Archivarius does not say what a file was built for, so from Official the API is
what the official app writes there (its `getSdkApi`): the version's, else the
one asked for.

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
