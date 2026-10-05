import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../models/agent_models.dart';
import '../services/agent_service.dart';
import '../services/agent_conversation_store.dart';
import '../services/agent_settings_store.dart';
import '../services/agent_tool_registry.dart';
import '../services/campus_agent_tools.dart';
import '../widgets/agent_history_sheet.dart';
import '../widgets/agent_message_bubble.dart';
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
  late final AgentConversationStore _conversations = ref.read(
    agentConversationsProvider,
  );
  String? _conversationId;
  bool _chatsReady = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore({bool retry = false}) async {
    if (retry) {
      await _conversations.retryLoad();
    } else {
      await _conversations.load();
    }
    if (!mounted) return;
    setState(() {
      _chatsReady = _conversations.loadError == null;
      _showConversation(_conversations.active);
    });
    _scrollToEnd();
  }

  void _showConversation(AgentConversation? conversation) {
    _conversationId = conversation?.id;
    _messages.clear();
    _messages.addAll(conversation?.messages ?? []);
    _history = conversation?.history.toList() ?? [];
    _error = null;
    _input.clear();
  }

  Future<bool> _saveConversation({bool pending = false}) async {
    if (_messages.isEmpty || _conversationId == null) return true;
    final first = _messages.first.text.replaceAll(RegExp(r'\s+'), ' ');
    final record = AgentConversation(
      id: _conversationId!,
      title:
          _conversations.byId(_conversationId!)?.title ??
          (first.length > 32 ? '${first.substring(0, 32)}…' : first),
      updatedAt: DateTime.now(),
      messages: _messages,
      history: _history,
      pending: pending,
    );
    try {
      await _conversations.upsert(record);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _interruptTurn() {
    _cancelToken?.cancel();
    _cancelToken = null;
    if (_busy) {
      _messages.add(
        const AgentDisplayMessage(
          'assistant',
          agentInterruptedText,
          incomplete: true,
        ),
      );
      // _history already contains the safe placeholder persisted at send time.
      unawaited(_saveConversation());
    }
    _busy = false;
    _activity = null;
  }

  @override
  void dispose() {
    _interruptTurn();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _stop({bool clear = false}) {
    _interruptTurn();
    setState(() {
      _busy = false;
      _activity = null;
      _error = null;
      if (clear) {
        _showConversation(null);
        unawaited(_selectConversation(null));
      }
    });
  }

  Future<void> _selectConversation(String? id) async {
    try {
      await _conversations.select(id);
    } catch (_) {}
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
    if (_busy ||
        !_chatsReady ||
        text.isEmpty ||
        !config.enabled ||
        !config.isConfigured) {
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
    _conversationId ??=
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    final requestHistory = [
      ..._history,
      {'role': 'user', 'content': text},
    ];
    setState(() {
      _busy = true;
      _error = null;
      _activity = '正在思考';
      _messages.add(AgentDisplayMessage('user', text));
      _history = [
        ...requestHistory,
        {'role': 'assistant', 'content': agentInterruptedText},
      ];
      _input.clear();
    });
    _scrollToEnd();
    try {
      if (!await _saveConversation(pending: true)) {
        throw const AgentException('消息未能保存，本次尚未请求模型，请重试保存后再发送');
      }
      if (!mounted || token.isCancelled) return;
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
        _busy = false;
        _activity = null;
        _history = result.history;
        _messages.add(
          AgentDisplayMessage(
            'assistant',
            result.text,
            reasoning: result.reasoning,
            usage: result.usage,
            model: result.model,
            durationMs: result.durationMs,
          ),
        );
      });
      await _saveConversation();
      _scrollToEnd();
    } catch (e) {
      if (!mounted || token.isCancelled) return;
      final errorMessage = e is AgentException ? e.message : '请求未完成，请检查配置或稍后重试';
      setState(() {
        _busy = false;
        _activity = null;
        _error = null;
        _messages.add(
          AgentDisplayMessage('assistant', errorMessage, incomplete: true),
        );
      });
      await _saveConversation();
    } finally {
      if (mounted && identical(_cancelToken, token)) {
        setState(() {
          _busy = false;
          _activity = null;
        });
      }
    }
  }

  void _newConversation() {
    _stop(clear: true);
  }

  Future<void> _openHistory() async {
    if (_busy) _stop();
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AgentHistorySheet(),
    );
    if (!mounted) return;
    if (id != null) {
      await _selectConversation(id);
      if (!mounted) return;
      setState(() => _showConversation(_conversations.byId(id)));
      _scrollToEnd();
    } else if (_conversationId != null &&
        _conversations.byId(_conversationId!) == null) {
      _stop(clear: true);
    }
  }

  Future<void> _export(String action) async {
    final conversation = _conversationId == null
        ? null
        : _conversations.byId(_conversationId!);
    if (conversation == null) return;
    final text = conversation.exportText();
    try {
      if (action == 'copy') {
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('对话已复制为 Markdown')));
        }
      } else {
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(
          ShareParams(
            text: text,
            title: conversation.title,
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('导出未完成，请尝试复制对话')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(agentSettingsProvider);
    final chats = ref.watch(agentConversationsProvider);
    ref.listen<AgentSettingsStore>(agentSettingsProvider, (previous, next) {
      // ChangeNotifier 的 previous/next 是同一对象，配置快照在消息发送时检查。
      if (_cancelToken != null &&
          (!next.config.enabled || !identical(next.config, _activeConfig))) {
        _stop(clear: true);
        _cancelToken = null;
      }
    });
    final config = store.config;
    final available =
        store.loaded && config.enabled && config.isConfigured && _chatsReady;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent'),
        actions: [
          IconButton(
            tooltip: '聊天记录',
            onPressed: chats.loaded && chats.loadError == null
                ? _openHistory
                : null,
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: '新建会话',
            onPressed: _chatsReady ? _newConversation : null,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: '导出对话',
            enabled: _messages.isNotEmpty,
            onSelected: _export,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', child: Text('复制完整对话')),
              PopupMenuItem(value: 'share', child: Text('分享 / 导出对话')),
            ],
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              if (chats.loadError != null || chats.saveError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      Text(
                        chats.loadError ?? chats.saveError!,
                        style: TextStyle(color: colors.error),
                      ),
                      TextButton(
                        onPressed: () async {
                          if (chats.loadError != null) {
                            await _restore(retry: true);
                          } else {
                            try {
                              await chats.retrySave();
                            } catch (_) {}
                          }
                        },
                        child: Text(
                          chats.loadError != null ? '重试读取聊天记录' : '重试保存',
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: !store.loaded || !chats.loaded
                    ? const Center(child: CircularProgressIndicator())
                    : !config.enabled || !config.isConfigured
                    ? _buildSetup(store)
                    : _messages.isEmpty
                    ? _buildWelcome()
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) =>
                            AgentMessageBubble(message: _messages[i]),
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
        '对话自动保存在本机，可从右上角历史记录继续聊天。仅把回答所需的对话与校园数据发送到你配置的模型服务。',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}
