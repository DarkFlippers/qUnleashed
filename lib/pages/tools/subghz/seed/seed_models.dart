/// The things a SubGHz seed recovery works on: a capture, a manufacturer, and
/// how a recovery ended.
library;

/// The remotes the engine has a manufacture key for.
///
/// `mode` is the number the native engine takes. It is hard-coded inside the
/// generated engine rather than derived from anything here, so this enum is a
/// transcription of that numbering and not its source - see
/// `lib/modules/cpp/faaccrack/BUILD_NOTES.md`. The known-answer vectors in the
/// native probe are what hold the two in step.
enum SeedManufacturer {
  faacSlh(mode: 1, label: 'FAAC SLH', protocol: 'Faac SLH'),
  bft(mode: 2, label: 'BFT', protocol: 'KeeLoq'),
  genius(mode: 3, label: 'Genius', protocol: 'Faac SLH'),
  erreka(mode: 4, label: 'Erreka', protocol: 'KeeLoq');

  const SeedManufacturer({
    required this.mode,
    required this.label,
    required this.protocol,
  });

  /// The engine's mode number.
  final int mode;

  /// How the Flipper-side capture app writes it, and how a `.sub` spells the
  /// `Manufacture` field.
  final String label;

  /// The `Protocol` a written `.sub` carries. Two manufacturers share each: a
  /// file says which of them it is through `Manufacture`.
  final String protocol;

  /// The counter inside a decrypted hop is 20 bits for the Faac protocols and
  /// 16 for the KeeLoq ones. Only used for formatting - the engine already
  /// masks it - but a counter printed to the wrong width looks like a bug in
  /// the recovery rather than in the display.
  int get counterDigits => protocol == 'Faac SLH' ? 5 : 4;

  /// Spacing and case, which the label is not meaningful in: it is typed into
  /// the Flipper app's source by hand, and "FAAC SLH" versus "FAAC_SLH" is not
  /// a difference worth failing a capture over.
  static final _noise = RegExp(r'[\s_]');

  String get _normalised => label.replaceAll(_noise, '').toLowerCase();

  /// The manufacturer the capture file names, or null if it names something
  /// this build has no key for.
  static SeedManufacturer? fromLabel(String label) {
    final wanted = label.replaceAll(_noise, '').toLowerCase();
    for (final manufacturer in SeedManufacturer.values) {
      if (manufacturer._normalised == wanted) return manufacturer;
    }
    return null;
  }
}

/// One capture file: a remote's fixed code and the hops it was seen sending.
///
/// Everything except [fix] and [hops] is optional, because the file is written
/// by a separate app on a device whose clock may not be set and whose format
/// may gain fields. A capture missing its frequency is still solvable; it just
/// cannot be written back as a transmittable file without one.
class SeedCapture {
  const SeedCapture({
    required this.fix,
    required this.hops,
    required this.manufacturer,
    this.frequencyHz,
  });

  /// The fixed code: the top 32 bits of the frame, the same in every hop.
  final int fix;

  /// The rolling halves, in the order they were received.
  ///
  /// Order is load-bearing and not a presentation detail: the engine accepts a
  /// seed only if consecutive hops decrypt to consecutive counters, so a
  /// reordered list does not solve.
  final List<int> hops;

  final SeedManufacturer manufacturer;

  /// Hertz, from the capture. Absent rather than defaulted: a `.sub` written
  /// with the wrong frequency transmits into the void, and guessing 433.92 for
  /// a Genius remote that was captured at 868.35 is exactly that.
  final int? frequencyHz;

  /// Whether this capture carries enough hops for the engine to accept it.
  bool get isSolvable => hops.length >= minHops;

  /// Matches `FAACCRACK_MIN_HOPS` and `FAACCRACK_MAX_HOPS` in the native
  /// header. Checked here so the two user-fixable cases - a capture with one
  /// press, or one left collecting through more than the engine takes - are
  /// explained in words rather than reaching the engine as `badArguments`,
  /// which is a fault in this app.
  static const minHops = 2;
  static const maxHops = 16;
}

