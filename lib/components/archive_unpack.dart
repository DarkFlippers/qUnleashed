/// What one unpack did with the archive entries it considered.
///
/// Every considered entry lands in exactly one of the three counts, which is
/// what makes a quietly lost entry impossible to hide: a caller that reports
/// only successes cannot tell a clean run from one that dropped half the
/// archive on the floor.
///
/// Which entries are considered is the caller's to define and to document —
/// the IR library weighs every file entry the decoder produced, while a plugin
/// pack weighs only the `.fap` entries and ignores the rest outright.
class UnpackTally {
  const UnpackTally({
    required this.extracted,
    required this.skipped,
    required this.dropped,
    this.firstError,
  });

  /// Entries written to disk.
  final int extracted;

  /// Entries that resolved to a path but could not be written or read. Every
  /// one is a file the user does not get.
  final int skipped;

  /// Entries the name check declined, such as a `..` traversal or anything
  /// resolving outside the destination root. Real archives have some, so
  /// these are not on their own a sign of trouble.
  final int dropped;

  /// The first failure, entry name included, for the log and the error message.
  final String? firstError;
}
