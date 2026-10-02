import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/questionnaire_models.dart';
import '../services/questionnaire_service.dart';
import '../widgets/questionnaire_widgets.dart';

class QuestionnaireDetailPage extends StatefulWidget {
  const QuestionnaireDetailPage({
    super.key,
    required this.item,
    required this.service,
  });
  final QuestionnaireItem item;
  final QuestionnaireService service;

  @override
  State<QuestionnaireDetailPage> createState() =>
      _QuestionnaireDetailPageState();
}

class _QuestionnaireDetailPageState extends State<QuestionnaireDetailPage> {
  QuestionnaireDetail? _detail;
  final Map<String, dynamic> _answers = {};
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, GlobalKey> _questionKeys = {};
  bool _loading = true;
  bool _submitting = false;
  bool _dirty = false;
  bool _allowExit = false;
  bool _requiresStatusCheck = false;
  bool _exitDialogOpen = false;
  String? _error;
  String? _submissionError;
  String? _invalidQuestion;

  bool get _readOnly => !widget.item.isPending || _detail?.canSubmit != true;
  bool get _editable => !_readOnly && !_submitting && !_requiresStatusCheck;
  int get _answeredCount =>
      _detail?.questions.where((q) => q.isAnswered(_answers[q.dm])).length ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.service.fetchDetail(widget.item);
      if (!mounted) return;
      for (final question in detail.questions) {
        _answers[question.dm] = question.initialAnswer;
        _questionKeys[question.dm] = GlobalKey();
        if (!question.isChoice && !question.isDate) {
          _controllers[question.dm] = TextEditingController(
            text: question.answer,
          );
        }
      }
      setState(() => _detail = detail);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is QuestionnaireException
              ? e.message
              : '暂时无法读取题目，请检查网络后重试',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _answer(QuestionnaireQuestion question, dynamic value) {
    if (!_editable) return;
    setState(() {
      _answers[question.dm] = value;
      _dirty = true;
      if (_invalidQuestion == question.dm) _invalidQuestion = null;
    });
  }

