# Архітектура qUnleashed (as-is)

> Опис того, що є в коді на `main` (`11107c0`). Без оцінок і рекомендацій — це
> вхідні дані для Фази 2. Числа зібрані `grep`/`find` по `lib/`, стан
> аналізатора — через Dart MCP.
>
> Там, де на одну задачу в коді співіснує кілька підходів, стоїть позначка
> **змішано**.

## 1. Структура проєкту

`lib/` — 454 файли `.dart`, поділені так:

| Тека | Файлів | Що містить |
|---|---|---|
| `lib/pages/` | 230 | 7 фіч: `about`, `apps`, `archive`, `devices`, `flibler`, `option`, `tools` |
| `lib/modules/` | 130 | 3 локальні пакети (див. §12) |
| `lib/components/` | 43 | спільні віджети та утиліти |
| `lib/services/` | 40 | наскрізні сервіси |
| `lib/theme/` | 5 | тема |
| `lib/app/` | 5 | каркас застосунку |

**Змішано:** верхній рівень — feature-first (`lib/pages/<фіча>/`), під ним
layer-first (`lib/services/`, `lib/components/`). Усередині фічі структура не
єдина: `lib/pages/devices/` має `controllers/`, `models/`, `widgets/`,
`firmware/`, тоді як решта фіч тримає логіку у файлах поруч із UI (§5).

**Точок входу дві**, обидві в `lib/main.dart`:

- `main()` (`lib/main.dart:17`) — `_initCore()` → `_runApp()`.
- `widgetMain()` (`lib/main.dart:27`), позначена `@pragma('vm:entry-point')` —
  її запускає віджет домашнього екрана, коли застосунку немає. Піднімає той
  самий ізолят без UI і без ambient-сервісів, лише тримача зʼєднання
  (`BleForegroundService`). `promote` перетворює його на повний застосунок.

Ініціалізація (`_initCore`, `lib/main.dart:44`) послідовна:
`WidgetsFlutterBinding.ensureInitialized()` → `registerAppRoutes()` →
`LogService.initialize()` → тема → локаль → налаштування асемблера →
`HomeWidgetService.instance.install(promote: _runApp)`. Далі `_runApp`
(`lib/main.dart:54`) робить `runApp`, потім `bootstrapAmbientServices()` і
`HomeWidgetSettings.instance.sync()`.

## 2. Стейт-менеджмент

Пакета стейт-менеджменту немає — ні `provider`, ні `riverpod`, ні `bloc`
(перевірено: збіги на `Provider`/`Bloc` у коді — це `MapTileProvider` з
`flutter_map`, `SingleTickerProviderStateMixin`, `AtpBlock` тощо).

Використовуються засоби самого Flutter:

| Механізм | Файлів |
|---|---|
| `setState(` | 56 |
| `extends ChangeNotifier` | 29 |
| `AnimatedBuilder` | 32 |
| `ValueNotifier` | 10 |
| `ListenableBuilder` | 6 |
| `ValueListenableBuilder` | 5 |
| `InheritedNotifier` / `InheritedWidget` | 2 / 2 |
| `StreamBuilder` | 0 |

`StreamBuilder` не використовується жодного разу, попри те що транспортний шар
віддає `Stream` (§6): стани зʼєднання доходять до UI через `ChangeNotifier`.

**Змішано:** для перебудови на зміну `Listenable` співіснують `AnimatedBuilder`
(32), `ListenableBuilder` (6) і `ValueListenableBuilder` (5).

Класи `ChangeNotifier` розкидані по фічах, а не зібрані в один шар: 4 в
`lib/pages/apps/data`, по 2 в `lib/services/connection`,
`lib/pages/devices/controllers`, `lib/pages/archive/editor/hex`, і по одному ще
в 19 теках.

## 3. DI / service location

Контейнера немає (`get_it` — 0 згадок). Залежності отримують двома шляхами:

1. **Ручні синглтони** — 28 оголошень виду `static final X instance = ...`.
   Приклади: `LogService`, `QAppThemeController.instance`,
   `QLocaleController.instance`, `AssemblerController.instance`,
   `HomeWidgetService.instance`, `FirmwareRepository.instance`,
   `PushService.instance`. Викликаються з будь-якого місця напряму.
