class ElectricityArea {
  final String id;
  final String name;

  ElectricityArea({required this.id, required this.name});

  factory ElectricityArea.fromJson(Map<String, dynamic> json) {
    final name =
        (json['xiaoqu'] ?? json['schoolname'] ?? json['schoolid'] ?? '')
            .toString();
    return ElectricityArea(id: name, name: name);
  }
}

class ElectricityBuilding {
  final String id;
  final String name;

  ElectricityBuilding({required this.id, required this.name});

  factory ElectricityBuilding.fromJson(Map<String, dynamic> json) {
    final name =
        (json['buildingname'] ??
                json['buildname'] ??
                json['buildingid'] ??
                json['buildid'] ??
                '')
            .toString();
    final id = (json['buildingid'] ?? json['buildid'] ?? name).toString();
    return ElectricityBuilding(id: id, name: name);
  }
}

class ElectricityRoom {
  final String id;
  final String name;
  final String mertype;

  ElectricityRoom({
    required this.id,
    required this.name,
    required this.mertype,
  });

  factory ElectricityRoom.fromJson(Map<String, dynamic> json) {
    final name = (json['roomname'] ?? json['roomid'] ?? '').toString();
    final id = (json['roomid'] ?? name).toString();
    final mertype = (json['mertype'] ?? 'yk').toString();
    return ElectricityRoom(id: id, name: name, mertype: mertype);
  }
}

class ElectricityBalanceInfo {
  final String balance;
  final String? detail;

  ElectricityBalanceInfo({required this.balance, this.detail});

  factory ElectricityBalanceInfo.fromJson(Map<String, dynamic> json) {
    return ElectricityBalanceInfo(
      balance: (json['balance'] ?? json['elebalance'] ?? '0.00').toString(),
      detail: json['eleaccdetail']?.toString(),
    );
  }
}

/// 上次使用的电费房间，用于下次进入页面时自动恢复。
class SavedElectricityRoom {
  final String areaName;
  final String buildingName;
  final String roomId;
  final String roomName;
  final String mertype;

  const SavedElectricityRoom({
    required this.areaName,
    required this.buildingName,
    required this.roomId,
    required this.roomName,
    required this.mertype,
  });

  Map<String, dynamic> toJson() => {
    'areaName': areaName,
    'buildingName': buildingName,
    'roomId': roomId,
    'roomName': roomName,
    'mertype': mertype,
  };

  factory SavedElectricityRoom.fromJson(Map<String, dynamic> json) {
    return SavedElectricityRoom(
      areaName: (json['areaName'] ?? '').toString(),
      buildingName: (json['buildingName'] ?? '').toString(),
      roomId: (json['roomId'] ?? '').toString(),
      roomName: (json['roomName'] ?? json['roomId'] ?? '').toString(),
      mertype: (json['mertype'] ?? 'yk').toString(),
    );
  }
}
