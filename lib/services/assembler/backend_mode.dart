/// Where a source build actually runs.
enum AssemblerBackend { local, server }

/// What the settings page asks for. The local toolchain is never a standing
/// choice: it is used while it works and the server takes over the moment it
/// does not, so the only thing worth storing is whether the user pinned the
/// server for good.
enum AssemblerBackendPreference {
  auto,
  server;

  /// Older builds stored the backend itself; `local` was their default and
  /// means "use this computer when it can", which is exactly [auto].
  static AssemblerBackendPreference parse(String? raw) =>
      raw == server.name ? server : auto;
}

/// Why the backend below is the one in use, so the settings can say it in
/// words instead of leaving the user guessing.
enum AssemblerBackendReason {
  ready('builds run on this computer'),
  chosen('picked in the settings'),
  unsupported('local builds need a desktop'),
  notInstalled('SDK or toolchain is not installed'),
  faulted('local toolchain failed, using the server');

  const AssemblerBackendReason(this.label);

  final String label;
}

class AssemblerBackendChoice {
  const AssemblerBackendChoice(this.backend, this.reason);

  final AssemblerBackend backend;
  final AssemblerBackendReason reason;

  bool get isLocal => backend == AssemblerBackend.local;
}

/// Picks where a build runs: this computer while its ufbt state is complete
/// and working, the server in every other case. Nothing but a deliberate
/// server choice is sticky, so an SDK downloaded later brings local builds
/// back on its own.
AssemblerBackendChoice resolveAssemblerBackend({
  required bool platformSupported,
  required bool localReady,
  required bool localFaulted,
  AssemblerBackendPreference preference = AssemblerBackendPreference.auto,
}) {
  if (preference == AssemblerBackendPreference.server) {
    return const AssemblerBackendChoice(
      AssemblerBackend.server,
      AssemblerBackendReason.chosen,
    );
  }
  if (!platformSupported) {
    return const AssemblerBackendChoice(
      AssemblerBackend.server,
      AssemblerBackendReason.unsupported,
    );
  }
  if (localFaulted) {
    return const AssemblerBackendChoice(
      AssemblerBackend.server,
      AssemblerBackendReason.faulted,
    );
  }
  if (!localReady) {
    return const AssemblerBackendChoice(
      AssemblerBackend.server,
      AssemblerBackendReason.notInstalled,
    );
  }
  return const AssemblerBackendChoice(
    AssemblerBackend.local,
    AssemblerBackendReason.ready,
  );
}