2. **`InheritedNotifier`** — `DeviceScope` (`lib/pages/devices/device_scope.dart`)
   передає `DeviceController` піддереву; `lib/components/cardlist.dart` робить
   те саме для свого списку.

**Змішано:** один і той самий обʼєкт може бути доступний обома шляхами —
`FirmwareCard` бере контролери і з `DeviceScope`, і з синглтонів.

## 4. Навігація та роутинг

Пакета роутингу немає (`go_router` відсутній), іменованих маршрутів теж (0
згадок `pushNamed` / `onGenerateRoute` / `routes:`).

**Змішано**, два механізми:

1. **Власний реєстр** для переходів між фічами. `lib/components/navigation.dart`
   оголошує `enum AppRoute` (10 значень), `registerRoute()`, `openRoute()` і
   типізовані аргументи (`PixelEditorArgs`, `PlotterArgs`).
   `lib/app/routes.dart:15` — єдине місце, що знає про всі сторінки одночасно;
   `registerAppRoutes()` викликається з `_initCore` до `runApp`. Незареєстрований
   маршрут кидає `StateError` (`navigation.dart:56`).
2. **Прямий `Navigator`** усередині фічі: 16 викликів `Navigator.push`,
   25 `MaterialPageRoute`.

## 5. Шари: UI / логіка / дані

Формальних меж між шарами немає — немає ні окремої теки `domain`/`data` на
рівні `lib/`, ні правила лінтера про імпорти.

Прямі імпорти `package:flipperlib` (транспорт до пристрою) за теками:

| Тека | Файлів з `package:flipperlib` |
|---|---|
| `lib/pages/` | 37 |
| `lib/services/` | 11 |
| `lib/components/` | 4 |

З них 3 файли лежать безпосередньо в `lib/pages/*/widgets/`, тобто віджет
звертається до клієнта пристрою без проміжного шару.

Тека `controllers/` існує лише у `lib/pages/devices/` (2 файли). У решті фіч
класи з логікою лежать поруч зі сторінками (§2).

## 6. BLE-шар

Інкапсульований у локальному пакеті `lib/modules/flipperlib`. Структура
`lib/modules/flipperlib/lib/src/`:

```
client/    client.dart + api/{app,ble,desktop,gpio,gui,property,storage,system,usb}.dart
session/   protocol.dart, queue.dart, session.dart
transport/ ble/…, usb/…
model/     common/     dfu/     proto/generated/
```

**Два транспорти, не один.** Поруч із BLE є USB/serial:

- `transport/ble/` — `android`, `ios`, `linux`, `macos`, `windows`,
  `unsupported`, плюс `gatt.dart`, `link.dart`, `ops.dart`, `platform.dart`.
- `transport/usb/` — ті самі платформи, плюс `serial/` (визначення портів під
  Linux/macOS/Windows, `flipper_filter.dart`) і `hotplug/` під три ОС,
  а також `isolate.dart`.

Пакети: `universal_ble ^2.1.1` (BLE), `usb_serial ^0.5.2` і
`flutter_libserialport ^0.6.0` (USB).

**Зʼєднання і reconnect** (`client/client.dart`):

- `autoReconnect = true` (`:61`), `reconnectSettle = Duration(milliseconds: 600)`
  (`:31`).
- `connectionCtrl` — `StreamController<FlipperConnectionState>.broadcast()`
  (`:39`), назовні як `connectionStream` (`:101`).
- Коментарі на `:861` і `:1110` розрізняють «сесія померла остаточно
  (reconnect вичерпано)» і помилки, які авто-reconnect може пережити.

**Черга запитів** (`session/queue.dart`): `QueuedRequest` з полями `priority`
(`FlipperRequestPriority`), `seq`, `interleavable`, `holdsTxUntilAnswer`,
прапорцем `_settled` і колбеками `onSent`/`onError`; реалізує `Comparable`.

**Таймаути:** 35 місць із `Duration(...)` або `.timeout(` у `session/` +
`transport/`.

