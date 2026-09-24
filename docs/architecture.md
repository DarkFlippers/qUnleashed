# qUnleashed architecture (as-is)

> What the code on `main` (`11107c0`) does, with no verdicts and no
> recommendations — this is the input to the comparison in
> `architecture-review.md`. Counts were taken with `grep`/`find` over `lib/`;
> the analyzer state comes from the Dart MCP server.
>
> Where the codebase does one job in more than one way, it is marked **mixed**.

## 1. Project structure

`lib/` holds 454 `.dart` files:

| Directory | Files | Contents |
|---|---|---|
| `lib/pages/` | 230 | 7 features: `about`, `apps`, `archive`, `devices`, `flibler`, `option`, `tools` |
| `lib/modules/` | 130 | 3 local packages (see §12) |
| `lib/components/` | 43 | shared widgets and utilities |
| `lib/services/` | 40 | cross-cutting services |
| `lib/theme/` | 5 | theming |
| `lib/app/` | 5 | application shell |

**Mixed:** the top level is feature-first (`lib/pages/<feature>/`), and below it
layer-first (`lib/services/`, `lib/components/`). Inside a feature the shape
varies too: `lib/pages/devices/` has `controllers/`, `models/`, `widgets/` and
`firmware/`, while the other features keep their logic in files next to the UI
(§5).

**There are two entry points**, both in `lib/main.dart`:

- `main()` (`lib/main.dart:17`) — `_initCore()` then `_runApp()`.
- `widgetMain()` (`lib/main.dart:27`), marked `@pragma('vm:entry-point')` — a
  home-screen widget starts it while the app is not running. It brings up the
  same isolate without a UI and without the ambient services, holding only the
  connection (`BleForegroundService`). `promote` turns it into the full app.

Startup (`_initCore`, `lib/main.dart:44`) is sequential:
`WidgetsFlutterBinding.ensureInitialized()` → `registerAppRoutes()` →
`LogService.initialize()` → theme → locale → assembler settings →
`HomeWidgetService.instance.install(promote: _runApp)`. Then `_runApp`
(`lib/main.dart:54`) calls `runApp`, followed by `bootstrapAmbientServices()`
and `HomeWidgetSettings.instance.sync()`.

## 2. State management

There is no state-management package — no `provider`, no `riverpod`, no `bloc`.
(Checked: matches on `Provider`/`Bloc` in the code are `MapTileProvider` from
`flutter_map`, `SingleTickerProviderStateMixin`, `AtpBlock` and similar.)

What is used is Flutter's own machinery:

| Mechanism | Files |
|---|---|
| `setState(` | 56 |
| `extends ChangeNotifier` | 29 |
| `AnimatedBuilder` | 32 |
| `ValueNotifier` | 10 |
| `ListenableBuilder` | 6 |
| `ValueListenableBuilder` | 5 |
| `InheritedNotifier` / `InheritedWidget` | 2 / 2 |
| `StreamBuilder` | 0 |

`StreamBuilder` is never used, even though the transport layer exposes a
`Stream` (§6): connection state reaches the UI through `ChangeNotifier`.

**Mixed:** three ways to rebuild on a `Listenable` coexist — `AnimatedBuilder`
(32), `ListenableBuilder` (6) and `ValueListenableBuilder` (5).

`ChangeNotifier` classes live inside features rather than in one layer: 4 in
`lib/pages/apps/data`, 2 each in `lib/services/connection`,
`lib/pages/devices/controllers` and `lib/pages/archive/editor/hex`, and one
each in 19 more directories.

## 3. Dependency injection / service location

There is no container (`get_it`: 0 matches). Dependencies arrive three ways:

1. **Hand-rolled singletons** — 28 declarations of the form
   `static final X instance = ...`: `LogService`,
   `QAppThemeController.instance`, `QLocaleController.instance`,
   `AssemblerController.instance`, `HomeWidgetService.instance`,
   `FirmwareRepository.instance`, `PushService.instance` and others. They are
   reached directly from anywhere.
2. **The `FlipperOneClient()` factory singleton**
   (`lib/modules/flipperlib/lib/flipperlib.dart:28`) — it does not have the
   `static final instance` shape, so it is not among the 28 above, but it is
   what gives access to the device: **24 call sites** in `lib/` outside the
   modules.
