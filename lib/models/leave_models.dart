class LeaveRecord {
  final String id, typeName, startTime, endTime, reason, auditStatus, auditStatusName, auditResultName;
  final int days, hours;
  const LeaveRecord({required this.id, required this.typeName, required this.startTime, required this.endTime, this.reason = '', this.auditStatus = '', this.auditStatusName = '', this.auditResultName = '', this.days = 0, this.hours = 0});
  factory LeaveRecord.fromJson(Map<String, dynamic> j) => LeaveRecord(id: '${j['ID'] ?? ''}', typeName: '${j['LXMC'] ?? ''}', startTime: '${j['KSSJ'] ?? ''}', endTime: '${j['JSSJ'] ?? ''}', reason: '${j['QJSY'] ?? ''}', auditStatus: '${j['SHZT'] ?? ''}', auditStatusName: '${j['SHZTMC'] ?? ''}', auditResultName: '${j['SHJGMC'] ?? ''}', days: int.tryParse('${j['TS'] ?? 0}') ?? 0, hours: int.tryParse('${j['HOUR'] ?? 0}') ?? 0);
  String get statusLabel => auditStatusName.isNotEmpty ? (auditStatus == '9' && auditResultName.isNotEmpty ? '$auditStatusName·$auditResultName' : auditStatusName) : {'0': '待审核', '8': '审核中', '9': '已审核'}.containsKey(auditStatus) ? '${{'0': '待审核', '8': '审核中', '9': '已审核'}[auditStatus]}${auditStatus == '9' && auditResultName.isNotEmpty ? '·$auditResultName' : ''}' : '状态未知';
  bool get canDelete => auditStatus == '0';
  String get durationLabel => [if (days > 0) '$days天', if (hours > 0) '$hours小时'].join();
}
class LeaveDictItem { final String id, name; const LeaveDictItem(this.id, this.name); factory LeaveDictItem.fromJson(Map<String, dynamic> j) => LeaveDictItem('${j['id'] ?? ''}', '${j['text'] ?? ''}'); }
class RegionNode { final String id, name; final List<RegionNode> children; const RegionNode(this.id, this.name, [this.children = const []]); factory RegionNode.fromJson(Map<String, dynamic> j) => RegionNode('${j['id'] ?? ''}', '${j['text'] ?? ''}', (j['children'] is List ? (j['children'] as List).whereType<Map>().map((e) => RegionNode.fromJson(e.cast<String, dynamic>())).toList() : const [])); }
class LeaveDuration { final int days, hours; const LeaveDuration(this.days, this.hours); factory LeaveDuration.fromJson(Map<String, dynamic> j) => LeaveDuration(int.tryParse('${j['day'] ?? 0}') ?? 0, int.tryParse('${j['hour'] ?? 0}') ?? 0); String get label => [if (days > 0) '$days天', if (hours > 0) '$hours小时'].join(); }
class LeaveDetail { final Map<String, dynamic> raw; const LeaveDetail(this.raw); String get(String key) => '${raw[key] ?? ''}'; }
