import 'package:shared_preferences/shared_preferences.dart';

class OverviewCardOrderStore {
  const OverviewCardOrderStore();

  static const List<String> defaultOrder = [
    'notice',
    'homework',
    'upcoming_homework',
    'exam',
    'campus_card',
    'recent_bill',
    'electricity_1',
    'electricity_2',
  ];

  static const String _key = 'overview_card_order';

  Future<List<String>> load() async {
    final preferences = await SharedPreferences.getInstance();
    try {
      return _normalize(preferences.getStringList(_key) ?? const <String>[]);
    } on TypeError {
      return List<String>.of(defaultOrder);
    }
  }

  Future<void> save(List<String> ids) async {
    final preferences = await SharedPreferences.getInstance();
    try {
      final saved = await preferences.setStringList(_key, _normalize(ids));
      if (!saved) {
        throw StateError('Failed to persist overview card order.');
      }
    } catch (_) {
      await preferences.reload();
      rethrow;
    }
  }

  static List<String> _normalize(List<String> ids) {
    return <String>{
      ...ids.where(defaultOrder.contains),
      ...defaultOrder,
    }.toList();
  }
}
