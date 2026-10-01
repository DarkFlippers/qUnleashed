import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/http/app_http.dart';

/// What a fetch does when nothing replaced it in a widget test.
///
/// `flutter_test` installs HttpOverrides, so an unreplaced request never
/// reaches the network: it answers 400, and the app turns that into an
/// `AppHttpException`. Several seams are written against exactly that -
/// `FirmwareParser.fetchJson`'s doc says so in as many words - and a widget
/// test that reaches one gets one network-shaped failure and nothing else.
///
/// #199 broke it without failing anything. The idle deadline it added
/// widened the response stream to `Stream<List<int>>`, and
/// `transform(utf8.decoder)` then casts the decoder to a transformer over
/// the stream's runtime element type, which the mock's is not. Every such
/// test started getting a `TypeError`. Nothing caught it, because the three
/// files covering AppHttp all run without this binding and so against a real
/// client, where the cast does not arise.
///
/// Which is what this file is: the binding the rest of them do not install.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Unroutable, so a run that somehow escaped the override would fail rather
  // than reach anything.
  final uri = Uri.parse('http://127.0.0.1:1/directory.json');

  group('a fetch nobody replaced', () {
    test('reads as a refused request, not a type error', () async {
      await expectLater(AppHttp.getJson(uri), throwsA(isA<AppHttpException>()));
    });

    test('is the same for a cached read', () async {
      await expectLater(
        AppHttp.getJsonCached(uri),
        throwsA(isA<AppHttpException>()),
      );
    });

    test('is the same for bytes', () async {
      await expectLater(
        AppHttp.getBytes(uri),
        throwsA(isA<AppHttpException>()),
      );
    });

    // The status is the part seams read, and it is what the override chose
    // rather than anything this app decided.
    test('carries the status the override answered with', () async {
      try {
        await AppHttp.getJson(uri);
        fail('the override answers every request');
      } on AppHttpException catch (e) {
        expect(e.statusCode, 400);
      }
    });
  });
}
