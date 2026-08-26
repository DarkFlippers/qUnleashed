import 'catalog_api.dart';
import 'models/card.dart';

/// Returns a new list of [cards] in the order [sort] asks for. Cards with no
/// catalog timestamps — the ones that only exist in the release index — keep
/// their own order at the end of a date sort, and join the rest by name when
/// sorting alphabetically.
List<AppCard> sortAppCards(List<AppCard> cards, AppsSort sort) {
  int byName(AppCard a, AppCard b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());

  int byStamp(int a, int b, int order) {
    if (a == b) return 0;
    if (a == 0) return 1;
    if (b == 0) return -1;
    return order * a.compareTo(b);
  }

  final out = [...cards];
  switch (sort) {
    case AppsSort.alphabetical:
      out.sort(byName);
    case AppsSort.newUpdates:
    case AppsSort.oldUpdates:
      out.sort((a, b) => byStamp(a.updatedAt, b.updatedAt, sort.order));
    case AppsSort.newReleases:
    case AppsSort.oldReleases:
      out.sort((a, b) => byStamp(a.createdAt, b.createdAt, sort.order));
  }
  return out;
}
