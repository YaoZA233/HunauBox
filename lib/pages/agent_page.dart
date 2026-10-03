import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_models.dart';
import '../services/agent_service.dart';
import '../services/agent_settings_store.dart';
import '../services/agent_tool_registry.dart';
import '../services/campus_agent_tools.dart';
import 'agent_settings_page.dart';
import 'campus_card_recharge_page.dart';
import 'electricity_recharge_page.dart';
import 'empty_classroom_page.dart';
import 'homework_page.dart';
import 'notice_page.dart';
import 'questionnaire_list_page.dart';
import 'score_page.dart';
import 'timetable_page.dart';
import 'sunshine_page.dart';
import 'leave_page.dart';
import 'repair_page.dart';

class AgentPage extends ConsumerStatefulWidget {
  const AgentPage({super.key, this.service, this.tools});
  final AgentService? service;
  final AgentToolRegistry? tools;
  @override
  ConsumerState<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends ConsumerState<AgentPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <AgentDisplayMessage>[];
  List<Map<String, dynamic>> _history = [];
  late final AgentService _service = widget.service ?? AgentService();
  CancelToken? _cancelToken;
  bool _busy = false;
  String? _activity;
  String? _error;

  @override
  void dispose() {
    _cancelToken?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _stop({bool clear = false}) {
    _cancelToken?.cancel();
    setState(() {
      _busy = false;
      _activity = null;
      _error = null;
      if (clear) {
        _messages.clear();
        _history.clear();
      }
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<bool> _confirm(String title, String details) async {
    if (!mounted || _cancelToken?.isCancelled != false) return false;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: Text(details)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('确认操作'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _openService(String service) async {
    if (!mounted) return;
    final Widget page = switch (service) {
      'timetable' => const TimetablePage(),
      'homework' => const HomeworkPage(),
      'notice' => const NoticePage(),
      'scores' => const ScorePage(),
      'classroom' => const EmptyClassroomPage(),
      'campus_card' => const CampusCardRechargePage(),
      'electricity' => const ElectricityRechargePage(),
      'questionnaire' => const QuestionnaireListPage(),
      'sunshine' => const SunshinePage(),
      'leave' => const LeavePage(),
      'repair' => const RepairPage(),
      _ => throw const AgentException('不支持的校园页面'),
    };
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  Future<void> _send([String? suggested]) async {
    final text = (suggested ?? _input.text).trim();
    final config = ref.read(agentSettingsProvider).config;
    if (_busy || text.isEmpty || !config.enabled || !config.isConfigured) {
      return;
    }
    if (text.length > 4000) {
      setState(() => _error = '消息过长，请控制在 4000 字以内');
      return;
    }
    if (_messages.where((m) => m.role == 'user').length >= 20) {
      setState(() => _error = '当前会话已达 20 轮，请新建会话后继续');
      return;
    }
    final token = CancelToken();
    _cancelToken = token;
    final requestHistory = [
      ..._history,
      {'role': 'user', 'content': text},
    ];
    setState(() {
      _busy = true;
      _error = null;
      _activity = '正在思考';
      _messages.add(AgentDisplayMessage('user', text));
      _input.clear();
    });
    _scrollToEnd();
    try {
      final result = await _service.chat(
        config: config,
        history: requestHistory,
        tools:
            widget.tools ??
            buildCampusAgentTools(ref, openService: _openService),
        context: AgentToolContext(cancelToken: token, confirm: _confirm),
        onActivity: (label) {
          if (mounted && !token.isCancelled) setState(() => _activity = label);
        },
      );
      if (!mounted || token.isCancelled) return;
      setState(() {
        _history = result.history;
        _messages.add(AgentDisplayMessage('assistant', result.text));
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted || token.isCancelled) return;
      setState(() {
        _error = e is AgentException ? e.message : '请求未完成，请检查配置或稍后重试';
        _history = [
          ...requestHistory,
          {'role': 'assistant', 'content': '本轮请求未完成。请以校园页面中的实际记录为准。'},
        ];
      });
    } finally {
      if (mounted && identical(_cancelToken, token)) {
        setState(() {
          _busy = false;
          _activity = null;
        });
      }
    }
  }

  Future<void> _newConversation() async {
    if (_messages.isNotEmpty) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('新建会话？'),
          content: const Text('清空当前对话。已经完成的校园操作不会撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('保留'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('新建'),
            ),
          ],
        ),
      );
      if (!mounted || approved != true) return;
    }
    _stop(clear: true);
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(agentSettingsProvider);
    ref.listen<AgentSettingsStore>(agentSettingsProvider, (previous, next) {
      // ChangeNotifier 的 previous/next 是同一对象，配置快照在消息发送时检查。
      if (_cancelToken != null &&
          (!next.config.enabled || !identical(next.config, _activeConfig))) {
        _stop(clear: true);
        _cancelToken = null;
      }
    });
    final config = store.config;
    final available = store.loaded && config.enabled && config.isConfigured;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent'),
        actions: [
          IconButton(
            tooltip: '新建会话',
            onPressed: _newConversation,
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              Expanded(
                child: !available
                    ? _buildSetup(store)
                    : _messages.isEmpty
                    ? _buildWelcome()
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final message = _messages[i];
                          final user = message.role == 'user';
                          return Align(
                            alignment: user
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              padding: const EdgeInsets.all(16),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width * .86,
                              ),
                              decoration: BoxDecoration(
                                color: user
                                    ? colors.primaryContainer
                                    : colors.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user ? '你' : 'Agent',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: user
                                          ? colors.onPrimaryContainer
                                          : colors.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SelectableText(
                                    message.text,
                                    style: TextStyle(
                                      height: 1.55,
                                      color: user
                                          ? colors.onPrimaryContainer
                                          : colors.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (_busy)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_activity ?? '正在思考')),
                      TextButton(onPressed: _stop, child: const Text('停止')),
                    ],
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Text(_error!, style: TextStyle(color: colors.error)),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          enabled: available && !_busy,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 4000,
                          decoration: const InputDecoration(
                            hintText: '问课表、查作业，或说明你要办的事',
                            counterText: '',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(16),
                              ),
                            ),
                          ),
                          onSubmitted: (_) => _startSend(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        tooltip: '发送',
                        onPressed: available && !_busy ? _startSend : null,
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  AgentConfig? _activeConfig;
  void _startSend([String? text]) {
    _activeConfig = ref.read(agentSettingsProvider).config;
    _send(text);
  }

  Widget _buildSetup(AgentSettingsStore store) => ListView(
    padding: const EdgeInsets.all(28),
    children: [
      const SizedBox(height: 32),
      const Icon(Icons.smart_toy_outlined, size: 48),
      const SizedBox(height: 20),
      Text(
        store.config.enabled ? '先连接你的模型服务' : 'Agent 已关闭',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      Text(
        store.config.enabled
            ? '填写服务 URL、API Key 和模型。配置只保存在设备上，发送消息后才会连接服务。'
            : '如需使用，请从右上角头像进入设置，开启 Agent。',
      ),
      if (store.error != null) ...[
        const SizedBox(height: 12),
        Text(store.error!),
      ],
      const SizedBox(height: 24),
      if (store.config.enabled)
        FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const AgentSettingsPage()),
          ),
          icon: const Icon(Icons.tune_rounded),
          label: const Text('填写模型服务配置'),
        ),
    ],
  );

  Widget _buildWelcome() => ListView(
    padding: const EdgeInsets.all(28),
    children: [
      const SizedBox(height: 24),
      Align(
        alignment: Alignment.centerLeft,
        child: Icon(
          Icons.smart_toy_outlined,
          size: 38,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      const SizedBox(height: 24),
      Text(
        '今天的校园事务，\n从一句话开始。',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      const Text('回答来自你的校园数据。工具执行进度会显示在对话下方，修改前需要你确认。'),
      const SizedBox(height: 28),
      for (final prompt in [
        '今天有哪些课，分别在哪上？',
        '把下周一的高等数学调到下周三第3-4节',
        '这周五的英语课停课一次',
        '列出还没完成的作业',
        '查询宿舍电费余额',
        '有哪些待填写的学工问卷？',
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.all(16),
            ),
            onPressed: () => _startSend(prompt),
            child: Text(prompt),
          ),
        ),
      const SizedBox(height: 16),
      Text(
        '仅把本次回答所需数据发送到你配置的模型服务。对话仅保留在当前页面，退出即清空。',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}
