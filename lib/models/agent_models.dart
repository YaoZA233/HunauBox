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
  const AgentDisplayMessage(this.role, this.text);
  final String role;
  final String text;
}

class AgentReply {
  const AgentReply(this.text, this.history);
  final String text;
  final List<Map<String, dynamic>> history;
}

class AgentException implements Exception {
  const AgentException(this.message);
  final String message;
  @override
  String toString() => message;
}
