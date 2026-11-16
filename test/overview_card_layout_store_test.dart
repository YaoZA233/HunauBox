import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_hunan_agri/services/overview_card_layout_store.dart';

List<String> encode(List<OverviewCardSlot> layout) => [
  for (final slot in layout) slot.encode(),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const layoutKey = 'overview_card_layout';
  const legacyKey = 'overview_card_order';
  const expectedDefaults = <String>[
    'notice|small',
    'homework|small',
    'upcoming_homework|large',
    'exam|large',
    'campus_card|large',
    'recent_bill|large',
    'electricity_1|large',
    'electricity_2|large',
    'chaoxing_messages|small',
    'chaoxing_courses|small',
  ];

  group('OverviewCardLayoutStore persistence failures', () {
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    late bool throwOnWrite;

    setUp(() {
      SharedPreferences.resetStatic();
      throwOnWrite = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'getAll':
                return <String, Object>{};
              case 'setStringList':
                if (throwOnWrite) {
                  throw PlatformException(code: 'write_failed');
                }
                return false;
              default:
                throw MissingPluginException(call.method);
            }
          });
    });

    tearDown(() {
      SharedPreferences.resetStatic();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('save throws when persistence returns false', () async {
      await expectLater(
        const OverviewCardLayoutStore().save(
          OverviewCardLayoutStore.defaultLayout,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('save propagates persistence exceptions', () async {
      throwOnWrite = true;

      await expectLater(
        const OverviewCardLayoutStore().save(
          OverviewCardLayoutStore.defaultLayout,
        ),
        throwsA(isA<PlatformException>()),
      );
    });

    for (final throwsException in [false, true]) {
      test(
        'failed save restores cached layout, exception=$throwsException',
        () async {
          throwOnWrite = throwsException;
          final previous = await const OverviewCardLayoutStore().load();
          await expectLater(
            const OverviewCardLayoutStore().save(previous.reversed.toList()),
            throwsA(
              throwsException ? isA<PlatformException>() : isA<StateError>(),
            ),
          );
          expect(
            encode(await const OverviewCardLayoutStore().load()),
            encode(previous),
          );
        },
      );
    }
  });

  group('OverviewCardLayoutStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('adds new cards once and respects later removal', () async {
      SharedPreferences.setMockInitialValues({
        layoutKey: <String>['notice|large', 'campus_card|small'],
      });
      const store = OverviewCardLayoutStore();
      final migrated = await store.load();
      expect(encode(migrated), [
        'notice|large',
        'campus_card|small',
        'chaoxing_messages|small',
        'chaoxing_courses|small',
      ]);
      await store.save(
        migrated.where((s) => s.cardId != 'chaoxing_messages').toList(),
      );
      expect(encode(await store.load()), [
        'notice|large',
        'campus_card|small',
        'chaoxing_courses|small',
      ]);
    });

    test('load returns the mixed default layout when unset', () async {
      expect(
        encode(await const OverviewCardLayoutStore().load()),
        expectedDefaults,
      );
      expect(encode(OverviewCardLayoutStore.defaultLayout), expectedDefaults);
    });

    test(
      'customized layout with a duplicated card persists across instances',
      () async {
        final customized = [
          OverviewCardSlot(
            cardId: 'electricity_2',
            size: OverviewCardSize.small,
          ),
          OverviewCardSlot(cardId: 'campus_card', size: OverviewCardSize.large),
          OverviewCardSlot(cardId: 'campus_card', size: OverviewCardSize.small),
          OverviewCardSlot(cardId: 'notice', size: OverviewCardSize.large),
        ];

        await const OverviewCardLayoutStore().save(customized);
        final preferences = await SharedPreferences.getInstance();
        await preferences.reload();

        expect(preferences.getStringList(layoutKey), [
          'electricity_2|small',
          'campus_card|large',
          'campus_card|small',
          'notice|large',
        ]);
        expect(encode(await const OverviewCardLayoutStore().load()), [
          'electricity_2|small',
          'campus_card|large',
          'campus_card|small',
          'notice|large',
        ]);
      },
    );

    test('load migrates the legacy order key with default sizes', () async {
      SharedPreferences.setMockInitialValues({
        legacyKey: <String>[
          'campus_card',
          'notice',
          'electricity_1',
          'homework',
          'upcoming_homework',
          'exam',
          'recent_bill',
          'electricity_2',
        ],
      });

      expect(encode(await const OverviewCardLayoutStore().load()), <String>[
        'campus_card|large',
        'notice|small',
        'electricity_1|large',
        'homework|small',
        'upcoming_homework|large',
        'exam|large',
        'recent_bill|large',
        'electricity_2|large',
        'chaoxing_messages|small',
        'chaoxing_courses|small',
      ]);
    });

    test('load prefers the new layout key over the legacy order key', () async {
      SharedPreferences.setMockInitialValues({
        legacyKey: <String>['campus_card', 'notice'],
        layoutKey: <String>['recent_bill|small', 'notice|large'],
      });

      expect(encode(await const OverviewCardLayoutStore().load()), [
        'recent_bill|small',
        'notice|large',
        'chaoxing_messages|small',
        'chaoxing_courses|small',
      ]);
    });

    test('load restores defaults when the legacy order is empty', () async {
      SharedPreferences.setMockInitialValues({legacyKey: <String>[]});

      expect(
        encode(await const OverviewCardLayoutStore().load()),
        expectedDefaults,
      );
    });

    test('load drops unknown cards and malformed encodings', () async {
      SharedPreferences.setMockInitialValues({
        layoutKey: <String>[
          'electricity_1|large',
          'unknown|large',
          'notice',
          'notice|huge',
          '|small',
          'notice|small',
          'campus_card|large',
        ],
      });

      expect(encode(await const OverviewCardLayoutStore().load()), <String>[
        'electricity_1|large',
        'notice|small',
        'campus_card|large',
        'chaoxing_messages|small',
        'chaoxing_courses|small',
      ]);
    });

    test(
      'load restores defaults when every stored encoding is invalid',
      () async {
        SharedPreferences.setMockInitialValues({
          layoutKey: <String>['unknown|large', ''],
        });

        expect(
          encode(await const OverviewCardLayoutStore().load()),
          expectedDefaults,
        );
      },
    );

    test('load keeps an intentionally emptied layout', () async {
      await const OverviewCardLayoutStore().save(const []);

      expect(await const OverviewCardLayoutStore().load(), isEmpty);
    });

    for (final storedValue in <Object>['notice', 42, true, 1.5]) {
      test('load recovers from stored ${storedValue.runtimeType}', () async {
        SharedPreferences.setMockInitialValues({layoutKey: storedValue});

        expect(
          encode(await const OverviewCardLayoutStore().load()),
          expectedDefaults,
        );
      });
    }

    test('save filters unknown slots without mutating the input', () async {
      final slots = [
        OverviewCardSlot(cardId: 'homework', size: OverviewCardSize.large),
        OverviewCardSlot(cardId: 'unknown', size: OverviewCardSize.small),
      ];

      await const OverviewCardLayoutStore().save(slots);
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();

      expect(preferences.getStringList(layoutKey), ['homework|large']);
      expect(slots.length, 2);
      expect(slots[1].cardId, 'unknown');
    });

    test('load returns independent mutable layouts', () async {
      final loaded = await const OverviewCardLayoutStore().load();
      loaded.clear();

      expect(
        encode(await const OverviewCardLayoutStore().load()),
        expectedDefaults,
      );
      expect(encode(OverviewCardLayoutStore.defaultLayout), expectedDefaults);
    });
  });
}
