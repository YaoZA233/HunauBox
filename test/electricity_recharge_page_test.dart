import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_hunan_agri/models/electricity_model.dart';
import 'package:smart_hunan_agri/pages/electricity_recharge_page.dart';
import 'package:smart_hunan_agri/services/electricity_service.dart';

const _originalRoom = SavedElectricityRoom(
  areaName: '芷兰',
  buildingName: '1栋',
  roomId: '101',
  roomName: '101室',
  mertype: 'yk',
);
const _secondRoom = SavedElectricityRoom(
  areaName: '芷兰',
  buildingName: '1栋',
  roomId: '202',
  roomName: '202室',
  mertype: 'yk',
);

class RoomSelectionService implements ElectricityService {
  int areaCalls = 0;
  bool failBalance = false;
  Future<List<ElectricityRoom>>? delayedRooms;
  Completer<void>? pendingSave;

  @override
  Future<SavedElectricityRoom?> getSavedRoom({int slot = 0}) =>
      ElectricityService.instance.getSavedRoom(slot: slot);

  @override
  Future<void> saveSavedRoom(SavedElectricityRoom room, {int slot = 0}) async {
    if (pendingSave != null) await pendingSave!.future;
    await ElectricityService.instance.saveSavedRoom(room, slot: slot);
  }

  @override
  Future<List<ElectricityArea>> getAreas() async {
    areaCalls++;
    return [ElectricityArea(id: '芷兰', name: '芷兰')];
  }

  @override
  Future<List<ElectricityBuilding>> getBuildings(String areaName) async => [
    ElectricityBuilding(id: '1栋', name: '1栋'),
  ];

  @override
  Future<List<ElectricityRoom>> getRooms(
    String areaName,
    String buildingName,
  ) async => delayedRooms ?? availableRooms;

  static final availableRooms = [
    ElectricityRoom(id: '101', name: '101室', mertype: 'yk'),
    ElectricityRoom(id: '202', name: '202室', mertype: 'yk'),
  ];

  @override
  Future<ElectricityBalanceInfo> getBalance({
    required String areaName,
    required String buildingName,
    required String roomId,
    required String mertype,
  }) async {
    if (failBalance) throw Exception('服务暂不可用');
    return ElectricityBalanceInfo(balance: roomId == '202' ? '28.00' : '10.00');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<GlobalKey<NavigatorState>> openRoomPage(
  WidgetTester tester,
  RoomSelectionService service,
) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Text('概览')),
    ),
  );
  navigatorKey.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => ElectricityRechargePage(roomSlot: 1, service: service),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  return navigatorKey;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({'user': 'student'}));
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'saved_electricity_room': jsonEncode(_originalRoom.toJson()),
    }),
  );
  test('existing callers default to the original room slot', () {
    expect(const ElectricityRechargePage().roomSlot, 0);
  });

  test('the second overview entry can select its own room slot', () {
    expect(const ElectricityRechargePage(roomSlot: 1).roomSlot, 1);
  });

  testWidgets('第二槽位恢复自己的房间，切换房间不改动第一槽位', (tester) async {
    await ElectricityService.instance.saveSavedRoom(_secondRoom, slot: 1);
    final service = RoomSelectionService();
    await openRoomPage(tester, service);
    await tester.pumpAndSettle();
    expect(find.text('28.00 元'), findsOneWidget);
    expect(service.areaCalls, 0);
    await tester.tap(find.text('更换房间'));
    await tester.pumpAndSettle();
    expect(service.areaCalls, 1);
    final roomDropdown = find.byType(DropdownButtonFormField<String>).last;
    await tester.ensureVisible(roomDropdown);
    await tester.pumpAndSettle();
    await tester.tap(roomDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('101室').last);
    await tester.pumpAndSettle();
    expect(
      (await ElectricityService.instance.getSavedRoom(slot: 1))?.roomId,
      '101',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('saved_electricity_room'),
      jsonEncode(_originalRoom.toJson()),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('刷新失败仍保留同一宿舍的余额并提示缓存状态', (tester) async {
    await ElectricityService.instance.saveSavedRoom(_secondRoom, slot: 1);
    final service = RoomSelectionService();
    await openRoomPage(tester, service);
    await tester.pumpAndSettle();
    service.failBalance = true;
    await tester.tap(find.byTooltip('刷新余额'));
    await tester.pumpAndSettle();
    expect(find.text('28.00 元'), findsOneWidget);
    expect(find.text('更新失败，显示上次余额'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final afterDisposal in [false, true]) {
    testWidgets('返回后到达的房间列表不再保存选择，已销毁=$afterDisposal', (tester) async {
      final rooms = Completer<List<ElectricityRoom>>();
      final service = RoomSelectionService()..delayedRooms = rooms.future;
      final navigator = await openRoomPage(tester, service);
      await navigator.currentState!.maybePop();
      if (afterDisposal) await tester.pumpAndSettle();
      rooms.complete(RoomSelectionService.availableRooms);
      await tester.pumpAndSettle();
      expect(find.text('概览'), findsOneWidget);
      expect(await ElectricityService.instance.getSavedRoom(slot: 1), isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('返回会等第二槽位的当前保存完成', (tester) async {
    final save = Completer<void>();
    final service = RoomSelectionService()..pendingSave = save;
    final navigator = await openRoomPage(tester, service);
    await navigator.currentState!.maybePop();
    await tester.pump();
    expect(find.byType(ElectricityRechargePage), findsOneWidget);
    expect(await ElectricityService.instance.getSavedRoom(slot: 1), isNull);
    save.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ElectricityRechargePage), findsNothing);
    expect(
      (await ElectricityService.instance.getSavedRoom(slot: 1))?.roomId,
      '101',
    );
    expect(tester.takeException(), isNull);
  });

  for (final slot in [-1, 2]) {
    test('unsupported room slot $slot is rejected before opening the page', () {
      expect(
        () => ElectricityRechargePage(roomSlot: slot),
        throwsAssertionError,
      );
    });
  }
}
