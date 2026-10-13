import '../logging.dart';
import '../prefs_reader.dart';
import '../settings/persist.dart';
import '../settings/store.dart';

/// How the archive's file lists are ordered, remembered across launches.
///
/// Held once for every archive table rather than per category. A user who
/// copies Flipper-IRDB onto the Flipper wants the folder grouping wherever
/// the folders are deep (#122), and picking it again in each of the eight
/// categories is the annoyance the issue is about, one level up.
///
/// Not a `static final instance`. The three pages that read it are handed it
/// by [AppShell], which owns it beside the archive controller. ADR 0002.
class ArchiveSortSettings extends PrefsBackedSettings {
  /// One preference holding `<key>:asc` or `<key>:desc`, rather than a key
  /// and a direction side by side.
  ///
  /// The two cannot be written together. `persistSetting` never throws, so a
  /// pair of calls is a pair of independent failures: the field lands, the
  /// direction does not, and the next launch opens on a sort the user has
  /// never picked - name ascending turned into folder *descending*, which on
  /// a 10k-entry Flipper-IRDB is the whole list upside down. The log would
  /// name only the half that failed. One value lands or it does not.
  static const String _pref = 'archive.sort';

  /// Named so [resetFields] and [resolve]'s fallback cannot drift from the
  /// initialisers. Every table offers this one, which is what makes it safe
  /// as the fallback for a key some table does not.
  ///
  /// `_SortBtn._active` still spells the literal out: the toolbar sits below
  /// this in the layering and does not import it.
  static const String defaultKey = 'name';
  static const bool defaultAsc = true;

  String _key = defaultKey;
  bool _asc = defaultAsc;

  /// Whether the user has picked a sort since this store was built.
  ///
  /// `load()` is started by `AppShell` and is a platform round trip, so a
  /// pick can happen while it is still out. Without this the read's
  /// continuation runs second and puts the stored pair back: the table snaps
  /// out of the order the user just chose, and their pick - which did reach
  /// the disk - turns up at the *next* launch instead. Narrow window, but it
  /// costs the user the one interaction this whole store exists to keep.
  bool _picked = false;

  String get key => _key;
  bool get asc => _asc;

  /// The stored sort, held to what the table asking for it can actually do.
  ///
  /// The sort keys are not the same everywhere, and no table's set contains
  /// another's: `uid` is NFC's, `frequency` belongs to SubGHz, infrared has
  /// no size column, and the `protocol` the deleted and favourites tables
  /// offer is SubGHz's alone among the categories - NFC and rfid call theirs
  /// `type`, infrared `protocols`. Only `folder` and `name` are on every
  /// table, so the fallback runs in both directions: out of a category into
  /// Deleted as readily as back.
  ///
  /// Handing a table a key it does not offer does not
  /// throw - `sortArchiveKeys` falls through to ordering by name - but the
  /// screen then lies about it twice over: the sort pill lights up, and no row
  /// in its sheet is marked. So the fallback happens here, where both the
  /// ordering and what the controls say are decided from one answer.
  ///
  /// The stored key is left alone, so returning to the category it belongs to
  /// brings it back. It also covers the key that was valid when it was written
  /// and is not after an update.
  ({String key, bool asc}) resolve(Iterable<String> offered) =>
      offered.contains(_key)
      ? (key: _key, asc: _asc)
      : (key: defaultKey, asc: defaultAsc);

  @override
  void readFrom(PrefsReader reader) {
    final stored = reader.orNull<String>(_pref);

    // A rejected value is a list that comes back in an order the user did not
    // leave it in, with nothing on screen saying why.
    reader.report('[ArchiveSort]');

    // A pick that beat the read keeps the screen. It is already on its way to
    // the disk, so putting the old pair back here would lose it twice over.
    if (_picked) return;

    final parsed = _parse(stored);
    if (parsed == null) return;
    _key = parsed.key;
    _asc = parsed.asc;
  }

  /// Reads back what [setSort] wrote, or null for anything else.
  ///
  /// Anything that does not split into a key and a direction leaves the
  /// defaults, which is what a missing value does too. Nothing but [setSort]
  /// writes this preference, so a shape that does not parse means the store
  /// was edited by hand or written by a build that is no longer installed -
  /// and either way it costs one re-pick, the same as having nothing stored.
  /// ADR 0005.
  ///
  /// Splits at the *last* colon, so a sort key that ever contains one still
  /// reads back.
  static ({String key, bool asc})? _parse(String? stored) {
    if (stored == null) return null;
    final cut = stored.lastIndexOf(':');
    if (cut <= 0) return null;
    final direction = stored.substring(cut + 1);
    if (direction != 'asc' && direction != 'desc') return null;
    return (key: stored.substring(0, cut), asc: direction == 'asc');
  }

  /// Losing this costs one re-pick of a sort, so it is a line and not a
  /// notice.
  ///
  /// `warn` and not `caught`, which is also kept and would read as the better
  /// fit: `services/archive` is not in `test/caught_budget_test.dart`'s map,
  /// and an unlisted area is allowed none, so `caught` here is a red suite
  /// and a budget raised for a log line. The four sibling stores all write
  /// this same line at `warn`.
  @override
  void onLoadFailed(Object error, StackTrace stack) {
    LogService.warn(
      '[ArchiveSort] load failed: ${LogService.describe(error, stack)}',
    );
  }

  @override
  void resetFields() {
    _key = defaultKey;
    _asc = defaultAsc;
    _picked = false;
  }

  /// Applies a sort the user picked from a column header or the sort sheet:
  /// a new key starts ascending, the key already in force turns around.
  ///
  /// [offered] is the asking table's own keys, so "already in force" means
  /// the sort that table is showing rather than the one on disk. The two
  /// differ exactly when [resolve] has stood something in: with a stored
  /// `uid` the deleted table is showing name ascending, and a tap on its name
  /// header has to turn that around. Compared against the raw `uid` the tap
  /// would count as a new key, set name ascending - already on screen - and
  /// the header would read as dead.
  ///
  /// The rule lives here rather than in each page because all three had the
  /// same ten lines of it, and the sort sheet and the column header both go
  /// through it - two surfaces that must agree on what a second tap means.
  Future<void> pick(String key, {required Iterable<String> offered}) {
    final current = resolve(offered);
    return setSort(key, asc: current.key == key ? !current.asc : true);
  }

  Future<void> setSort(String key, {required bool asc}) async {
    // Set before the early return, so a pick that only re-states what is
    // already in force still holds off a read that has not landed yet.
    _picked = true;
    if (_key == key && _asc == asc) return;
    _key = key;
    _asc = asc;
    notifyListeners();
    final value = '$key:${asc ? 'asc' : 'desc'}';
    await persistSetting(_pref, (prefs) => prefs.setString(_pref, value));
  }
}