## 7. Робота з файлами пристрою

Протокол — protobuf: 30 файлів `*.pb*.dart` у `lib/modules/flipperlib/lib/src/proto/generated/`,
пакет `protobuf ^6.0.0` + `fixnum ^1.1.1`.

API файлової системи — `client/api/storage.dart`, 14 операцій:
`storageList`, `storageRead`, `storageReadChunked`, `storageWrite`,
`storageDelete`, `storageMkdir`, `storageMd5sum`, `storageStat`, `storageInfo`,
`storageRename`, `storageBackupCreate`, `storageBackupRestore`, `storageDu`,
`storageTimestamp`.

Типи повернення неоднорідні: частина віддає `FlipperRpcBatch<XResponse>`
(`storageList`, `storageRead`, `storageMd5sum`, `storageStat`, `storageInfo`,
`storageTimestamp`), частина — `List<Main>` (мутації), `storageReadChunked` —
`List<int>`, `storageDu` — `int`.

Обробка розриву під час передачі описана в коментарі `storage.dart:351`:
після відновлення сесії авто-reconnectом завантаження перезапускається.

## 8. Обробка помилок

Result-типів немає: 0 збігів на `class Result`, `sealed class …Result`,
`Either<`. Використовуються винятки.

| Патерн | Кількість |
|---|---|
| `} catch (` | 378 |
| `} on <Тип> catch` | 23 |
| `catch (_) {}` (порожній) | 49 |
| `implements Exception` (власні типи) | 26 |

**Змішано:** 378 нетипізованих `catch` проти 23 типізованих.

`lib/services/guarded.dart` — обгортка для future, на яку ніхто не чекає:
повертає future, що **ніколи не реджектить** (черги чіплять наступну операцію
через `previous.then(...)`, тож один провал інакше застрягив би весь ланцюг), і
логує на фіксованому рівні `error`.

`lib/services/logging.dart` — `LogService`: `error`/`warn` тримаються в
памʼяті (обмежений буфер), `info`/`debug`/`trace` не зберігаються;
встановлює обробники неперехоплених помилок у `initialize()`.

## 9. Моделі та серіалізація

**Code-gen для JSON немає** — у `pubspec.yaml` відсутні `build_runner`,
`freezed`, `json_serializable`, `json_annotation`.

- 135 згадок `fromJson`, написаних вручну.
- 4 згадки `toJson` — серіалізація майже вся одностороння (читання).
- Protobuf-класи згенеровані і закомічені в репо (`proto/generated/`).

## 10. Платформний код

**Android** (`android/app/src/main/kotlin/com/darkflippers/qunleashed/`):
`MainActivity.kt`, `MediaRemoteChannel.kt`, і 7 файлів віджета домашнього
екрана — `widget/FlutterEngineHolder.kt`, `HomeWidgetChannel.kt`,
`KeyWidgetProvider.kt`, `KeyWidgetReceiver.kt`, `KeyWidgetRenderer.kt`,
`KeyWidgetStore.kt`, `WidgetSettings.kt`.

**iOS** (`ios/Runner/`): `AppDelegate.swift`, `SceneDelegate.swift` — поза
шаблоном нічого.

**Нативний C/C++**: `lib/modules/cpp/` — `CMakeLists.txt`, `hardnested/`,
`mfkey32/`, `nfc-tools/`. Підключається через `ffi ^2.1.3`.

Десктоп: є теки `linux/`, `macos/`, `windows/`, `web/`.

## 11. Тести

- 53 файли в `test/`.
- `flutter test` на `main`: **691 пройдено, 4 пропущено**, падінь немає.
- CI (`.github/workflows/ci.yml`) запускає format → analyze → test; Flutter
  запінено на `3.47.1` у `.github/actions/setup-flutter/action.yml:19`.