3. **`InheritedNotifier`** — `DeviceScope`
   (`lib/pages/devices/device_scope.dart`) passes a `DeviceController` down the
   subtree; `lib/components/cardlist.dart` does the same for its list.

**Mixed:** the same object can be reachable both ways — `FirmwareCard` takes
controllers from `DeviceScope` and from singletons.

## 4. Navigation and routing

There is no routing package (`go_router` is absent) and no named routes
(0 matches for `pushNamed` / `onGenerateRoute` / `routes:`).

**Mixed**, two mechanisms:

1. **A hand-rolled registry** for cross-feature navigation.
   `lib/components/navigation.dart` declares `enum AppRoute` (10 values),
   `registerRoute()`, `openRoute()` and typed arguments (`PixelEditorArgs`,
   `PlotterArgs`). `lib/app/routes.dart:15` is the only place that knows about
   every feature page at once; `registerAppRoutes()` runs from `_initCore`
   before `runApp`. An unregistered route throws `StateError`
   (`navigation.dart:56`).
2. **Direct `Navigator`** inside a feature: 16 `Navigator.push` calls,
   25 `MaterialPageRoute`.

## 5. Layers: UI / logic / data

There are no formal boundaries — no `domain`/`data` directory at the `lib/`
level, and no lint rule about imports.

Direct imports of `package:flipperlib` (the device transport), by directory:

| Directory | Files importing `package:flipperlib` |
|---|---|
| `lib/pages/` | 37 |
| `lib/services/` | 11 |
| `lib/components/` | 4 |

**5 of them sit in a `widgets/` directory** at some depth —
`devices/widgets/{firmware_card,firmware_changelog_page,firmware_update_button}.dart`,
`archive/browser/widgets/storage_card.dart` and
`tools/infrared/widgets/ir_file_viewer.dart` — so a widget reaches the device
client with nothing in between.

A `controllers/` directory exists only under `lib/pages/devices/` (2 files). In
every other feature the classes holding logic sit beside the pages (§2).

## 6. The BLE layer

Encapsulated in the local package `lib/modules/flipperlib`. The shape of
`lib/modules/flipperlib/lib/src/`:

```
client/    client.dart + api/{app,ble,desktop,gpio,gui,property,storage,system,usb}.dart
session/   protocol.dart, queue.dart, session.dart
transport/ ble/…, usb/…
model/     common/     dfu/     proto/generated/
```

**Two transports, not one.** USB/serial sits beside BLE:

- `transport/ble/` — `android`, `ios`, `linux`, `macos`, `windows`,
  `unsupported`, plus `gatt.dart`, `link.dart`, `ops.dart`, `platform.dart`.
- `transport/usb/` — the same platforms, plus `serial/` (port discovery for
  Linux/macOS/Windows, `flipper_filter.dart`), `hotplug/` for three operating
  systems, and `isolate.dart`.

Packages: `universal_ble ^2.1.1` (BLE), `usb_serial ^0.5.2` and
`flutter_libserialport ^0.6.0` (USB).

**Connection and reconnect** (`client/client.dart`):

- `autoReconnect = true` (`:61`),
  `reconnectSettle = Duration(milliseconds: 600)` (`:31`).
- `connectionCtrl` is a
  `StreamController<FlipperConnectionState>.broadcast()` (`:39`), exposed as
  `connectionStream` (`:101`).
- Comments at `:861` and `:1110` distinguish a session that died terminally
  (reconnect exhausted) from errors an automatic reconnect can survive.

**Request queue** (`session/queue.dart`): `QueuedRequest` carries `priority`
(`FlipperRequestPriority`), `seq`, `interleavable`, `holdsTxUntilAnswer`, a
`_settled` flag and `onSent`/`onError` callbacks; it implements `Comparable`.

**Timeouts:** 35 sites using `Duration(...)` or `.timeout(` across `session/`
and `transport/`.

## 7. Working with device files

The protocol is protobuf: 30 `*.pb*.dart` files in
`lib/modules/flipperlib/lib/src/proto/generated/`, with `protobuf ^6.0.0` and
`fixnum ^1.1.1`.

