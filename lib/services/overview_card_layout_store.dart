import 'package:shared_preferences/shared_preferences.dart';

/// 概览卡片尺寸：大卡独占整行，小卡可两两并排。
enum OverviewCardSize { large, small }

/// 概览布局中的一个卡片实例（同一内容可以出现多次，尺寸可不同）。
class OverviewCardSlot {
  const OverviewCardSlot({required this.cardId, required this.size});

  final String cardId;
  final OverviewCardSize size;

  String encode() => '$cardId|${size.name}';

  static OverviewCardSlot? decode(String raw) {
    final separator = raw.lastIndexOf('|');
    if (separator <= 0 || separator == raw.length - 1) return null;
    final cardId = raw.substring(0, separator);
    if (!OverviewCardLayoutStore.knownCardIds.contains(cardId)) return null;
    final size = switch (raw.substring(separator + 1)) {
      'large' => OverviewCardSize.large,
      'small' => OverviewCardSize.small,
      _ => null,
    };
    return size == null ? null : OverviewCardSlot(cardId: cardId, size: size);
  }
}

class OverviewCardLayoutStore {
  const OverviewCardLayoutStore();

  static const String key = 'overview_card_layout';
  static const String legacyOrderKey = 'overview_card_order';
  static const String chaoxingMigrationKey = 'overview_chaoxing_cards_added_v1';

  static const List<String> knownCardIds = [
    'notice',
    'homework',
    'upcoming_homework',
    'exam',
    'campus_card',
    'recent_bill',
    'electricity_1',
    'electricity_2',
    'chaoxing_messages',
    'chaoxing_courses',
  ];

  static const Map<String, OverviewCardSize> defaultSizes = {
    'notice': OverviewCardSize.small,
    'homework': OverviewCardSize.small,
    'chaoxing_messages': OverviewCardSize.small,
    'chaoxing_courses': OverviewCardSize.small,
    'upcoming_homework': OverviewCardSize.large,
    'exam': OverviewCardSize.large,
    'campus_card': OverviewCardSize.large,
    'recent_bill': OverviewCardSize.large,
    'electricity_1': OverviewCardSize.large,
    'electricity_2': OverviewCardSize.large,
  };

  static List<OverviewCardSlot> get defaultLayout => [
    for (final id in knownCardIds)
      OverviewCardSlot(cardId: id, size: defaultSizes[id]!),
  ];

  Future<List<OverviewCardSlot>> load() async {
    final preferences = await SharedPreferences.getInstance();
    try {
      final encoded = preferences.getStringList(key);
      if (encoded != null) {
        final layout = encoded
            .map(OverviewCardSlot.decode)
            .whereType<OverviewCardSlot>()
            .toList();
        return _addNewCards(
          preferences,
          layout.isEmpty && encoded.isNotEmpty ? defaultLayout : layout,
        );
      }
      final legacy = _migrateLegacyOrder(preferences);
      return legacy == null ? defaultLayout : _addNewCards(preferences, legacy);
    } on TypeError {
      return defaultLayout;
    }
  }

  Future<List<OverviewCardSlot>> _addNewCards(
    SharedPreferences preferences,
    List<OverviewCardSlot> layout,
  ) async {
    if (layout.isEmpty || preferences.getBool(chaoxingMigrationKey) == true) {
      return layout;
    }
    final ids = layout.map((slot) => slot.cardId).toSet();
    final next = [
      ...layout,
      for (final id in ['chaoxing_messages', 'chaoxing_courses'])
        if (!ids.contains(id))
          OverviewCardSlot(cardId: id, size: defaultSizes[id]!),
    ];
    try {
      if (await preferences.setStringList(
        key,
        next.map((slot) => slot.encode()).toList(),
      )) {
        await preferences.setBool(chaoxingMigrationKey, true);
      }
    } catch (_) {
      /* Retry the migration the next time the layout is read. */
    }
    return next;
  }

  Future<void> save(List<OverviewCardSlot> layout) async {
    final preferences = await SharedPreferences.getInstance();
    try {
      final saved = await preferences.setStringList(key, [
        for (final slot in layout)
          if (knownCardIds.contains(slot.cardId)) slot.encode(),
      ]);
      if (!saved) {
        throw StateError('Failed to persist overview card layout.');
      }
      await preferences.setBool(chaoxingMigrationKey, true);
    } catch (_) {
      await preferences.reload();
      rethrow;
    }
  }

  /// 旧版本只保存卡片顺序，迁移时按当前默认尺寸补齐。
  static List<OverviewCardSlot>? _migrateLegacyOrder(
    SharedPreferences preferences,
  ) {
    try {
      final ids = preferences.getStringList(legacyOrderKey);
      if (ids == null) return null;
      final unique = <String>{...ids.where(knownCardIds.contains)};
      if (unique.isEmpty) return null;
      return [
        for (final id in unique)
          OverviewCardSlot(cardId: id, size: defaultSizes[id]!),
      ];
    } on TypeError {
      return null;
    }
  }
}
