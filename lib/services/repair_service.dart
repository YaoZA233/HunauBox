import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../models/app_constants.dart';
import '../models/repair_models.dart';
import 'auth_service.dart';
import 'dio_client.dart';

class RepairException implements Exception {
  final String message;
  const RepairException(this.message);
  @override
  String toString() => message;
}

class _RepairLoginRequired extends RepairException {
  const _RepairLoginRequired() : super('报修登录已失效，请重新登录');
}

class RepairService {
  RepairService({Dio? dio, Future<bool> Function()? reauthenticate})
    : _dio = dio,
      _reauthenticate = reauthenticate ?? AuthService().silentLogin;
  final Dio? _dio;
  final Future<bool> Function() _reauthenticate;
  bool _ready = false;
  Future<void>? _sessionFuture;
  String _uid = '';
  Map<String, dynamic> _identity = {};
  Future<Dio> get client async {
    if (_dio != null) return _dio;
    await DioClient().initialize();
    return DioClient().dio;
  }

  static const catalogs = <RepairCatalog>[
    RepairCatalog(
      id: '5bbbaf0a-b7b7-11eb-b305-4bcc6b2984af',
      title: '后勤报修',
      subtitle: '宿舍、公共设施与生活服务',
      department: '后勤保障中心',
      processId: '4e2cc26d-08b4-4cab-a3a7-fba23a23e11d',
      color: Color(0xFFE8843A),
      icon: Icons.home_repair_service_outlined,
    ),
    RepairCatalog(
      id: 'b4435ca0-99f6-11ec-bf7a-177427586306',
      title: '校园网络报修',
      subtitle: '无线网络、网线与校园网故障',
      department: '信息与网络中心',
      processId: 'd86a31ef-6e54-4da5-8c8f-a881986ec422',
      color: Color(0xFF478BEA),
      icon: Icons.wifi_tethering_error_rounded,
    ),
    RepairCatalog(
      id: 'f11e3e78-9ace-11ec-9f07-f7b2f4ca88d7',
      title: '一校通报修',
      subtitle: '一卡通、数字校园与信息化设备',
      department: '信息与网络中心',
      processId: 'aa21a42a-a2f7-48a7-aae6-fc374e4ebc44',
      color: Color(0xFFDD5B75),
      icon: Icons.devices_other_outlined,
    ),
    RepairCatalog(
      id: 'ffa62964-9539-11ec-a409-0f7763ad71f7',
      title: '业务系统报修',
      subtitle: '教务、门户及其他业务系统',
      department: '信息与网络中心',
      processId: 'f83a50f6-95f9-41d9-bf27-851f340035a4',
      color: Color(0xFF38A88D),
      icon: Icons.apps_outlined,
    ),
  ];

  Future<void> _ensure({bool verify = false}) {
    if (_sessionFuture != null) return _sessionFuture!;
    if (_ready && !verify) return Future.value();
    return _sessionFuture = _establish().whenComplete(
      () => _sessionFuture = null,
    );
  }

