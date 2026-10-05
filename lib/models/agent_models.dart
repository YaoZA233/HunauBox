import 'dart:convert';

class AgentConfig {
  const AgentConfig({
    this.enabled = false,
    this.apiUrl = '',
    this.apiKey = '',
    this.model = '',
  });
  final bool enabled;
  final String apiUrl;
  final String apiKey;
  final String model;

  bool get isConfigured => validationError == null;
  String? get validationError {
    final uri = Uri.tryParse(apiUrl.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return '请填写有效的 HTTPS 服务 URL，不含账号、查询参数或片段';
    }
    if (apiKey.trim().isEmpty) return '请填写 API Key';
    if (model.trim().isEmpty) return '请填写服务商支持的模型名称';
    return null;
  }

  String get endpoint {
    var url = apiUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (!url.endsWith('/chat/completions')) url += '/chat/completions';
    return url;
  }

  AgentConfig copyWith({
    bool? enabled,
    String? apiUrl,
    String? apiKey,
    String? model,
  }) => AgentConfig(
    enabled: enabled ?? this.enabled,
    apiUrl: apiUrl?.trim() ?? this.apiUrl,
    apiKey: apiKey?.trim() ?? this.apiKey,
    model: model?.trim() ?? this.model,
  );

  String encodeForStorage() => jsonEncode({
    'enabled': enabled,
    'apiUrl': apiUrl,
    'apiKey': apiKey,
    'model': model,
  });
  factory AgentConfig.decode(String value) {
    final data = jsonDecode(value) as Map<String, dynamic>;
    return AgentConfig(
      enabled: data['enabled'] == true,
      apiUrl: data['apiUrl'] as String? ?? '',
      apiKey: data['apiKey'] as String? ?? '',
      model: data['model'] as String? ?? '',
    );
  }
  // 不提供包含 Key 的 toString / 日志序列化。
}

class AgentDisplayMessage {
  const AgentDisplayMessage(
    this.role,
    this.text, {
    this.reasoning = '',
    this.usage,
    this.model = '',
    this.durationMs,
    this.incomplete = false,
  });
  final String role;
  final String text;
  final String reasoning;
  final AgentTokenUsage? usage;
  final String model;
  final int? durationMs;
  final bool incomplete;

  Map<String, dynamic> toJson() => {
    'role': role,
    'text': text,
    if (reasoning.isNotEmpty) 'reasoning': reasoning,
    if (usage != null) 'usage': usage!.toJson(),
    if (model.isNotEmpty) 'model': model,
    if (durationMs != null) 'durationMs': durationMs,
    if (incomplete) 'incomplete': true,
  };

  factory AgentDisplayMessage.fromJson(Map<String, dynamic> data) =>
      AgentDisplayMessage(
        data['role'] as String,
        data['text'] as String,
        reasoning: data['reasoning'] as String? ?? '',
        usage: data['usage'] is Map
            ? AgentTokenUsage.fromJson(Map<String, dynamic>.from(data['usage']))
            : null,
        model: data['model'] as String? ?? '',
        durationMs: data['durationMs'] as int?,
        incomplete: data['incomplete'] == true,
      );
}

class AgentReply {
  const AgentReply(
    this.text,
    this.history, {
    this.reasoning = '',
    this.usage,
    this.model = '',
    this.durationMs,
  });
  final String text;
  final List<Map<String, dynamic>> history;
  final String reasoning;
  final AgentTokenUsage? usage;
  final String model;
  final int? durationMs;
}

/// Nullable counts distinguish an unavailable measurement from a real zero.
/// Details (cache/reasoning) are subsets, never added to input/output totals.
class AgentTokenUsage {
  const AgentTokenUsage({
    this.inputTokens,
    this.outputTokens,
    this.cachedTokens,
    this.reasoningTokens,
    this.requests = 1,
    this.reportedRequests = 0,
  });
  final int? inputTokens;
  final int? outputTokens;
  final int? cachedTokens;
  final int? reasoningTokens;
  final int requests;
  final int reportedRequests;

  static int? count(dynamic value) => value is int && value >= 0 ? value : null;

  factory AgentTokenUsage.fromProvider(dynamic raw) {
    final data = raw is Map ? raw : const {};
    final promptDetails = data['prompt_tokens_details'];
    final outputDetails = data['completion_tokens_details'];
    final input = count(data['prompt_tokens']) ?? count(data['input_tokens']);
    final output =
        count(data['completion_tokens']) ?? count(data['output_tokens']);
    return AgentTokenUsage(
      inputTokens: input,
      outputTokens: output,
      cachedTokens:
          count(promptDetails is Map ? promptDetails['cached_tokens'] : null) ??
          count(data['cached_tokens']) ??
          count(data['prompt_cache_hit_tokens']),
      reasoningTokens: count(
        outputDetails is Map ? outputDetails['reasoning_tokens'] : null,
      ),
      reportedRequests: input != null && output != null ? 1 : 0,
    );
  }

