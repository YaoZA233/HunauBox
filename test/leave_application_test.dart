import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/leave_application.dart';
import 'package:smart_hunan_agri/models/leave_models.dart';

LeaveApplication application({
  bool leaving = false,
  String contact = '母亲',
  String phone = '13800138000',
  RegionNode? region,
  String address = '测试地址',
  String remark = '回家',
  DateTime? end,
  LeaveDuration? duration = const LeaveDuration(1, 2),
}) => LeaveApplication(
  type: const LeaveDictItem('type', '事假'),
  start: DateTime(2026, 10, 12, 9, 5),
  end: end ?? DateTime(2026, 10, 13, 11, 5),
  duration: duration,
  reason: ' 家中有事 ',
  contact: contact,
  phone: phone,
  companions: '同学',
  leaveSchool: leaving,
  backDorm: true,
  outCity: true,
  outProvince: true,
  destination: region,
  address: address,
  remark: remark,
);

void main() {
  test('完整表单遵循ChillEast字段约定和Create操作', () {
    final fields = application(
      leaving: true,
      region: const RegionNode('county', '区县'),
    ).toFields();
    expect(fields, {
      'qjlxM.dm': 'type',
      'qjlx': '事假',
      'kssj': '2026-10-12 09:05',
      'jssj': '2026-10-13 11:05',
      'ts': '1',
      'jsTs': '1',
      'hour': '2',
      'jsHour': '2',
      'qjsy': '家中有事',
      'lxr': '母亲',
      'lxrdh': '13800138000',
      'txry': '同学',
      'lxInd': '1',
      'lxqx.dm': 'county',
      'lxqx1': '区县',
      'lxMdd': '测试地址',
      'huisusheInd': '1',
      'lxBz': '回家',
      'chushiInd': '1',
      'chushengInd': '1',
      'pathFile': '',
      'qjLocation': '',
      'qjLocationZb': '',
      'operationType': 'Create',
      'id': '',
    });
  });
  test('紧急联系人和合法电话为必填', () {
    expect(application(contact: '').validationError, contains('联系人'));
    for (final phone in ['', '123', '1380013800a']) {
      expect(application(phone: phone).validationError, contains('手机号'));
    }
  });
  test('结束时间不能早于或等于开始时间', () {
    for (final end in [DateTime(2026, 10, 12, 9, 5), DateTime(2026, 10, 11)]) {
      expect(application(end: end).validationError, contains('晚于'));
    }
  });
  test('学校时长不可缺失或越界', () {
    expect(application(duration: null).validationError, contains('时长'));
    for (final value in [
      const LeaveDuration(-1, 0),
      const LeaveDuration(0, 24),
    ]) {
      expect(application(duration: value).validationError, contains('时长异常'));
    }
  });
  test('离校时去向、地址和备注缺一不可', () {
    expect(application(leaving: true).validationError, contains('去向'));
    expect(
      application(
        leaving: true,
        region: const RegionNode('id', '省'),
        address: '',
      ).validationError,
      contains('地址'),
    );
    expect(
      application(
        leaving: true,
        region: const RegionNode('id', '省'),
        remark: '',
      ).validationError,
      contains('备注'),
    );
  });
  test('取消离校不会提交隐藏的旧地址和出省开关', () {
    final fields = application(
      region: const RegionNode('old', '旧地址'),
    ).toFields();
    expect(fields['lxqx.dm'], isEmpty);
    expect(fields['lxMdd'], isEmpty);
    expect(fields['chushengInd'], '0');
  });
  test('详情正确展示对象名称和附件列表', () {
    final detail = LeaveDetail({
      'lxqx': {'mc': '长沙市'},
      'fileList': [
        {'nameOld': '证明.jpg'},
        {'name': '附件.png'},
      ],
    });
    expect(detail.get('lxqx'), '长沙市');
    expect(detail.get('fileList'), '证明.jpg、附件.png');
  });
}
