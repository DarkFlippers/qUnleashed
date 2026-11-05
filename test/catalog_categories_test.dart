import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/apps/data/models/category.dart';

AppCategory cat(
  String id, {
  String? parent,
  int priority = 0,
  String color = '',
}) => AppCategory(
  id: id,
  name: id.split('/').last,
  color: color,
  priority: priority,
  parentId: parent,
);

void main() {
  test('every folder follows its own category', () {
    // The order the server sends: roots, then folders of every root mixed by
    // priority.
    final list = nestCategories([
      cat('nfc', priority: 2, color: '98CEFE'),
      cat('subghz', priority: 0, color: 'A5F4BE'),
      cat('ir', priority: 1, color: 'FE938C'),
      cat('ir/ACs', parent: 'ir', color: 'FE938C'),
      cat('nfc/Access', parent: 'nfc', color: '98CEFE'),
      cat('subghz/Analyzers', parent: 'subghz', color: 'A5F4BE'),
      cat('nfc/Gaming', parent: 'nfc', priority: 1, color: '98CEFE'),
    ]);
    expect(list.map((c) => c.id), [
      'subghz',
      'subghz/Analyzers',
      'ir',
      'ir/ACs',
      'nfc',
      'nfc/Access',
      'nfc/Gaming',
    ]);
  });

  test('a folder without a colour wears its category one', () {
    final list = nestCategories([
      cat('games', color: 'FFC486'),
      cat('games/Arcade', parent: 'games'),
      cat('games/Arcade/Retro', parent: 'games/Arcade'),
    ]);
    expect(list.map((c) => c.color), ['FFC486', 'FFC486', 'FFC486']);
  });

  test('folders of one category go by priority, then name', () {
    final list = nestCategories([
      cat('tools'),
      cat('tools/Timers', parent: 'tools', priority: 1),
      cat('tools/Clocks', parent: 'tools', priority: 1),
      cat('tools/Editors', parent: 'tools'),
    ]);
    expect(list.map((c) => c.id), [
      'tools',
      'tools/Editors',
      'tools/Clocks',
      'tools/Timers',
    ]);
  });

  test('a folder whose category is missing is kept, last', () {
    final list = nestCategories([
      cat('gone/Lost', parent: 'gone'),
      cat('media'),
    ]);
    expect(list.map((c) => c.id), ['media', 'gone/Lost']);
  });
}
