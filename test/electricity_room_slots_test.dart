import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_hunan_agri/models/electricity_model.dart';
import 'package:smart_hunan_agri/services/electricity_service.dart';

const _originalRecord =
    '{"areaName":"芷兰","buildingName":"一栋","roomId":"101",'
    '"roomName":"101室","mertype":"yk"}';
const _secondRecord =
    '{"areaName":"金岸","buildingName":"二栋","roomId":"202",'
    '"roomName":"202室","mertype":"dk"}';
const _secondRoom = SavedElectricityRoom(
  areaName: '金岸',
  buildingName: '二栋',
  roomId: '202',
  roomName: '202室',
  mertype: 'dk',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = ElectricityService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'saved_electricity_room': _originalRecord,
    });
  });

  test(
    'legacy saved room remains available through default and explicit slot 0',
    () async {
      final SavedElectricityRoom? original = await service.getSavedRoom();
      final SavedElectricityRoom? explicit = await service.getSavedRoom(
        slot: 0,
      );
      expect(original?.toJson(), {
        'areaName': '芷兰',
        'buildingName': '一栋',
        'roomId': '101',
        'roomName': '101室',
        'mertype': 'yk',
      });
      expect(explicit?.roomId, '101');
    },
  );

  test('slot 1 starts empty rather than restoring the legacy room', () async {
    expect(await service.getSavedRoom(slot: 1), isNull);
  });

  test('two persisted rooms restore independently', () async {
    SharedPreferences.setMockInitialValues({
      'saved_electricity_room': _originalRecord,
      'saved_electricity_room_2': _secondRecord,
    });
    final SavedElectricityRoom? first = await service.getSavedRoom(slot: 0);
    final SavedElectricityRoom? second = await service.getSavedRoom(slot: 1);
    expect(first?.roomId, '101');
    expect(second?.toJson(), {
      'areaName': '金岸',
      'buildingName': '二栋',
      'roomId': '202',
      'roomName': '202室',
      'mertype': 'dk',
    });
  });

  test('saving slot 1 preserves the original record byte for byte', () async {
    await service.saveSavedRoom(_secondRoom, slot: 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('saved_electricity_room'), _originalRecord);
    expect(prefs.getString('saved_electricity_room_2'), _secondRecord);
  });

  test('clearing slot 1 never removes slot 0', () async {
    SharedPreferences.setMockInitialValues({
      'saved_electricity_room': _originalRecord,
      'saved_electricity_room_2': _secondRecord,
    });
    await service.clearSavedRoom(slot: 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('saved_electricity_room'), _originalRecord);
    expect(prefs.containsKey('saved_electricity_room_2'), isFalse);
  });

  test('default save and clear still address only slot 0', () async {
    SharedPreferences.setMockInitialValues({
      'saved_electricity_room_2': _originalRecord,
    });
    await service.saveSavedRoom(_secondRoom);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('saved_electricity_room'), _secondRecord);
    expect(prefs.getString('saved_electricity_room_2'), _originalRecord);
    await service.clearSavedRoom();
    expect(prefs.containsKey('saved_electricity_room'), isFalse);
    expect(prefs.getString('saved_electricity_room_2'), _originalRecord);
  });

  for (final amount in [0.0, 1001.0, 1.5]) {
    test(
      'slot 1 recharge rejects invalid amount $amount without changing saved rooms',
      () async {
        await expectLater(
          service.recharge(
            areaName: '金岸',
            buildingName: '二栋',
            roomId: '202',
            roomName: '202室',
            mertype: 'dk',
            amount: amount,
            roomSlot: 1,
          ),
          throwsA(
            isA<Exception>().having(
              (error) => error.toString(),
              'message',
              contains('充值金额必须是 1–1000 元的整数'),
            ),
          ),
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('saved_electricity_room'), _originalRecord);
        expect(prefs.containsKey('saved_electricity_room_2'), isFalse);
      },
    );
  }

  for (final malformed in ['{bad json', '[]', 'null', '']) {
    test(
      'bad JSON "$malformed" in slot 1 is ignored without damaging slot 0',
      () async {
        SharedPreferences.setMockInitialValues({
          'saved_electricity_room': _originalRecord,
          'saved_electricity_room_2': malformed,
        });
        expect(await service.getSavedRoom(slot: 1), isNull);
        final SavedElectricityRoom? first = await service.getSavedRoom();
        expect(first?.roomId, '101');
      },
    );
  }
}