  Future<void> _exit([bool changed = false]) async {
    setState(() => _allowExit = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(changed);
  }

  Future<void> _handleBack() async {
    if (_submitting || _exitDialogOpen) return;
    if (_requiresStatusCheck || !_dirty) {
      await _exit(_requiresStatusCheck);
      return;
    }
    _exitDialogOpen = true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出填写？'),
        content: const Text('本次填写的内容还未提交，退出后将不会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续填写'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    _exitDialogOpen = false;
    if (leave == true && mounted) await _exit();
  }

  Future<void> _submit() async {
    final detail = _detail;
    if (detail == null || !_editable) return;
    FocusScope.of(context).unfocus();
    final validation = detail.validate(_answers);
    if (validation != null) {
      final missing = detail.questions
          .where((q) => q.required && !q.isAnswered(_answers[q.dm]))
          .firstOrNull;
      setState(() => _invalidQuestion = missing?.dm);
      final target = _questionKeys[missing?.dm]?.currentContext;
      if (target != null) {
        await Scrollable.ensureVisible(
          target,
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 250),
          alignment: 0.15,
        );
      }
      if (mounted) _message(validation);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提交这份问卷？'),
        content: const Text('请确认填写的信息准确，提交后可返回列表查看结果。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('再检查一下'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认提交'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_editable) return;
    setState(() {
      _submitting = true;
      _submissionError = null;
    });
    try {
      await widget.service.submit(
        item: widget.item,
        detail: detail,
        answers: Map.of(_answers),
      );
      if (!mounted) return;
      _message('问卷提交成功');
      await _exit(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submissionError = e is QuestionnaireException
            ? e.message
            : '提交失败，请检查网络后重试';
        _requiresStatusCheck =
            e is QuestionnaireException && e.requiresStatusCheck;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _pickDate(QuestionnaireQuestion question) async {
    if (!_editable) return;
    final first = DateTime(1900);
    final last = DateTime(2100, 12, 31);
    var initial =
        DateTime.tryParse(_answers[question.dm]?.toString() ?? '') ??
        DateTime.now();
    if (initial.isBefore(first) || initial.isAfter(last)) {
      initial = DateTime.now();
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null && mounted && _editable) {
      _answer(question, DateFormat('yyyy-MM-dd').format(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final detail = _detail;
    final total = detail?.questions.length ?? 0;
    return PopScope(
      canPop: _allowExit || (!_dirty && !_submitting && !_requiresStatusCheck),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.item.isSubmitted ? '问卷详情' : '填写问卷'),
          leading: IconButton(
            tooltip: '返回',
            onPressed: _submitting ? null : _handleBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: SingleChildScrollView(
                  child: QuestionnaireStatePanel(
                    icon: Icons.description_outlined,
                    title: '题目暂未加载',
                    message: _error!,
                    action: FilledButton(
                      onPressed: _load,
                      child: const Text('重新加载'),
                    ),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  _header(total),
                  const SizedBox(height: 20),
                  if (detail != null)
                    ...detail.questions.asMap().entries.map(
                      (e) => _question(e.value, e.key),
                    ),
                  if (total == 0)
                    const QuestionnaireStatePanel(
                      icon: Icons.description_outlined,
                      title: '暂无可显示的题目',
                      message: '可返回列表刷新，或在学工系统网页查看。',
                    ),
                  if (_submissionError != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.errorContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _submissionError!,
                        style: TextStyle(
                          color: colors.onErrorContainer,
                          height: 1.6,
                        ),
                      ),
                    ),
                ],
              ),
        bottomNavigationBar: detail == null || _loading
            ? null
            : SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: Border(
                      top: BorderSide(color: colors.outlineVariant),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _readOnly
                                  ? (widget.item.isPending
                                        ? '当前不可填写'
                                        : widget.item.statusLabel)
                                  : '已填写 $_answeredCount / $total 题',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _readOnly ? '当前问卷仅供查看' : '标记「必填」的题目需完成',
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _submitting
                            ? null
                            : _requiresStatusCheck
                            ? () => _exit(true)
                            : _readOnly
                            ? () => _exit()
                            : total == 0
                            ? null
                            : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _readOnly || _requiresStatusCheck
                                    ? Icons.arrow_back_rounded
                                    : Icons.send_rounded,
                                size: 17,
                              ),
                        label: Text(
                          _submitting
                              ? '正在提交'
                              : _requiresStatusCheck
                              ? '返回核对'
                              : _readOnly
                              ? '返回列表'
                              : '提交问卷',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _header(int total) {
    final colors = Theme.of(context).colorScheme;
    final detail = _detail;
    final title = detail?.title.isNotEmpty == true
        ? detail!.title
        : widget.item.title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            QuestionnaireBadge(label: _readOnly ? '查看记录' : '信息登记'),
            QuestionnaireBadge(
              label: '$total 道题',
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          title.isEmpty ? '学工问卷' : title,
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        if (detail?.desc.isNotEmpty == true && detail!.desc != title) ...[
          const SizedBox(height: 10),
          Text(
            detail.desc,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 14,
              height: 1.65,
            ),
          ),
        ],
        if (widget.item.endTime.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '截止 ${widget.item.endTime}',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : _answeredCount / total,
            minHeight: 5,
            backgroundColor: colors.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }

  Widget _question(QuestionnaireQuestion q, int index) {
    final colors = Theme.of(context).colorScheme;
    final invalid = _invalidQuestion == q.dm;
    return Container(
      key: _questionKeys[q.dm],
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: invalid
              ? colors.error
              : colors.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                (index + 1).toString().padLeft(2, '0'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                q.typeLabel,
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
              const Spacer(),
              if (q.required)
                Text(
                  '必填',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: invalid ? colors.error : colors.onSurfaceVariant,
                  ),
                )
              else
                Text(
                  '选填',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            q.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          if (q.desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              q.desc,
              style: TextStyle(
                fontSize: 12,
                height: 1.55,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (!q.isSupported)
            const Text('该题型请在学工系统网页填写')
          else if (q.isChoice)
            _choices(q)
          else if (q.isDate)
            InkWell(
              onTap: _editable ? () => _pickDate(q) : null,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  suffixIcon: const Icon(
                    Icons.calendar_today_outlined,
                    size: 19,
                  ),
                ),
                child: Text(
                  _answers[q.dm]?.toString().isNotEmpty == true
                      ? _answers[q.dm].toString()
                      : _readOnly
                      ? '未填写'
                      : '请选择日期',
                ),
              ),
            )
          else
            TextField(
              key: ValueKey('answer-${q.dm}'),
              controller: _controllers[q.dm],
              readOnly: !_editable,
              minLines: 1,
              maxLines: q.isPhone ? 1 : 4,
              keyboardType: q.isPhone
                  ? TextInputType.phone
                  : TextInputType.multiline,
              inputFormatters: q.isPhone
                  ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]'))]
                  : null,
              onChanged: (value) => _answer(q, value),
              decoration: InputDecoration(
                hintText: _readOnly
                    ? '未填写'
                    : q.isPhone
                    ? '请输入数字或联系电话'
                    : '请填写你的回答',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: colors.onSurfaceVariant,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
          if (invalid) ...[
            const SizedBox(height: 8),
            Text(
              '请完成这道必填题',
              style: TextStyle(color: colors.error, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _choices(QuestionnaireQuestion q) {
    if (q.options.isEmpty) return const Text('选项暂未加载，请返回列表刷新');
    final colors = Theme.of(context).colorScheme;
    final value = _answers[q.dm];
    final selected = value is List ? value.toSet() : {value};
    final options = Column(
      children: q.options.map((option) {
        final checked = selected.contains(option.dm);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: checked
                ? colors.primaryContainer.withValues(alpha: 0.5)
                : colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: checked ? colors.primary : Colors.transparent,
            ),
          ),
          child: q.isMultiChoice
              ? CheckboxListTile(
                  value: checked,
                  onChanged: _editable
                      ? (value) {
                          final current = _answers[q.dm];
                          final next = Set<String>.from(
                            current is List
                                ? current.whereType<String>()
                                : <String>[],
                          );
                          if (value == true) {
                            next.add(option.dm);
                          } else {
                            next.remove(option.dm);
                          }
                          _answer(q, next.toList());
                        }
                      : null,
                  title: Text(
                    option.name,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                )
              : RadioListTile<String>(
                  value: option.dm,
                  enabled: _editable,
                  title: Text(
                    option.name,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
        );
      }).toList(),
    );
    if (q.isMultiChoice) return options;
    return RadioGroup<String>(
      groupValue: value is String && value.isNotEmpty ? value : null,
      onChanged: (value) => _answer(q, value ?? ''),
      child: options,
    );
  }
}
