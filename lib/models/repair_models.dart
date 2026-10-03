import 'package:flutter/material.dart';

class RepairCatalog { final String id, title, subtitle, department, processId; final Color color; final IconData icon; const RepairCatalog({required this.id, required this.title, required this.subtitle, required this.department, required this.processId, required this.color, required this.icon}); }
class RepairActivityLog { final String description, userName; final DateTime? time; const RepairActivityLog(this.description, this.userName, this.time); factory RepairActivityLog.fromJson(Map<String,dynamic> j) => RepairActivityLog('${j['description'] ?? ''}', '${j['create_user'] ?? ''}', DateTime.tryParse('${j['create_time'] ?? ''}')); }
class RepairAttachment { final String id, fileName, downloadUrl; const RepairAttachment(this.id, this.fileName, this.downloadUrl); factory RepairAttachment.fromJson(Map<String,dynamic> j) { final id='${j['id'] ?? ''}'; return RepairAttachment(id, '${j['upload_file_name'] ?? j['display_name'] ?? '附件'}', 'https://bxpt.hunau.edu.cn/relax/mobile/rpc?method=/v2/file/download&id=$id'); } }
class RepairAction { final String id, name; const RepairAction(this.id,this.name); bool get isCancel => name.contains('取消'); }
class RepairOrder {
  final String id, code, title, description, catalog, status, department, phone, handler, supplement;
  final DateTime? createdAt; final List<RepairActivityLog> logs; final List<RepairAttachment> attachments; final List<RepairAction> actions; final Map<String,dynamic> raw;
  const RepairOrder({required this.id, required this.code, required this.title, required this.description, required this.catalog, required this.status, required this.department, this.phone='', this.handler='', this.supplement='', this.createdAt, this.logs=const [], this.attachments=const [], this.actions=const [], this.raw=const {}});
  factory RepairOrder.fromJson(Map<String,dynamic> j, {List<RepairActivityLog> logs = const [], List<RepairAttachment> attachments = const [], List<RepairAction> actions = const []}) {
    String text(dynamic v) => v is Map ? '${v['display_name'] ?? v['name'] ?? v['name_path'] ?? ''}' : '${v ?? ''}';
    final cat=text(j['service_catalog']).isEmpty ? text(j['type']) : text(j['service_catalog']);
    return RepairOrder(id:'${j['id'] ?? ''}', code:'${j['code'] ?? j['id'] ?? ''}', title:'${j['dynamic_title'] ?? j['title'] ?? '校园报修'}', description:'${j['wtmsh'] ?? j['apply_description'] ?? j['description'] ?? ''}', catalog:cat, status:text(j['flow_status']).isEmpty ? '${j['node_name'] ?? '处理中'}' : text(j['flow_status']), department:text(j['actual_handler_department'] ?? j['process']), phone:'${j['lxfs'] ?? j['phone'] ?? ''}', handler:text(j['actual_handler']), supplement:'${j['bchshm'] ?? ''}', createdAt: j['create_time'] is num ? DateTime.fromMillisecondsSinceEpoch((j['create_time'] as num).toInt()) : DateTime.tryParse('${j['create_time'] ?? ''}'), logs: logs, attachments: attachments, actions: actions, raw:j);
  }
}
