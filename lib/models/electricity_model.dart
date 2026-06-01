class ElectricityArea {
  final String id;
  final String name;

  ElectricityArea({required this.id, required this.name});

  factory ElectricityArea.fromJson(Map<String, dynamic> json) {
    final name = (json['xiaoqu'] ?? json['schoolname'] ?? json['schoolid'] ?? '').toString();
    return ElectricityArea(
      id: name,
      name: name,
    );
  }
}

class ElectricityBuilding {
  final String id;
  final String name;

  ElectricityBuilding({required this.id, required this.name});

  factory ElectricityBuilding.fromJson(Map<String, dynamic> json) {
    final name =
        (json['buildingname'] ?? json['buildname'] ?? json['buildingid'] ?? json['buildid'] ?? '').toString();
    final id = (json['buildingid'] ?? json['buildid'] ?? name).toString();
    return ElectricityBuilding(
      id: id,
      name: name,
    );
  }
}

class ElectricityRoom {
  final String id;
  final String name;
  final String mertype;

  ElectricityRoom({required this.id, required this.name, required this.mertype});

  factory ElectricityRoom.fromJson(Map<String, dynamic> json) {
    final name = (json['roomname'] ?? json['roomid'] ?? '').toString();
    final id = (json['roomid'] ?? name).toString();
    final mertype = (json['mertype'] ?? 'yk').toString();
    return ElectricityRoom(
      id: id,
      name: name,
      mertype: mertype,
    );
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
