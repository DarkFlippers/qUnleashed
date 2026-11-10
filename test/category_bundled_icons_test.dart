import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/apps/data/categories.dart';
import 'package:qunleashed/pages/apps/data/models/category.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'another family\'s id for a known category still finds its icon',
    () async {
      // CLI sends `games`, apps send the ObjectId; both are Games.
      final out = await CategoryRegistry.instance.withBundledIcons([
        AppCategory(id: 'games', name: 'Games', color: 'FFC486'),
        AppCategory(id: 'games-arcade', name: 'Arcade', color: 'FFC486'),
        AppCategory(id: 'theme', name: 'Themes', color: 'EBEBEB'),
      ]);
      expect(out[0].iconAsset, 'assets/ic/appcat/games.svg');
      expect(out[1].iconAsset, isNull);
      expect(out[2].iconAsset, isNull);
    },
  );
}
