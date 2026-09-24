import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/devices/firmware/directory.dart';

/// Which archive the installer is handed, and whether it has a checksum to
/// match it against — ADR 0009.
///
/// `getUpdatePackage` returns two different kinds of thing under one type. For
/// the base variant it hands back a file the feed published, checksum and all.
/// For the two extra-apps variants it *mints* a URL the feed never listed, by
/// rewriting the base one, and no checksum exists for it anywhere.
///
/// That second case is the reason `FirmwareFile.sha256` is nullable. It used
/// to be `''`, which `RemoteFirmwareSource._verifySha256` read as permission
/// to skip verifying an archive about to be flashed — the same value a parse
/// default would have produced.
void main() {
  FirmwareFile file({String target = 'f7', String? sha256 = 'abc'}) =>
      FirmwareFile(
        url:
            'https://up.unleashedflip.com/'
            'fw/flipper-z-$target-update-unlshd-090.tgz',
        target: target,
        type: 'update_tgz',
        sha256: sha256,
      );

  FirmwareDirectory directoryWith(String channelId, List<FirmwareFile> files) =>
      FirmwareDirectory(
        channels: [
          FirmwareDirectoryChannel(
            id: channelId,
            title: channelId,
            description: '',
            versions: [
              FirmwareVersion(
                version: 'unlshd-090',
                changelog: '',
                files: files,
              ),
            ],
          ),
        ],
      );

  final parser = UnleashedParser.instance;

  setUp(() => parser.seedCache(directoryWith('release', [file()])));
  tearDown(parser.clearCache);

  group('the base variant', () {
    test('is the feed entry itself, checksum and all', () {
      final package = parser.getUpdatePackage('release')!;

      expect(package.sha256, 'abc');
      expect(package.url, contains('/fw/'));
      expect(
        package.url,
        isNot(contains('fw_extra_apps')),
        reason: 'nothing is rewritten for the base build',
      );
    });

    test('is null when the feed has no archive for the target', () {
      expect(parser.getUpdatePackage('release', target: 'f18'), isNull);
    });
  });

  group('an extra-apps variant', () {
    // The URL is built, not published. There is no checksum for it to carry,
    // and `null` is how the installer is told so - an empty string would be
    // indistinguishable from a checksum that failed to decode.
    for (final (variant, suffix) in const [
      (UnleashedVariant.extraPacks, 'e'),
      (UnleashedVariant.compact, 'c'),
    ]) {
      test('carries no checksum: ${variant.name}', () {
        final package = parser.getUpdatePackage('release', variant: variant)!;

        expect(package.sha256, isNull);
        expect(
          package.url,
          'https://up.unleashedflip.com/fw_extra_apps/'
          'flipper-z-f7-update-unlshd-090$suffix.tgz',
        );
        expect(package.target, 'f7');
        expect(package.type, 'update_tgz');
      });
    }

    test('is offered on development as well as release', () {
      parser.seedCache(directoryWith('development', [file()]));

      final package = parser.getUpdatePackage(
        'development',
        variant: UnleashedVariant.compact,
      );

      expect(package, isNotNull);
      expect(package!.sha256, isNull);
    });

    // Release-candidate builds publish no extra-apps archives at all, so there
    // is nothing to mint a URL for. Falling back to the base file would hand
    // the installer a build the user did not choose.
    test('is not offered on a channel that publishes none', () {
      parser.seedCache(directoryWith('release-candidate', [file()]));

      expect(
        parser.getUpdatePackage(
          'release-candidate',
          variant: UnleashedVariant.compact,
        ),
        isNull,
      );
    });

    // Mint from a name the pattern does not match and the base URL comes back
    // unchanged - with the *base* checksum dropped, because the file is still
    // reported as a variant. The checksum must not be inherited: it belongs to
    // the archive the feed published, not to whatever this returns.
    test(
      'never inherits the base checksum, even when the URL is unchanged',
      () {
        parser.seedCache(
          directoryWith('release', [
            FirmwareFile(
              url: 'https://up.unleashedflip.com/fw/not-the-expected-name.tgz',
              target: 'f7',
              type: 'update_tgz',
              sha256: 'abc',
            ),
          ]),
        );

        final package = parser.getUpdatePackage(
          'release',
          variant: UnleashedVariant.compact,
        )!;

        expect(
          package.url,
          'https://up.unleashedflip.com/fw/not-the-expected-name.tgz',
        );
        expect(package.sha256, isNull);
      },
    );
  });
}