- Відомі дві залежності від порядку виконання, які відтворюються і на `main`:
  `test/logging_history_test.dart:223` і `test/flibler_project_test.dart:103`
  (issue #139). За замовчуванням `flutter test` не рандомізує порядок, тож CI
  зелений.
- Мутаційного тестування в репо немає; воно робилося разово скриптами поза
  репозиторієм.

## 12. Залежності

**Локальні пакети** (`path:`):

| Пакет | Шлях | Роль |
|---|---|---|
| `flipperlib` | `lib/modules/flipperlib` | транспорт, сесія, RPC-клієнт пристрою |
| `dartufbt` | `lib/modules/dartufbt` | порт ufbt: SDK, збірка FAP |

**Ключові зовнішні:**

| Пакет | За що відповідає |
|---|---|
| `universal_ble`, `usb_serial`, `flutter_libserialport` | транспорти до пристрою |
| `protobuf`, `fixnum` | кадри RPC |
| `ffi` | міст до `lib/modules/cpp` |
| `shared_preferences` | усі налаштування |
| `firebase_core`, `firebase_messaging` | push |
| `flutter_foreground_task` | утримання зʼєднання у фоні (Android) |
| `flutter_local_notifications` | локальні сповіщення |
| `http` | мережа (каталог застосунків, директорії прошивок) |
| `archive`, `crypto` | розпакування та контрольні суми прошивок |
| `re_editor`, `re_highlight`, `flutter_highlight`, `highlight` | редактор коду |
| `flutter_html`, `flutter_html_table`, `markdown` | рендер описів і чейнджлогів |
| `flutter_map`, `geolocator` | мапа |
| `xterm` | термінал |
| `window_manager` | десктопне вікно |
| `file_picker`, `path_provider`, `share_plus`, `saver_gallery`, `pasteboard` | файли й обмін |
| `flutter_svg`, `diffutil_dart`, `permission_handler`, `url_launcher`, `device_info_plus`, `package_info_plus` | решта |
| `logger`, `logging` | обидва імпортує рівно один файл — `lib/services/logging.dart`; власний `LogService` побудований поверх них |

**Dev:** `flutter_test`, `flutter_lints ^6.0.0`, `analyzer ^14.4.0`,
`path_provider_platform_interface`, `shared_preferences_platform_interface`.

## 13. Стан аналізатора

- Dart MCP `analyze_files` по кореню проєкту: **No errors**.
- `flutter analyze`: **No issues found**.
- `dart format` через `.github/scripts/check_format.sh`: 373 файли, розбіжностей
  немає.
- В `analysis_options.yaml` `comment_references` не увімкнено, тож посилання в
  doc-коментарях на видалені символи аналізатор не ловить.
- CI трактує infos і warnings як фатальні.

## Потік даних

```
┌─────────────────────────────────────────────────────────────┐
│ UI                lib/pages/<фіча>/…  +  lib/components/    │
│                   setState · AnimatedBuilder · DeviceScope  │
└───────────────┬─────────────────────────────────────────────┘
                │ читає/слухає
                ▼
┌─────────────────────────────────────────────────────────────┐
│ Логіка            ChangeNotifier у фічах (29 класів)        │
│                   + синглтони lib/services/ (28 instance)   │
└───────────────┬─────────────────────────────────────────────┘
                │  37 файлів lib/pages/ імпортують flipperlib
                │  напряму, оминаючи цей шар
                ▼
┌─────────────────────────────────────────────────────────────┐
│ Клієнт            flipperlib · client/api/*.dart            │
│                   storage · system · gui · gpio · app · ble │
└───────────────┬─────────────────────────────────────────────┘
                ▼
┌─────────────────────────────────────────────────────────────┐
│ Сесія             session/{protocol,queue,session}.dart     │
│                   черга з пріоритетами, seq, таймаути       │
└───────────────┬─────────────────────────────────────────────┘
                ▼
┌─────────────────────────────────────────────────────────────┐
│ Транспорт         transport/ble/<платформа>.dart            │
│                   transport/usb/<платформа>.dart + serial   │
│                   autoReconnect · reconnectSettle 600ms     │
└───────────────┬─────────────────────────────────────────────┘
                ▼
          ┌───────────────┐
          │  Flipper Zero │   protobuf RPC
          └───────────────┘

Назад: connectionStream (broadcast) ─► ChangeNotifier ─► UI
       StreamBuilder не використовується (0 згадок)
```
