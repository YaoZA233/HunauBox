import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_models.dart';
import '../services/agent_settings_store.dart';

class AgentSettingsPage extends ConsumerStatefulWidget {
  const AgentSettingsPage({super.key});
  @override
  ConsumerState<AgentSettingsPage> createState() => _AgentSettingsPageState();
}

class _AgentSettingsPageState extends ConsumerState<AgentSettingsPage> {
  final _form = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _key = TextEditingController();
  final _model = TextEditingController();
  bool _ready = false;
  bool _hidden = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool retry = false}) async {
    final store = ref.read(agentSettingsProvider);
    if (retry) {
      await store.retryLoad();
    } else {
      await store.load();
    }
    if (!mounted) return;
    final config = store.config;
    _url.text = config.apiUrl;
    _key.text = config.apiKey;
    _model.text = config.model;
    setState(() {
      _ready = true;
      _error = store.error;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final store = ref.read(agentSettingsProvider);
    final next = store.config.copyWith(
      apiUrl: _url.text,
      apiKey: _key.text,
      model: _model.text,
    );
    try {
      await store.save(next);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Agent 配置已保存')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is AgentException ? e.message : '无法保存配置，请稍后重试',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(agentSettingsProvider);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Agent 配置')),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Form(
                  key: _form,
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Icon(Icons.tune_rounded, color: colors.primary, size: 32),
                      const SizedBox(height: 16),
                      Text(
                        '使用你自己的模型服务',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '支持兼容 Chat Completions 和工具调用的服务。URL、API Key 与模型均由你填写，没有默认中转服务。',
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _url,
                        enabled: !store.saving,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: '服务 URL',
                          hintText: 'https://你的服务域名/v1',
                          helperText: '可填写 Base URL 或完整 /chat/completions 地址',
                          helperMaxLines: 3,
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => AgentConfig(
                          apiUrl: v ?? '',
                          apiKey: 'validation-only',
                          model: 'validation-only',
                        ).validationError,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _key,
                        enabled: !store.saving,
                        obscureText: _hidden,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          helperText: '仅保存在设备安全存储中，不写入普通缓存或日志',
                          helperMaxLines: 3,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _hidden ? '显示 API Key' : '隐藏 API Key',
                            onPressed: () => setState(() => _hidden = !_hidden),
                            icon: Icon(
                              _hidden
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (v) =>
                            v?.trim().isNotEmpty == true ? null : '请填写 API Key',
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _model,
                        enabled: !store.saving,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: '模型名称',
                          hintText: '填写服务商提供的 model ID',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            v?.trim().isNotEmpty == true ? null : '请填写模型名称',
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '发送消息后，对话和回答所需的校园数据会传到你配置的服务。API Key 只用于该地址的授权。保存配置不会发送测试请求或自动开启 Agent。',
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(_error!, style: TextStyle(color: colors.error)),
                        if (store.error != null)
                          TextButton(
                            onPressed: () => _load(retry: true),
                            child: const Text('重试读取安全存储'),
                          ),
                      ],
                      const SizedBox(height: 28),
                      FilledButton.icon(
                        onPressed: store.saving || store.error != null
                            ? null
                            : _save,
                        icon: store.saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(store.saving ? '正在保存' : '保存配置'),
                      ),
                      TextButton(
                        onPressed: store.saving
                            ? null
                            : () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('清除 Agent 配置？'),
                                    content: const Text(
                                      '删除设备上保存的 URL、API Key 和模型，并关闭 Agent。',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('保留'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('清除'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true) return;
                                try {
                                  await store.clear();
                                  if (mounted) await _load();
                                } catch (_) {
                                  if (mounted) {
                                    setState(
                                      () => _error = '配置删除失败，Agent 已关闭，请重试',
                                    );
                                  }
                                }
                              },
                        child: const Text('清除配置并关闭 Agent'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