  AgentTokenUsage plus(AgentTokenUsage other) {
    int? sum(int? a, int? b) =>
        a == null && b == null ? null : (a ?? 0) + (b ?? 0);
    return AgentTokenUsage(
      inputTokens: sum(inputTokens, other.inputTokens),
      outputTokens: sum(outputTokens, other.outputTokens),
      cachedTokens: sum(cachedTokens, other.cachedTokens),
      reasoningTokens: sum(reasoningTokens, other.reasoningTokens),
      requests: requests + other.requests,
      reportedRequests: reportedRequests + other.reportedRequests,
    );
  }

  Map<String, dynamic> toJson() => {
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'cachedTokens': cachedTokens,
    'reasoningTokens': reasoningTokens,
    'requests': requests,
    'reportedRequests': reportedRequests,
  };
  factory AgentTokenUsage.fromJson(Map<String, dynamic> data) =>
      AgentTokenUsage(
        inputTokens: count(data['inputTokens']),
        outputTokens: count(data['outputTokens']),
        cachedTokens: count(data['cachedTokens']),
        reasoningTokens: count(data['reasoningTokens']),
        requests: count(data['requests']) ?? 1,
        reportedRequests: count(data['reportedRequests']) ?? 0,
      );
}

const agentInterruptedText = '本轮请求未完成。部分校园操作可能已经执行，请先检查对应页面，勿重复提交。';

class AgentConversation {
  AgentConversation({
    required this.id,
    required this.title,
    required this.updatedAt,
    required List<AgentDisplayMessage> messages,
    required List<Map<String, dynamic>> history,
    this.pending = false,
  }) : messages = List.unmodifiable(messages),
       // Snapshot the complete tool protocol before asynchronous storage writes.
       history = List.unmodifiable(
         (jsonDecode(jsonEncode(history)) as List).map(
           (m) => Map<String, dynamic>.from(m as Map),
         ),
       );
  final String id;
  final String title;
  final DateTime updatedAt;
  final List<AgentDisplayMessage> messages;
  final List<Map<String, dynamic>> history;
  final bool pending;

  AgentTokenUsage? get usage {
    AgentTokenUsage? total;
    for (final message in messages) {
      if (message.usage != null) {
        total = total?.plus(message.usage!) ?? message.usage;
      }
    }
    return total;
  }

  AgentConversation copyWith({
    String? title,
    bool? pending,
    List<AgentDisplayMessage>? messages,
  }) => AgentConversation(
    id: id,
    title: title ?? this.title,
    updatedAt: updatedAt,
    messages: messages ?? this.messages,
    history: history,
    pending: pending ?? this.pending,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages.map((m) => m.toJson()).toList(),
    'history': history,
    'pending': pending,
  };
  factory AgentConversation.fromJson(Map<String, dynamic> data) =>
      AgentConversation(
        id: data['id'] as String,
        title: data['title'] as String,
        updatedAt: DateTime.parse(data['updatedAt'] as String),
        messages: (data['messages'] as List)
            .map(
              (m) => AgentDisplayMessage.fromJson(
                Map<String, dynamic>.from(m as Map),
              ),
            )
            .toList(),
        history: (data['history'] as List)
            .map((m) => Map<String, dynamic>.from(m as Map))
            .toList(),
        pending: data['pending'] == true,
      );

  String exportText() {
    final result = StringBuffer('# $title\n\n');
    for (final m in messages) {
      result.writeln('## ${m.role == 'user' ? '你' : 'Agent'}\n');
      if (m.reasoning.isNotEmpty) {
        result.writeln('思考内容（模型返回）：\n${m.reasoning}\n');
      }
      result.writeln('${m.text}\n');
      if (m.model.isNotEmpty) result.writeln('模型：${m.model}');
      if (m.usage != null) {
        result.writeln(
          '输入 Token：${m.usage!.inputTokens ?? '未返回'}；输出 Token：${m.usage!.outputTokens ?? '未返回'}；统计 ${m.usage!.reportedRequests}/${m.usage!.requests} 次请求\n',
        );
      }
    }
    return result.toString();
  }
}

class AgentException implements Exception {
  const AgentException(this.message);
  final String message;
  @override
  String toString() => message;
}