/// How a recovery ended.
///
/// One member per native status, plus the two this side adds. The native codes
/// are `enum faaccrack_status` in `lib/modules/cpp/faaccrack/faaccrack.h`; the
/// mapping lives in `faaccrack_recoverer.dart` and a test pins it, because
/// nothing derives one from the other.
enum SeedOutcome {
  /// A seed came back and the rebuilt frame reproduced the capture. The only
  /// outcome under which a `.sub` may be written.
  found,

  /// A seed came back, but re-encrypting the rebuilt frame did not reproduce
  /// the last captured hop - so the plaintext layout was wrong for this
  /// protocol. The seed is worth showing; the file is not writable.
  unverified,

  /// The whole space was swept and nothing matched.
  ///
  /// **Not a verdict on the remote.** For a supported manufacturer with hops
  /// that really are consecutive, a seed exists and an exhaustive sweep finds
  /// it - so this means the brand is one this build has no key for, the wrong
  /// one was chosen, the hops came from two remotes, or a press was missed.
  /// Deliberately not named `noSeed`: the hardnested recoverer's equivalent is
  /// documented as "an answer about the card", which is true there and would
  /// send a user away from a capture they could fix here.
  nothingMatched,

  /// Stopped because the caller asked.
  stopped,

  /// Another search is already running. One at a time, for the whole library.
  engineBusy,

  /// The engine's own startup checks failed, which is a fault in this build
  /// rather than anything about the remote - a bad regeneration or a
  /// miscompiled per-instruction-set object. The feature is broken until it is
  /// fixed, so a retry is pointless.
  engineSelfTestFailed,

  /// The native library did not load, or an entry point is missing from it.
  ///
  /// A packaging fault rather than anything about the remote or this capture,
  /// and distinct from [engineFault] because the thing to do about it is
  /// different: nothing the user does will help, and it means the build shipped
  /// without a component. It has happened here before - the Apple builds once
  /// shipped with the MIFARE bridges dead-stripped out.
  engineUnavailable,

  /// The engine refused the arguments, or answered something this build does
  /// not know. Its own fault rather than the capture's, and said that way.
  engineFault,
}

/// A recovered remote, or the reason there isn't one.
///
/// `outcome` is never null, so the switch that consumes it is exhaustive and a
/// new outcome is a compile error rather than falling into "nothing matched".
typedef SeedResult = ({
  SeedOutcome outcome,

  /// The recovered seed, present for [SeedOutcome.found] and
  /// [SeedOutcome.unverified] and null otherwise.
  int? seed,

  /// The 64-bit key the seed derives. Diagnostic.
  int? lrkey,

  /// The counter inside the last decrypted hop.
  int? counter,

  /// The rolling half of the rebuilt frame, which is what a `.sub` carries.
  /// Only meaningful - and only written - when the outcome is
  /// [SeedOutcome.found].
  int? frameHop,

  /// How many hops backed the answer. Fewer than [seedHopsConfident] means a
  /// false positive is conceivable and the UI should say so.
  int? hopsUsed,
});

/// Matches `FAACCRACK_HOPS_CONFIDENT`. With two hops a false positive over the
/// whole space is conceivable; three put it near 1e-7. One spelling on this
/// side too, so the page and the file writer cannot draw the line differently.
const seedHopsConfident = 3;

/// A result with nothing in it but a reason.
///
/// One spelling: the controller, the recoverer and the tests each had their own
/// copy of this record literal, so a field added to [SeedResult] cost six edits
/// and a missed one was a compile error in a different file each time.
SeedResult seedResult(
  SeedOutcome outcome, {
  int? seed,
  int? lrkey,
  int? counter,
  int? frameHop,
  int? hopsUsed,
}) => (
  outcome: outcome,
  seed: seed,
  lrkey: lrkey,
  counter: counter,
  frameHop: frameHop,
  hopsUsed: hopsUsed,
);

/// A fixed-width upper-case hex word, the way frames are written everywhere in
/// this feature - the page, the file name and the `.sub` itself.
String seedHex(int value, int digits) =>
    value.toRadixString(16).toUpperCase().padLeft(digits, '0');
