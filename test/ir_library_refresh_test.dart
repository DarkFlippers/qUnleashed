import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qunleashed/pages/tools/infrared/local_repo.dart';

final String sep = Platform.pathSeparator;

/// Stands in for `getTemporaryDirectory()`.
///
/// Through the platform interface rather than the method channel: the Windows
/// implementation is pure Dart over FFI and never goes near a channel, so a
/// channel mock works on some platforms and silently does nothing on others.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.temp);
  final String temp;

  @override
  Future<String?> getTemporaryPath() async => temp;
}

/// Serves one body to whatever `AppHttp` asks for.
///
/// `AppHttp.client` is a lazy `static final`, built on first touch and then
/// kept for the isolate, so the body has to be reachable through a mutable
/// hook rather than captured when the client is made.
class _FakeHttpOverrides extends HttpOverrides {
  static late List<int> body;
  static int status = 200;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

class _FakeHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeRequest();

  @override
  noSuchMethod(Invocation invocation) => null;
}

class _FakeRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeResponse();

  @override
  noSuchMethod(Invocation invocation) => null;
}

class _FakeHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  noSuchMethod(Invocation invocation) => null;
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  final _body = _FakeHttpOverrides.body;

  @override
  int get statusCode => _FakeHttpOverrides.status;

  @override
  int get contentLength => _body.length;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(_body).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  noSuchMethod(Invocation invocation) => null;
}

/// The shape codeload serves: every entry inside one wrapper folder.
List<int> irdbZip(
  Map<String, String> files, {
  String wrapper = 'Flipper-IRDB-main',
}) {
  final archive = Archive();
  files.forEach((name, content) {
    archive.add(
      ArchiveFile.bytes(
        '$wrapper/$name',
        Uint8List.fromList(content.codeUnits),
      ),
    );
  });
  return ZipEncoder().encode(archive);
}

