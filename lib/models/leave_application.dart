import 'leave_models.dart';

/// The native form and XGXT must send the same application contract.
class LeaveApplication {
  final LeaveDictItem? type;
  final DateTime? start, end;
  final LeaveDuration? duration;
  final String reason, contact, phone, companions, address, remark;
  final bool leaveSchool, backDorm, outCity, outProvince;
  final RegionNode? destination;
  const LeaveApplication({
    this.type,
    this.start,
    this.end,
    this.duration,
    this.reason = '',
    this.contact = '',
    this.phone = '',
    this.companions = '',
    this.address = '',
    this.remark = '',
    this.leaveSchool = false,
    this.backDorm = false,
    this.outCity = false,
    this.outProvince = false,
    this.destination,
  });

  static String formatTime(DateTime value) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${pad(value.month)}-${pad(value.day)} ${pad(value.hour)}:${pad(value.minute)}';
  }

  String? get validationError {
    if (type == null || type!.id.isEmpty) return '请选择请假类型';
    if (start == null || end == null) return '请选择开始和结束时间';
    if (!end!.isAfter(start!)) return '结束时间必须晚于开始时间';
    if (duration == null) return '请先计算请假时长';
    if (duration!.days < 0 || duration!.hours < 0 || duration!.hours > 23) {
      return '请假时长异常，请重新计算';
    }
    if (reason.trim().isEmpty) return '请填写请假事由';
    if (contact.trim().isEmpty) return '请填写紧急联系人';
    if (!RegExp(r'^1\d{10}$').hasMatch(phone.trim())) return '请填写11位紧急联系人手机号';
    if (leaveSchool) {
      if (destination == null || destination!.id.isEmpty) return '请选择离校去向';
      if (address.trim().isEmpty) return '请填写离校详细地址';
      if (remark.trim().isEmpty) return '请填写离校备注';
    }
    return null;
  }

  Map<String, String> toFields() {
    final error = validationError;
    if (error != null) throw ArgumentError(error);
    final region = leaveSchool ? destination : null;
    return {
      'qjlxM.dm': type!.id,
      'qjlx': type!.name,
      'kssj': formatTime(start!),
      'jssj': formatTime(end!),
      'ts': '${duration!.days}',
      'jsTs': '${duration!.days}',
      'hour': '${duration!.hours}',
      'jsHour': '${duration!.hours}',
      'qjsy': reason.trim(),
      'lxr': contact.trim(),
      'lxrdh': phone.trim(),
      'txry': companions.trim(),
      'lxInd': leaveSchool ? '1' : '0',
      'lxqx.dm': region?.id ?? '',
      'lxqx1': region?.name ?? '',
      'lxMdd': leaveSchool ? address.trim() : '',
      'huisusheInd': backDorm ? '1' : '0',
      'lxBz': leaveSchool ? remark.trim() : '',
      'chushiInd': leaveSchool && outCity ? '1' : '0',
      'chushengInd': leaveSchool && outProvince ? '1' : '0',
      'pathFile': '',
      'qjLocation': '',
      'qjLocationZb': '',
      'operationType': 'Create',
      'id': '',
    };
  }
}