The filesystem API is `client/api/storage.dart`, 14 operations:
`storageList`, `storageRead`, `storageReadChunked`, `storageWrite`,
`storageDelete`, `storageMkdir`, `storageMd5sum`, `storageStat`,
`storageInfo`, `storageRename`, `storageBackupCreate`,
`storageBackupRestore`, `storageDu`, `storageTimestamp`.

Return types are not uniform: some hand back `FlipperRpcBatch<XResponse>`
(`storageList`, `storageRead`, `storageMd5sum`, `storageStat`, `storageInfo`,
`storageTimestamp`), the mutations return `List<Main>`, `storageReadChunked`
returns `List<int>` and `storageDu` returns `int`.

What happens when the link drops mid-transfer is described in a comment at
`storage.dart:351`: once the automatic reconnect restores the session, the
upload restarts.

## 8. Error handling

There are no result types: 0 matches for `class Result`,
`sealed class …Result` or `Either<`. Exceptions are used throughout.

| Pattern | Count |
|---|---|
| `} catch (` | 378 |
| `} on <Type> catch` | 23 |
| `catch (_) {}` (empty) | 49 — 42 in the app, 7 in `flipperlib` (4 of those inside an isolate) |
| `implements Exception` (own types) | 26 |

**Mixed:** 378 untyped `catch` against 23 typed ones.

`lib/services/guarded.dart` wraps a future nobody is waiting on: it returns a
future that **never rejects** (queues chain the next operation with
`previous.then(...)`, so one failure would otherwise strand everything behind
it) and logs at a fixed `error` level.

`lib/services/logging.dart` holds `LogService`: `error` and `warn` are kept in
a bounded in-memory buffer, `info`/`debug`/`trace` are not; it installs the
uncaught-error handlers in `initialize()`.

## 9. Models and serialization

**There is no JSON code generation** — `pubspec.yaml` has no `build_runner`,
`freezed`, `json_serializable` or `json_annotation`.

- 135 `fromJson` mentions, all hand-written.
- 4 `toJson` mentions — serialization is almost entirely one-way (reading).
- Protobuf classes are generated and committed (`proto/generated/`).

## 10. Platform code

**Android** (`android/app/src/main/kotlin/com/darkflippers/qunleashed/`):
`MainActivity.kt`, `MediaRemoteChannel.kt`, and 7 home-screen widget files —
`widget/FlutterEngineHolder.kt`, `HomeWidgetChannel.kt`,
`KeyWidgetProvider.kt`, `KeyWidgetReceiver.kt`, `KeyWidgetRenderer.kt`,
`KeyWidgetStore.kt`, `WidgetSettings.kt`.

**iOS** (`ios/Runner/`): `AppDelegate.swift`, `SceneDelegate.swift` — nothing
beyond the template.

**Native C/C++**: `lib/modules/cpp/` — `CMakeLists.txt`, `hardnested/`,
`mfkey32/`, `nfc-tools/` (the last one is a submodule too, from the
flipperdevices repo). Reached through `ffi ^2.1.3`.

Desktop: `linux/`, `macos/`, `windows/` and `web/` directories exist.

## 11. Tests

- 51 `*_test.dart` files under `test/` (53 `.dart` files including fixtures).
- `flutter test` on `main`: **691 passed, 4 skipped**, no failures.
- CI (`.github/workflows/ci.yml`) runs format → analyze → test; Flutter is
  pinned to `3.47.1` in `.github/actions/setup-flutter/action.yml:19`.