  Future<bool> _probe(Dio d) async {
    try {
      final identity = await _rpcRaw(d, '/v2/login/isAuthenticated', null);
      if (identity is Map && '${identity['id'] ?? ''}'.isNotEmpty) {
        _identity = identity.cast<String, dynamic>();
        _uid = '${identity['id']}';
        _ready = true;
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _establish() async {
    final d = await client;
    if (await _probe(d)) return;
    _ready = false;
    _uid = '';
    _identity = {};
    await _exchange(d);
    if (await _probe(d)) return;
    if (await _reauthenticate()) {
      await _exchange(d);
      if (await _probe(d)) return;
    }
    throw const RepairException('报修平台登录失败，请在个人中心重新登录后重试');
  }

  Future<void> _exchange(Dio d) async {
    var current = Uri.parse(AppConstants.repairsSsoUrl);
    for (var i = 0; i < 10; i++) {
      final response = await d.getUri(
        current,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null || location.isEmpty) return;
      var next = current.resolve(location);
      if (next.host == Uri.parse(AppConstants.repairsBaseUrl).host &&
          next.scheme == 'http') {
        next = next.replace(scheme: 'https', port: 443);
      }
      if (next.scheme != 'https' ||
          next.userInfo.isNotEmpty ||
          ![
            Uri.parse(AppConstants.repairsBaseUrl).host,
            Uri.parse(AppConstants.ssoBaseUrl).host,
          ].contains(next.host)) {
        throw const RepairException('报修认证跳转异常');
      }
      if (next == current) return;
      current = next;
    }
    throw const RepairException('报修认证跳转次数过多，请重试');
  }

  Future<dynamic> _rpcRaw(Dio d, String path, dynamic params) async {
    final response = await d.post(
      '${AppConstants.repairsBaseUrl}/relax/mobile/rpc',
      queryParameters: {'p': path, 't': DateTime.now().millisecondsSinceEpoch},
      data: {'jsonrpc': '2.0', 'method': path, 'id': '1', 'params': params},
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.plain,
        followRedirects: false,
        validateStatus: (s) => s != null && s < 500,
        headers: {
          'Origin': AppConstants.repairsBaseUrl,
          'Referer': AppConstants.repairsIndexUrl,
          'X-Requested-With': 'XMLHttpRequest',
          'X-User-Lang': 'zh-CN',
          'Accept': '*/*',
        },
      ),
    );
    final status = response.statusCode ?? 0;
    if ((status >= 300 && status < 400) || status == 401 || status == 403) {
      throw const _RepairLoginRequired();
    }
    dynamic body = response.data;
    if (body is String) {
      final lower = body.trimLeft().toLowerCase();
      if (lower.startsWith('<!doctype') || lower.startsWith('<html')) {
        throw const _RepairLoginRequired();
      }
      try {
        body = jsonDecode(body);
      } catch (_) {
        try {
          body = jsonDecode(utf8.decode(base64Decode(body.trim())));
        } catch (_) {
          throw const RepairException('报修平台返回了无法读取的数据，请稍后重试');
        }
      }
    }
    if (body is! Map || !body.containsKey('result') && body['error'] == null) {
      throw const RepairException('报修平台响应格式异常');
    }
    if (body['error'] != null) {
      final error = body['error'];
      final message = error is Map
          ? '${error['message'] ?? error['data'] ?? ''}'
          : '$error';
      if (error is Map && [-32001, 401, 403].contains(error['code']) ||
          RegExp(
            r'未登录|登录已|登录失效|登录超时|not authenticated|unauthenticated|authentication required',
            caseSensitive: false,
          ).hasMatch(message)) {
        throw const _RepairLoginRequired();
      }
      throw RepairException(
        message.isEmpty ? '报修服务异常，请稍后重试' : '报修服务异常：$message',
      );
    }
    if (status != 200) throw RepairException('报修服务响应异常（$status）');
    return body['result'];
  }

  Future<dynamic> _rpc(
    String path,
    dynamic params, {
    dynamic Function()? buildParams,
  }) async {
    await _ensure();
    final d = await client;
    try {
      return await _rpcRaw(d, path, buildParams?.call() ?? params);
    } on _RepairLoginRequired {
      _ready = false;
      // Never replay submissions: a write failure may already have reached the server.
      if (path.contains('/execute') ||
          path.contains('/create') ||
          path.contains('/delete')) {
        rethrow;
      }
      await _ensure();
      return _rpcRaw(d, path, buildParams?.call() ?? params);
    }
  }

  Future<List<RepairOrder>> fetchOrders({
    bool ongoing = true,
    bool isDraft = false,
  }) async {
    await _ensure(verify: true);
    final method = isDraft
        ? '/v2/workorder/data/officePage'
        : ongoing
        ? '/v2/service/portal/workorderData/ongoingPage'
        : '/v2/service/portal/workorderData/finishPage';
    final result = await _rpc(
      method,
      null,
      buildParams: () => [
        '37ea4a70-af77-4c1a-9422-7582afc0de41',
        {
          'attributes': [
            'id',
            'type',
            'code',
            'service_catalog',
            'apply_user',
            'apply_description',
            'flow_status',
            'create_time',
            'start_time',
            'process',
            'node_name',
            'close_time',
            'dynamic_title',
          ],
          'filter': {
            'attribute': {
              'and': [
                if (isDraft)
                  {
                    'simple': {
                      'name': 'flow_status',
                      'operator': 'eq',
                      'value': 'NEW',
                    },
                  },
                if (ongoing && !isDraft)
                  {
                    'simple': {
                      'name': 'id',
                      'operator': 'in-lookup',
                      'value': ['0', '1'],
                    },
                  },
                if (ongoing && !isDraft)
                  {
                    'or': [
                      {
                        'simple': {
                          'name': 'apply_user',
                          'operator': 'eq',
                          'value': _uid,
                        },
                      },
                      {
                        'simple': {
                          'name': 'create_user',
                          'operator': 'eq',
                          'value': _uid,
                        },
                      },
                    ],
                  }
                else
                  {
                    'simple': {
                      'name': isDraft ? 'create_user' : 'apply_user',
                      'operator': 'eq',
                      'value': _uid,
                    },
                  },
                if (!ongoing && !isDraft)
                  {
                    'simple': {
                      'name': 'close_time',
                      'operator': 'isnotnull',
                      'value': null,
                    },
                  },
              ],
            },
            'query': '',
          },
          'orders': [
            {'name': isDraft ? 'create_time' : 'start_time', 'type': 'desc'},
          ],
          'pageSize': '50',
          'pageIndex': '1',
        },
      ],
    );
    final data = result is Map ? result['data'] : null;
    if (data is! List) throw const RepairException('未能读取报修工单，请重试');
    return data
        .whereType<Map>()
        .map((e) => RepairOrder.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<RepairOrder> fetchDetail(RepairOrder order) async {
    final type = order.raw['type'] is Map
        ? '${(order.raw['type'] as Map)['id'] ?? ''}'
        : '${order.raw['type'] ?? ''}';
    final result = await _rpc('/v2/workorder/data/getById', [type, order.id]);
    if (result is! Map) throw const RepairException('工单详情数据异常');
    return RepairOrder.fromJson({
      ...order.raw,
      ...result.cast<String, dynamic>(),
    });
  }

  Future<RepairFormSession> loadForm(RepairCatalog catalog) async {
    await _ensure(verify: true);
    final instanceId = await _rpc('/v2/cmdb/ci/id', []);
    final detail = await _rpc(
      '/v2/workorder/serviceitem/card/getMobileCatalogById',
      [catalog.id],
    );
    final formResult = await _rpc(
      '/v2/workorder/view/form/getNotRelationOrderForm',
      [
        catalog.id,
        'apply',
        {
          'create_user': null,
          'id': '$instanceId',
          'service_catalog': catalog.id,
        },
      ],
    );
    final actions = await _rpc('/v2/workorder/action/list', [
      await _rpc('/v2/workorder/orderConfig/getNodeByServiceCatalog', [
        catalog.id,
      ]),
      '',
    ]);
    final form = formResult is List && formResult.isNotEmpty
        ? formResult.first
        : null;
    final construct = form is Map
        ? jsonDecode('${form['constructData'] ?? '{}'}')
        : <String, dynamic>{};
    final detailType = detail is Map && detail['type'] is Map
        ? (detail['type'] as Map)['id']
        : '';
    final ciType = '${construct['ciType'] ?? detailType}';
    final components = construct['components'] is List
        ? construct['components'] as List
        : <dynamic>[];
    final fields = <RepairField>[];
    void add(dynamic item) {
      if (item is! Map) return;
      final editor = '${item['editor'] ?? ''}';
      final name = '${item['name'] ?? ''}';
      if (name.isEmpty || editor == 'group' || editor == 'label') return;
      final validate = item['validate'] is Map
          ? item['validate'] as Map
          : const {};
      fields.add(
        RepairField(
          name: name,
          label: '${item['label'] ?? name}',
          editor: editor,
          required: item['required'] == true || validate['required'] == true,
          hidden: item['hidden'] == true,
          readonly: item['readonly'] == true,
          referenceType: item['referenceType']?.toString(),
          reference: item['reference']?.toString(),
          raw: item.cast<String, dynamic>(),
        ),
      );
    }

    void walk(List items) {
      for (final item in items) {
        add(item);
        if (item is Map) {
          for (final key in ['components', 'children']) {
            if (item[key] is List) walk(item[key] as List);
          }
        }
      }
    }

    walk(components);
    if (ciType.isEmpty || fields.isEmpty) {
      throw const RepairException('报修表单配置不完整，请重试');
    }
    final nodeId =
        '${await _rpc('/v2/workorder/orderConfig/getNodeByServiceCatalog', [catalog.id])}';
    final actionList = actions is List ? actions : const [];
    final submit = actionList.whereType<Map>().firstWhere(
      (a) => '${a['name']}' == '提交' || '${a['display_name']}' == '提交',
      orElse: () => <String, dynamic>{'id': ''},
    );
    if ('${submit['id'] ?? ''}'.isEmpty) {
      throw const RepairException('该报修类型暂无提交动作');
    }
    final draft = actionList.whereType<Map>().firstWhere(
      (a) =>
          '${a['name']}'.contains('草稿') ||
          '${a['display_name']}'.contains('草稿'),
      orElse: () => <String, dynamic>{'id': ''},
    );
    final rule =
        construct['rules'] is List && (construct['rules'] as List).isNotEmpty
        ? '${(construct['rules'] as List).first['rule_id']}'
        : null;
    final initial = <String, dynamic>{
      'id': '$instanceId',
      'type': ciType,
      'source': 'mobile',
      'priority_group': '2',
      'apply_user': _uid,
      'xm': '${_identity['display_name'] ?? _identity['name'] ?? ''}',
      'xgh': '${_identity['username'] ?? _identity['login_name'] ?? ''}',
    };
    return RepairFormSession(
      catalog: catalog,
      instanceId: '$instanceId',
      ciType: ciType,
      nodeId: nodeId,
      submitActionId: '${submit['id'] ?? ''}',
      saveDraftActionId: '${draft['id'] ?? ''}'.isNotEmpty
          ? '${draft['id']}'
          : null,
      formRuleId: rule,
      fields: fields,
      initialValues: initial,
    );
  }

  Future<List<RepairChoice>> references(
    String type, {
    String query = '',
  }) async {
    dynamic result;
    try {
      result = await _rpc('/v2/cmdb/ci/page', [
        type,
        {
          'pageSize': 100,
          'pageIndex': 1,
          'orders': [
            {'name': 'display_name', 'type': 'asc'},
          ],
          'filter': {'query': query},
        },
      ]);
    } catch (_) {
      try {
        result = await _rpc('/v2/cmdb/ci/list', [
          type,
          {
            'attributes': ['id', 'display_name', 'name'],
            'orders': [
              {'name': 'display_name', 'type': 'asc'},
            ],
            'filter': {},
          },
        ]);
      } catch (_) {
        return [];
      }
    }

    List list = [];
    if (result is Map && result['data'] is List) {
      list = result['data'] as List;
    } else if (result is List) {
      list = result;
    }

    return list
        .whereType<Map>()
        .map(
          (e) => RepairChoice(
            '${e['id'] ?? ''}',
            '${e['display_name'] ?? e['name'] ?? ''}',
          ),
        )
        .where((e) => e.id.isNotEmpty && e.label.isNotEmpty)
        .take(100)
        .toList();
  }

  Future<List<RepairChoice>> lookup(
    String lookupType, {
    List<String>? notInNames,
  }) async {
    try {
      final andList = <Map<String, dynamic>>[
        {
          'simple': {
            'name': 'lookup_type',
            'operator': 'eq',
            'value': lookupType,
          },
        },
        if (notInNames != null && notInNames.isNotEmpty)
          {
            'simple': {
              'name': 'name',
              'operator': 'notin',
              'value': notInNames,
            },
          },
      ];

      final result = await _rpc('/v2/cmdb/meta/lookup/page', [
        {
          'orders': [
            {'name': 'index', 'type': 'asc'},
          ],
          'filter': {
            'attribute': {'and': andList},
            'query': '',
          },
          'pageSize': 20,
          'pageIndex': 1,
        },
      ]);
      final data = result is Map ? result['data'] : null;
      if (data is! List) return [];
      return data
          .whereType<Map>()
          .map(
            (e) => RepairChoice(
              '${e['name'] ?? e['id']}',
              '${e['display_name'] ?? e['name'] ?? ''}',
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static int? parseDateToTimestamp(dynamic val) {
    if (val == null) return null;
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is DateTime) return val.millisecondsSinceEpoch;
    final str = val.toString().trim();
    if (str.isEmpty) return null;
    final asInt = int.tryParse(str);
    if (asInt != null) return asInt;

    final parsed = DateTime.tryParse(str.replaceAll('/', '-'));
    if (parsed != null) return parsed.millisecondsSinceEpoch;

    final parts = str.split(RegExp(r'[/ -]'));
    if (parts.length >= 3) {
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y != null && m != null && d != null) {
        int hour = 0;
        int minute = 0;
        int second = 0;
        if (parts.length >= 4) hour = int.tryParse(parts[3]) ?? 0;
        if (parts.length >= 5) minute = int.tryParse(parts[4]) ?? 0;
        if (parts.length >= 6) second = int.tryParse(parts[5]) ?? 0;
        return DateTime(y, m, d, hour, minute, second).millisecondsSinceEpoch;
      }
    }
    final iso = str.replaceAll('/', '-');
    final dt = DateTime.tryParse(iso);
    if (dt != null) return dt.millisecondsSinceEpoch;
    return null;
  }

  Future<String> submitForm(
    RepairFormSession session,
    Map<String, dynamic> values, {
    bool isDraft = false,
  }) async {
    await _ensure(verify: true);
    final actionId = isDraft
        ? (session.saveDraftActionId ?? session.submitActionId)
        : session.submitActionId;

    final data = {...session.initialValues, 'apply_user': _uid};
    for (final field in session.fields) {
      data.putIfAbsent(field.name, () => field.isUpload ? 0 : null);
    }
    data.addAll(values);

    final dateFieldNames = {
      for (final f in session.fields)
        if (f.isDate) f.name,
    };

    final sanitizedData = <String, dynamic>{};
    for (final entry in data.entries) {
      final key = entry.key;
      final val = entry.value;

      if (dateFieldNames.contains(key) ||
          key == 'yyrq' ||
          key.toLowerCase().contains('date')) {
        if (val == null || (val is String && val.trim().isEmpty)) {
          sanitizedData[key] = null;
        } else {
          sanitizedData[key] = parseDateToTimestamp(val) ?? val;
        }
        continue;
      }

      if (val is Map && val.containsKey('id') && val['id'] is String) {
        sanitizedData[key] = val['id'];
      } else {
        sanitizedData[key] = val;
      }
    }
    final params = [
      actionId,
      [
        {
          'id': session.instanceId,
          'type': session.ciType,
          'node': session.nodeId,
        },
        sanitizedData,
        {'service_catalog': session.catalog.id},
      ],
      if (session.formRuleId != null) [session.formRuleId],
    ];
    final result = await _rpc(
      '/v2/workorder/action/executeWithValidate',
      params,
    );
    if (result is Map && result['state'] == true) return 'ok';
    throw RepairException(isDraft ? '保存草稿失败，请稍后重试' : '提交失败，请检查必填项后重试');
  }

  Future<RepairAttachment> uploadAttachment(
    RepairFormSession session,
    RepairField field,
    File file,
  ) async {
    await _ensure();

    final fileName = file.path.split(Platform.pathSeparator).last;
    final instance = '${session.instanceId}-${field.name}';
    final formData = FormData.fromMap({
      'uploadFile': await MultipartFile.fromFile(file.path, filename: fileName),
      'fileName': 'uploadFile',
      'subsystem': 'eui',
      'instance': instance,
    });

    final tm = DateTime.now().millisecondsSinceEpoch;
    final url =
        '${AppConstants.repairsBaseUrl}/relax/mobile/rpc?tm=$tm&method=/v2/file/upload';

    final response = await (await client).post(
      url,
      data: formData,
      options: Options(
        headers: {
          'Origin': AppConstants.repairsBaseUrl,
          'Referer': '${AppConstants.repairsBaseUrl}/relax/mobile/index.html',
          'X-Requested-With': 'XMLHttpRequest',
        },
      ),
    );

    dynamic resData = response.data;
    if (resData is String) {
      try {
        resData = jsonDecode(resData);
      } catch (_) {}
    }

    if (resData is! Map) {
      throw const RepairException('上传附件失败，服务器未返回有效数据');
    }

    final attachment = RepairAttachment.fromJson(
      resData.cast<String, dynamic>(),
    );

    // 记录节点上传附件活动日志并建立关联 (与 HAR 抓包中 Entry 12 & 13 一致)
    // 服务端靠这条 CI 日志关联工单展示流转记录，不写可能导致附件在流转记录/审核侧不可见，故保留。
    try {
      final user = '${_identity['display_name'] ?? '用户'}';
      final logRes = await _rpc('/v2/cmdb/ci/create', [
        {
          'type': '737fb2a0-a9a5-41fd-b36f-d32d604e2128',
          'create_user': _uid,
          'description':
              '$user在“开始“节点，上传附件\$\$"${attachment.fileName}"\$\$<<rpc?method=/v2/file/download&id=${attachment.id}>>',
        },
      ]);
      if (logRes != null) {
        final logId = '$logRes';
        await _rpc('/v2/cmdb/relation/create', [
          {
            'type': '42e2bb1d-2d74-4cc7-a53b-ba5413b14792',
            'source': session.instanceId,
            'destination': logId,
          },
        ]);
      }
    } catch (_) {}

    return attachment;
  }

  Future<void> deleteAttachment(String fileId) async {
    await _ensure();
    try {
      await _rpc('/v2/file/deleteById', [fileId]);
    } catch (e) {
      throw RepairException('删除附件失败: $e');
    }
  }

  Future<void> submit({
    required RepairCatalog catalog,
    required String title,
    required String description,
    required String location,
    String phone = '',
  }) async {
    final session = await loadForm(catalog);
    await submitForm(session, {
      'dynamic_title': title.trim(),
      'wtmsh': description.trim(),
      'bchshm': location.trim(),
      'lxfs': phone.trim(),
    });
  }
}
