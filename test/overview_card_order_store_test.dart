import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_hunan_agri/services/overview_card_order_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = 'overview_card_order';
  const expectedDefaults = <String>[
    'notice',
    'homework',
    'upcoming_homework',
    'exam',
    'campus_card',
    'recent_bill',
    'electricity_1',
    'electricity_2',
  ];

  group('OverviewCardOrderStore persistence failures', () {
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
        const OverviewCardOrderStore().save(expectedDefaults),
        throwsA(isA<StateError>()),
      );
    });

    test('save propagates persistence exceptions', () async {
      throwOnWrite = true;

      await expectLater(
        const OverviewCardOrderStore().save(expectedDefaults),
        throwsA(isA<PlatformException>()),
      );
    });

    for (final throwsException in [false, true]) {
      test(
        'failed save restores cached order, exception=$throwsException',
        () async {
          throwOnWrite = throwsException;
          final previous = await const OverviewCardOrderStore().load();
          await expectLater(
            const OverviewCardOrderStore().save(
              expectedDefaults.reversed.toList(),
            ),
            throwsA(
              throwsException ? isA<PlatformException>() : isA<StateError>(),
            ),
          );
          expect(await const OverviewCardOrderStore().load(), previous);
        },
      );
    }
  });

  group('OverviewCardOrderStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('load restores the default order when unset', () async {
      expect(await const OverviewCardOrderStore().load(), expectedDefaults);
      expect(OverviewCardOrderStore.defaultOrder, expectedDefaults);
    });

    test('load restores the default order when stored list is empty', () async {
      SharedPreferences.setMockInitialValues({key: <String>[]});

      expect(await const OverviewCardOrderStore().load(), expectedDefaults);
    });

    test('customized order persists across new store instances', () async {
      const customized = <String>[
        'electricity_2',
        'exam',
        'campus_card',
        'recent_bill',
        'notice',
        'electricity_1',
        'upcoming_homework',
        'homework',
      ];

      await OverviewCardOrderStore().save(customized);
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();

      expect(preferences.getStringList(key), customized);
      expect(await OverviewCardOrderStore().load(), customized);
    });

    test(
      'load removes unknown and duplicate ids and appends missing ids',
      () async {
        SharedPreferences.setMockInitialValues({
          key: <String>[
            'electricity_1',
            'unknown',
            'notice',
            'electricity_1',
            'campus_card',
            'notice',
          ],
        });

        expect(await const OverviewCardOrderStore().load(), <String>[
          'electricity_1',
          'notice',
          'campus_card',
          'homework',
          'upcoming_homework',
          'exam',
          'recent_bill',
          'electricity_2',
        ]);
      },
    );

    test('load appends the second electricity card to legacy orders', () async {
      SharedPreferences.setMockInitialValues({
        key: <String>[
          'campus_card',
          'notice',
          'electricity_1',
          'homework',
          'upcoming_homework',
        ],
      });

      expect(await const OverviewCardOrderStore().load(), <String>[
        'campus_card',
        'notice',
        'electricity_1',
        'homework',
        'upcoming_homework',
        'exam',
        'recent_bill',
        'electricity_2',
      ]);
    });

    test(
      'save normalizes ids before persistence without mutating input',
      () async {
        final ids = <String>[
          'electricity_2',
          'unknown',
          'homework',
          'electricity_2',
        ];

        await const OverviewCardOrderStore().save(ids);
        final preferences = await SharedPreferences.getInstance();
        await preferences.reload();

        expect(preferences.getStringList(key), <String>[
          'electricity_2',
          'homework',
          'notice',
          'upcoming_homework',
          'exam',
          'campus_card',
          'recent_bill',
          'electricity_1',
        ]);
        expect(ids, <String>[
          'electricity_2',
          'unknown',
          'homework',
          'electricity_2',
        ]);
      },
    );

    test('save stores defaults for an empty order', () async {
      await const OverviewCardOrderStore().save(<String>[]);
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();

      expect(preferences.getStringList(key), expectedDefaults);
    });

    test('load restores defaults when all stored ids are unknown', () async {
      SharedPreferences.setMockInitialValues({
        key: <String>['unknown', ''],
      });

      expect(await const OverviewCardOrderStore().load(), expectedDefaults);
    });

    for (final storedValue in <Object>['notice', 42, true, 1.5]) {
      test('load recovers from stored ${storedValue.runtimeType}', () async {
        SharedPreferences.setMockInitialValues({key: storedValue});

        expect(await const OverviewCardOrderStore().load(), expectedDefaults);
      });
    }

    test('load returns independent default lists', () async {
      final loaded = await const OverviewCardOrderStore().load();
      loaded.clear();

      expect(await const OverviewCardOrderStore().load(), expectedDefaults);
      expect(OverviewCardOrderStore.defaultOrder, expectedDefaults);
    });
  });
}
