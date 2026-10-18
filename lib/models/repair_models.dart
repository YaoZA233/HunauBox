import 'package:flutter/material.dart';

class RepairChoice {
  final String id;
  final String label;
  const RepairChoice(this.id, this.label);
}

class RepairField {
  final String name;
  final String label;
  final String editor;
  final bool required;
  final bool hidden;
  final bool readonly;
  final String? referenceType;
  final String? reference;
  final Map<String, dynamic> raw;
  const RepairField({
    required this.name,
    required this.label,
    required this.editor,
    required this.required,
    required this.hidden,
    required this.readonly,
    this.referenceType,
    this.reference,
    this.raw = const {},
  });

  bool get isChoice =>
      editor == 'lookup' ||
      editor == 'reference' ||
      editor == 'radiogroup' ||
      editor == 'priority';
  bool get isDate =>
      editor == 'datepicker' ||
      editor == 'datetimepicker' ||
      editor == 'date' ||
      raw['dataType'] == 'DATE' ||
      (!isChoice &&
          (label.contains('日期') || name.toLowerCase().contains('date')));
  bool get isMultiline => editor == 'textarea';
  bool get isUpload =>
      editor == 'upload' ||
      editor == 'image' ||
      editor == 'file' ||
      name == 'scwttp' ||
      name == 'uploadimage' ||
      name == 'zjsmj';
}

class RepairFormSession {
  final RepairCatalog catalog;
  final String instanceId;
  final String ciType;
  final String nodeId;
  final String submitActionId;
  final String? saveDraftActionId;
  final String? formRuleId;
  final List<RepairField> fields;
  final Map<String, dynamic> initialValues;
  const RepairFormSession({
    required this.catalog,
    required this.instanceId,
    required this.ciType,
    required this.nodeId,
    required this.submitActionId,
    this.saveDraftActionId,
    required this.formRuleId,
    required this.fields,
    required this.initialValues,
  });
}

class RepairCatalog {
  final String id, title, subtitle, department, processId;
  final Color color;
  final IconData icon;
  const RepairCatalog({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.department,
    required this.processId,
    required this.color,
    required this.icon,
  });
}

class RepairActivityLog {
  final String description, userName;
  final DateTime? time;
  const RepairActivityLog(this.description, this.userName, this.time);
  factory RepairActivityLog.fromJson(Map<String, dynamic> j) =>
      RepairActivityLog(
        '${j['description'] ?? ''}',
        '${j['create_user'] ?? ''}',
        DateTime.tryParse('${j['create_time'] ?? ''}'),
      );
}

class RepairAttachment {
  final String id, fileName, downloadUrl;
  const RepairAttachment(this.id, this.fileName, this.downloadUrl);
  factory RepairAttachment.fromJson(Map<String, dynamic> j) {
    final id = '${j['id'] ?? ''}';
    return RepairAttachment(
      id,
      '${j['upload_file_name'] ?? j['display_name'] ?? '附件'}',
      'https://bxpt.hunau.edu.cn/relax/mobile/rpc?method=/v2/file/download&id=$id',
    );
  }
}

class RepairAction {
  final String id, name;
  const RepairAction(this.id, this.name);
  bool get isCancel => name.contains('取消');
}

class RepairOrder {
  final String id,
      code,
      title,
      description,
      catalog,
      status,
      department,
      phone,
      handler,
      supplement;
  final DateTime? createdAt;
  final List<RepairActivityLog> logs;
  final List<RepairAttachment> attachments;
  final List<RepairAction> actions;
  final Map<String, dynamic> raw;
  const RepairOrder({
    required this.id,
    required this.code,
    required this.title,
    required this.description,
    required this.catalog,
    required this.status,
    required this.department,
    this.phone = '',
    this.handler = '',
    this.supplement = '',
    this.createdAt,
    this.logs = const [],
    this.attachments = const [],
    this.actions = const [],
    this.raw = const {},
  });
  factory RepairOrder.fromJson(
    Map<String, dynamic> j, {
    List<RepairActivityLog> logs = const [],
    List<RepairAttachment> attachments = const [],
    List<RepairAction> actions = const [],
  }) {
    String text(dynamic v) => v is Map
        ? '${v['display_name'] ?? v['name'] ?? v['name_path'] ?? ''}'
        : '${v ?? ''}';
    final cat = text(j['service_catalog']).isEmpty
        ? text(j['type'])
        : text(j['service_catalog']);
    return RepairOrder(
      id: '${j['id'] ?? ''}',
      code: '${j['code'] ?? j['id'] ?? ''}',
      title: '${j['dynamic_title'] ?? j['title'] ?? '校园报修'}',
      description:
          '${j['wtmsh'] ?? j['apply_description'] ?? j['description'] ?? ''}',
      catalog: cat,
      status: text(j['flow_status']).isEmpty
          ? '${j['node_name'] ?? '处理中'}'
          : text(j['flow_status']),
      department: text(j['actual_handler_department'] ?? j['process']),
      phone: '${j['lxfs'] ?? j['phone'] ?? ''}',
      handler: text(j['actual_handler']),
      supplement: '${j['bchshm'] ?? ''}',
      createdAt: j['create_time'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (j['create_time'] as num).toInt(),
            )
          : DateTime.tryParse('${j['create_time'] ?? ''}'),
      logs: logs,
      attachments: attachments,
      actions: actions,
      raw: j,
    );
  }
}
