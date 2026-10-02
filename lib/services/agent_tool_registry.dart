import 'package:dio/dio.dart';

import '../models/agent_models.dart';

typedef AgentConfirmation = Future<bool> Function(String title, String details);

class AgentToolContext {
  const AgentToolContext({required this.cancelToken, required this.confirm});
  final CancelToken cancelToken;
  final AgentConfirmation confirm;
  void checkActive() {
    if (cancelToken.isCancelled) throw const AgentException('本次请求已停止');
  }

  Future<bool> askConfirmation(String title, String details) async {
    checkActive();
    final approved = await confirm(title, details);
    checkActive();
    return approved;
  }
}

class AgentTool {
  const AgentTool({
    required this.name,
    required this.label,
    required this.description,
    this.properties = const {},
    this.requiredFields = const [],
    required this.run,
  });
  final String name;
  final String label;
  final String description;
  final Map<String, dynamic> properties;
  final List<String> requiredFields;
  final Future<Object?> Function(Map<String, dynamic>, AgentToolContext) run;

  Map<String, dynamic> toApiJson() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': properties,
        'required': requiredFields,
        'additionalProperties': false,
      },
    },
  };

  void validate(Map<String, dynamic> args) {
    if (requiredFields.any((f) => !args.containsKey(f)) ||
        args.keys.any((f) => !properties.containsKey(f))) {
      throw const AgentException('工具参数缺失或包含不支持的字段');
    }
    for (final entry in args.entries) {
      final schema = properties[entry.key] as Map;
      final value = entry.value;
      final valid = switch (schema['type']) {
        'string' => value is String && value.length <= 4000,
        'integer' => value is int,
        'boolean' => value is bool,
        _ => false,
      };
      if (!valid ||
          (schema['enum'] is List &&
              !(schema['enum'] as List).contains(value)) ||
          (value is num &&
              schema['minimum'] is num &&
              value < schema['minimum']) ||
          (value is num &&
              schema['maximum'] is num &&
              value > schema['maximum'])) {
        throw AgentException('工具参数 ${entry.key} 无效');
      }
    }
  }
}

class AgentToolRegistry {
  AgentToolRegistry(List<AgentTool> tools)
    : _tools = {for (final t in tools) t.name: t};
  final Map<String, AgentTool> _tools;
  List<Map<String, dynamic>> get schemas =>
      _tools.values.map((t) => t.toApiJson()).toList();
  String labelFor(String name) => _tools[name]?.label ?? '未知工具';

  Future<Object?> execute(
    String name,
    Map<String, dynamic> args,
    AgentToolContext context,
  ) async {
    context.checkActive();
    final tool = _tools[name];
    if (tool == null) return {'error': '不支持的工具，未执行任何操作'};
    try {
      tool.validate(args);
      final result = await tool.run(args, context);
      context.checkActive();
      return result;
    } on AgentException catch (e) {
      context.checkActive();
      return {'error': e.message};
    } catch (_) {
      context.checkActive();
      // 不向第三方模型暴露底层异常、请求头、Cookie 或密钥。
      return {'error': '${tool.label}未能完成，请在对应页面检查登录状态或网络后重试'};
    }
  }
}
