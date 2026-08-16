import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dartufbt/dartufbt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/assembler/backend_mode.dart';
import 'package:qunleashed/services/assembler/build_service.dart';

AssemblerBackendChoice _choice({
  bool platformSupported = true,
  bool localReady = true,
  bool localFaulted = false,
  AssemblerBackendPreference preference = AssemblerBackendPreference.auto,
}) => resolveAssemblerBackend(
  platformSupported: platformSupported,
  localReady: localReady,
  localFaulted: localFaulted,
  preference: preference,
);

void main() {
  test('a deployed local ufbt builds here', () {
    final choice = _choice();
    expect(choice.backend, AssemblerBackend.local);
    expect(choice.reason, AssemblerBackendReason.ready);
  });

  test('a missing SDK or toolchain moves builds to the server', () {
    final choice = _choice(localReady: false);
    expect(choice.backend, AssemblerBackend.server);
    expect(choice.reason, AssemblerBackendReason.notInstalled);
  });

  test('phones have no local ufbt at all', () {
    final choice = _choice(platformSupported: false, localReady: false);
    expect(choice.backend, AssemblerBackend.server);
    expect(choice.reason, AssemblerBackendReason.unsupported);
  });

  test('a local toolchain that failed hands the work over', () {
    final choice = _choice(localFaulted: true);
    expect(choice.backend, AssemblerBackend.server);
    expect(choice.reason, AssemblerBackendReason.faulted);
  });

  test('a pinned server is the only sticky choice', () {
    final choice = _choice(preference: AssemblerBackendPreference.server);
    expect(choice.backend, AssemblerBackend.server);
    expect(choice.reason, AssemblerBackendReason.chosen);
    // Deploying the SDK later brings automatic builds back on its own.
    expect(_choice(localReady: false).backend, AssemblerBackend.server);
    expect(_choice().backend, AssemblerBackend.local);
  });

  test('older builds stored the backend, not the preference', () {
    expect(
      AssemblerBackendPreference.parse('local'),
      AssemblerBackendPreference.auto,
    );
    expect(
      AssemblerBackendPreference.parse('server'),
      AssemblerBackendPreference.server,
    );
    expect(
      AssemblerBackendPreference.parse(null),
      AssemblerBackendPreference.auto,
    );
  });

  test('only a broken toolchain is retried on the server', () {
    expect(
      isLocalEnvironmentFailure(
        const AssemblerNotReadyException('SDK is not installed'),
      ),
      isTrue,
    );
    expect(
      isLocalEnvironmentFailure(
        const FapEnvironmentException('Toolchain binary not found: gcc'),
      ),
      isTrue,
    );
    expect(
      isLocalEnvironmentFailure(const FileSystemException('state dir gone')),
      isTrue,
    );
    expect(
      isLocalEnvironmentFailure(ProcessException('arm-none-eabi-gcc', [])),
      isTrue,
    );
    expect(isLocalEnvironmentFailure(ArchiveException('bad zip')), isTrue);

    // The toolchain ran and the app did not compile: the server would fail
    // the same way, so this one is shown to the user.
    expect(
      isLocalEnvironmentFailure(
        const AssemblerBuildFailedException('gcc failed with exit code 1'),
      ),
      isFalse,
    );
    expect(
      isLocalEnvironmentFailure(
        const FapBuildException('No source files found for hello_world'),
      ),
      isFalse,
    );
    expect(isLocalEnvironmentFailure(StateError('cancelled')), isFalse);
  });
}