- Two order dependencies are known and reproduce on `main` as well:
  `test/logging_history_test.dart:223` and `test/flibler_project_test.dart:103`
  (issue #139). `flutter test` does not randomize order by default, so CI is
  green.
- There is no mutation testing in the repository; it has been run ad hoc from
  scripts kept outside it.
- **The submodules are covered differently.** Counting all the code owned by
  the same organisation:

  | Part | `.dart` files | Test files |
  |---|---|---|
  | app (`lib/` without `modules/`) | 324 | 51 |
  | `flipperlib` | 96 | **0** |
  | `dartufbt` | 31 | 1 |

  `flipperlib`'s own CI runs `dart format --set-exit-if-changed` and
  `flutter analyze`; it has no `flutter test` step. That is the code holding
  the transport, the session, the RPC queue, auto-reconnect and DFU.

## 12. Dependencies

**Local packages** are wired with `path:`, but they are git submodules — that
is, separate repositories (`.gitmodules`). Both belong to the same
organisation (`DarkFlippers/dart-flipperlib`, `DarkFlippers/dart-ufbt`), so a
change to either is a PR in its own repository and arrives here as a submodule
bump. A third submodule, `lib/modules/cpp/nfc-tools`, belongs to someone else
(`flipperdevices/flipperzero-nfc-tools`).

| Package | Path | Role |
|---|---|---|
| `flipperlib` | `lib/modules/flipperlib` | transport, session, device RPC client |
| `dartufbt` | `lib/modules/dartufbt` | Dart port of uFBT: SDK deploy, FAP builds |

**The external ones that matter:**

| Package | Responsibility |
|---|---|
| `universal_ble`, `usb_serial`, `flutter_libserialport` | transports to the device |
| `protobuf`, `fixnum` | RPC frames |
| `ffi` | bridge to `lib/modules/cpp` |
| `shared_preferences` | every setting |
| `firebase_core`, `firebase_messaging` | push |
| `flutter_foreground_task` | holding the link in the background (Android) |
| `flutter_local_notifications` | local notifications |
| `http` | network (app catalog, firmware directories) |
| `archive`, `crypto` | unpacking and checksumming firmware |
| `re_editor`, `re_highlight`, `flutter_highlight`, `highlight` | code editor |
| `flutter_html`, `flutter_html_table`, `markdown` | rendering descriptions and changelogs |
| `flutter_map`, `geolocator` | the map |
| `xterm` | terminal |
| `window_manager` | desktop window |
| `file_picker`, `path_provider`, `share_plus`, `saver_gallery`, `pasteboard` | files and sharing |
| `flutter_svg`, `diffutil_dart`, `permission_handler`, `url_launcher`, `device_info_plus`, `package_info_plus` | the rest |
| `logger`, `logging` | both are imported by exactly one file, `lib/services/logging.dart`; the project's own `LogService` is built on top of them |

**Dev:** `flutter_test`, `flutter_lints ^6.0.0`, `analyzer ^14.4.0`,
`path_provider_platform_interface`, `shared_preferences_platform_interface`.

## 13. Analyzer state

- Dart MCP `analyze_files` over the project root: **No errors**.
- `flutter analyze`: **No issues found**.
- `dart format` through `.github/scripts/check_format.sh`: 373 files, no
  differences.
- `comment_references` is not enabled in `analysis_options.yaml`, so a doc
  comment pointing at a deleted symbol is not caught by the analyzer.
- CI treats infos and warnings as fatal.

## Data flow

```
┌─────────────────────────────────────────────────────────────┐
│ UI              lib/pages/<feature>/…  +  lib/components/   │
│                 setState · AnimatedBuilder · DeviceScope    │
└───────────────┬─────────────────────────────────────────────┘
                │ reads / listens
                ▼
┌─────────────────────────────────────────────────────────────┐
│ Logic           ChangeNotifier inside features (29 classes) │
│                 + singletons in lib/services/ (28 instance) │
└───────────────┬─────────────────────────────────────────────┘
                │  37 files under lib/pages/ import flipperlib
                │  directly, bypassing this layer
                ▼
┌─────────────────────────────────────────────────────────────┐
│ Client          flipperlib · client/api/*.dart              │
│                 storage · system · gui · gpio · app · ble   │
└───────────────┬─────────────────────────────────────────────┘
                ▼
┌─────────────────────────────────────────────────────────────┐
│ Session         session/{protocol,queue,session}.dart       │
│                 priority queue, seq, timeouts               │
└───────────────┬─────────────────────────────────────────────┘
                ▼
┌─────────────────────────────────────────────────────────────┐
│ Transport       transport/ble/<platform>.dart               │
│                 transport/usb/<platform>.dart + serial      │
│                 autoReconnect · reconnectSettle 600ms       │
└───────────────┬─────────────────────────────────────────────┘
                ▼
          ┌───────────────┐
          │  Flipper Zero │   protobuf RPC
          └───────────────┘

Back up: connectionStream (broadcast) ─► ChangeNotifier ─► UI
         StreamBuilder is not used anywhere (0 matches)
```