void main() {
  late Directory base;
  late Directory root;
  late Directory temp;

  setUpAll(() => HttpOverrides.global = _FakeHttpOverrides());
  tearDownAll(() => HttpOverrides.global = null);

  setUp(() {
    base = Directory.systemTemp.createTempSync('ir_refresh_test');
    root = Directory('${base.path}${sep}irlib');
    temp = Directory('${base.path}${sep}tmp')..createSync();
    PathProviderPlatform.instance = _FakePathProvider(temp.path);
    IrLibLocalRepo.debugUseRoot(root);
    addTearDown(() => IrLibLocalRepo.debugUseRoot(null));
    _FakeHttpOverrides.status = 200;
  });

  tearDown(() {
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  Future<Directory> refresh() => IrLibLocalRepo().download(
    owner: 'Lucaslhm',
    repo: 'Flipper-IRDB',
    branch: 'main',
  );

  String read(String relative) => File(
    '${root.path}$sep${relative.replaceAll('/', sep)}',
  ).readAsStringSync();

  List<Directory> supersededTrees() => base
      .listSync()
      .whereType<Directory>()
      .where((d) => d.path.startsWith('${root.path}.superseded'))
      .toList();

  /// The library where a swap that died between its two renames left it.
  Directory asideLibrary() {
    final aside = Directory('${root.path}.superseded.1000')
      ..createSync(recursive: true);
    Directory('${aside.path}${sep}TVs').createSync(recursive: true);
    File('${aside.path}${sep}TVs${sep}Old.ir').writeAsStringSync('old remote');
    return aside;
  }

  /// Stops the restore the way a stray file at the library path would: the
  /// rename has nowhere to land, and the tree beside it is the only copy.
  Directory blockRestore(Directory aside) {
    File(root.path).writeAsStringSync('in the way');
    return aside;
  }

  test('a refresh unpacks the library and puts it in place', () async {
    _FakeHttpOverrides.body = irdbZip({'TVs/Sony.ir': 'sony remote'});

    await refresh();

    expect(read('TVs/Sony.ir'), 'sony remote');
  });

  // The staging is the point: the unpack has to land beside the library, and
  // only a finished one replaces it. Writing into the root directly would pass
  // every test that only drives swapIn.
  test(
    'an existing library is replaced only once the new one is whole',
    () async {
      Directory('${root.path}${sep}TVs').createSync(recursive: true);
      File('${root.path}${sep}TVs${sep}Old.ir').writeAsStringSync('old remote');
      _FakeHttpOverrides.body = irdbZip({'TVs/Sony.ir': 'sony remote'});

      await refresh();

      expect(read('TVs/Sony.ir'), 'sony remote');
      expect(
        File('${root.path}${sep}TVs${sep}Old.ir').existsSync(),
        isFalse,
        reason: 'the whole tree is replaced, not merged into',
      );
    },
  );

  // #62 itself. The old code deleted the library before it fetched a byte, so
  // anything that went wrong afterwards left the user with nothing.
  test('a refresh that fails leaves the library exactly as it was', () async {
    Directory('${root.path}${sep}TVs').createSync(recursive: true);
    File('${root.path}${sep}TVs${sep}Old.ir').writeAsStringSync('old remote');
    _FakeHttpOverrides.status = 500;

    await expectLater(refresh(), throwsA(anything));

    expect(read('TVs/Old.ir'), 'old remote');
  });

  test('a library that will not unpack is not swapped in', () async {
    Directory('${root.path}${sep}TVs').createSync(recursive: true);
    File('${root.path}${sep}TVs${sep}Old.ir').writeAsStringSync('old remote');
    _FakeHttpOverrides.body = const [1, 2, 3, 4, 5];

    await expectLater(refresh(), throwsA(anything));

    expect(read('TVs/Old.ir'), 'old remote');
  });

  test('the staging tree does not survive a finished refresh', () async {
    _FakeHttpOverrides.body = irdbZip({'TVs/Sony.ir': 'sony remote'});

    await refresh();

    expect(Directory('${root.path}.incoming').existsSync(), isFalse);
  });

  // Recovery runs at startup now, so the repair does not wait for the user to
  // open the IR page. Until it did, the library read as absent to everything
  // else — Settings → Storage reported its size as zero.
  test('startup repairs a swap that was interrupted', () async {
    asideLibrary();

    final stranded = await IrLibLocalRepo.recoverStranded();

    expect(stranded, isNull);
    expect(read('TVs/Old.ir'), 'old remote');
    expect(await IrLibLocalRepo().exists(), isTrue);
  });

  // The launch call is unawaited and reaches the Android storage permission on
  // its way to the root, which can sit on a settings page until the user
  // answers. IrLibController.initialize() awaits this before asking exists(),
  // and it must join the pass already running rather than start a second one —
  // two passes at once is how a repaired library gets recorded as stranded.
  test(
    'a second caller joins the launch pass rather than starting one',
    () async {
      asideLibrary();

      final first = IrLibLocalRepo.recoverStranded();
      final second = IrLibLocalRepo.recoverStranded();

      expect(identical(first, second), isTrue);
      await Future.wait([first, second]);
      expect(read('TVs/Old.ir'), 'old remote', reason: 'and one pass ran');
    },
  );

  // The point of taking the repair out of exists(): a method that reads as a
  // query was renaming trees and running recursive deletes, so any caller
  // added later that treated it as a cheap check got those side effects.
  test('asking whether the library exists does not move anything', () async {
    final aside = asideLibrary();

    final present = await IrLibLocalRepo().exists();

    expect(present, isFalse, reason: 'it reports, it does not repair');
    expect(aside.existsSync(), isTrue, reason: 'and leaves the tree alone');
  });

  group('when the library cannot be put back', () {
    test('recovery says where it is instead of only logging it', () async {
      final aside = blockRestore(asideLibrary());

      final stranded = await IrLibLocalRepo.recoverStranded();

      expect(stranded?.path, aside.path);
      expect(
        File('${aside.path}${sep}TVs${sep}Old.ir').readAsStringSync(),
        'old remote',
        reason: 'kept, because it is the only copy there is',
      );
    });

    // LogService.enabled is bool.fromEnvironment('QLOG', kDebugMode), so the
    // log line this used to be is compiled out of a release build. The path
    // has to survive the pass that found it, or the one moment the app knows
    // the library is one rename away is the moment it says nothing.
    test('the path outlives the pass, for the UI to read', () async {
      final aside = blockRestore(asideLibrary());

      await IrLibLocalRepo.recoverStranded();

      expect(IrLibLocalRepo.strandedLibrary.value?.path, aside.path);
    });

    test('a later run that succeeds clears it', () async {
      blockRestore(asideLibrary());
      await IrLibLocalRepo.recoverStranded();
      expect(IrLibLocalRepo.strandedLibrary.value, isNotNull);

      File(root.path).deleteSync();
      await IrLibLocalRepo.recoverInterrupted(root);

      expect(IrLibLocalRepo.strandedLibrary.value, isNull);
      expect(read('TVs/Old.ir'), 'old remote');
    });

    // The notice's only job is to be trustworthy about where the user's data
    // is. Saying it is safe at a path the app removed a moment ago is the one
    // way it can be wrong that costs something.
    test('deleting the library takes the notice with it', () async {
      blockRestore(asideLibrary());
      await IrLibLocalRepo.recoverStranded();
      expect(IrLibLocalRepo.strandedLibrary.value, isNotNull);

      File(root.path).deleteSync();
      await IrLibLocalRepo().deleteAll();

      expect(IrLibLocalRepo.strandedLibrary.value, isNull);
      expect(supersededTrees(), isEmpty);
    });

    // The recovery inside download() runs before the swap, so it can never see
    // the state the swap creates. Without the swap clearing it, the notice sat
    // under a button that now read DELETE, still advising a download.
    test('a refresh that lands clears the notice', () async {
      blockRestore(asideLibrary());
      await IrLibLocalRepo.recoverStranded();
      expect(IrLibLocalRepo.strandedLibrary.value, isNotNull);

      File(root.path).deleteSync();
      _FakeHttpOverrides.body = irdbZip({'TVs/Sony.ir': 'sony remote'});
      await refresh();

      expect(IrLibLocalRepo.strandedLibrary.value, isNull);
      expect(read('TVs/Sony.ir'), 'sony remote');
    });

    // Two passes at once, which the startup call made possible against a
    // download's own. The loser used to record a strand the winner had already
    // repaired, leaving the notice pointing at a directory that was gone.
    //
    // Asserts the invariant, not the mechanism: with the lock taken away this
    // passes or fails depending on how the two passes interleave, so it will
    // not reliably catch a regression. The guarantee is that recovery now goes
    // through the same _exclusive queue as every other operation that moves
    // these trees; this only checks the outcome that queue is there to give.
    test('two passes at once do not invent a strand', () async {
      asideLibrary();

      await Future.wait([
        IrLibLocalRepo.recoverInterrupted(root),
        IrLibLocalRepo.recoverInterrupted(root),
      ]);

      expect(IrLibLocalRepo.strandedLibrary.value, isNull);
      expect(read('TVs/Old.ir'), 'old remote');
    });
  });
}
