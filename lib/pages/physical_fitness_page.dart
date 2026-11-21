import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/physical_fitness_service.dart';
import '../services/secure_storage_helper.dart';
import '../widgets/campus_loading_mark.dart';

class PhysicalFitnessPage extends StatefulWidget {
  const PhysicalFitnessPage({super.key});

  @override
  State<PhysicalFitnessPage> createState() => _PhysicalFitnessPageState();
}

class _PhysicalFitnessPageState extends State<PhysicalFitnessPage> {
  final _student = TextEditingController();
  final _password = TextEditingController();
  final _captcha = TextEditingController();
  final _service = PhysicalFitnessService();
  Uint8List? _captchaImage;
  PhysicalFitnessResult? _result;
  String? _error;
  bool _loading = false;
  bool _captchaLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _loadStudent();
    _refreshCaptcha();
  }

  Future<void> _loadStudent() async {
    final storage = SecureStorageHelper();
    final studentId = await storage.getFitnessStudentId();
    final password = await storage.getFitnessPassword();
    if (!mounted) return;
    if (studentId != null) _student.text = studentId;
    if (password != null) _password.text = password;
  }

  Future<void> _refreshCaptcha() async {
    setState(() => _captchaLoading = true);
    try {
      final image = await _service.fetchCaptcha();
      if (mounted) {
        setState(() {
          _captchaImage = image;
          _captcha.clear();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _captchaLoading = false);
    }
  }

  Future<void> _login() async {
    if (_student.text.trim().isEmpty ||
        _password.text.isEmpty ||
        _captcha.text.trim().isEmpty) {
      setState(() => _error = '请填写学号、密码和验证码');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final storage = SecureStorageHelper();
      await storage.saveFitnessStudentId(_student.text.trim());
      await storage.saveFitnessPassword(_password.text);
      final result = await _service.login(
        studentId: _student.text,
        password: _password.text,
        captcha: _captcha.text,
      );
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        await _refreshCaptcha();
      }
    }
  }

  static String _message(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('DioException [bad response]: ', '请求失败：');

  @override
  void dispose() {
    _student.dispose();
    _password.dispose();
    _captcha.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('体测成绩')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            '大学生体质健康测试',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '登录学校体测系统查询成绩',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _student,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '学号',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: '体测系统密码',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _captcha,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _loading ? null : _login(),
                  decoration: const InputDecoration(
                    labelText: '验证码',
                    prefixIcon: Icon(Icons.verified_user_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 112,
                height: 56,
                child: Material(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _captchaLoading ? null : _refreshCaptcha,
                    child: _captchaLoading || _captchaImage == null
                        ? Center(
                            child: _captchaLoading
                                ? const CampusLoadingMark(size: 22)
                                : const Icon(
                                    Icons.image_not_supported_outlined,
                                  ),
                          )
                        : Image.memory(_captchaImage!, fit: BoxFit.fill),
                  ),
                ),
              ),
              IconButton(
                tooltip: '刷新验证码',
                onPressed: _captchaLoading ? null : _refreshCaptcha,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: TextStyle(color: colors.error)),
            ),
          FilledButton.icon(
            onPressed: _loading ? null : _login,
            icon: _loading
                ? const CampusLoadingMark(size: 18, color: Colors.white)
                : const Icon(Icons.login_rounded),
            label: Text(_loading ? '正在连接学校系统' : '查询成绩'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
          if (_result case final result?) ...[
            const SizedBox(height: 28),
            Text(result.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (result.tables.isEmpty)
              Text(
                result.message.isEmpty
                    ? '学校系统已响应，但没有返回可展示的成绩表格。'
                    : result.message,
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              ...result.tables.map((table) => _ResultTable(table: table)),
          ],
        ],
      ),
    );
  }
}

class _ResultTable extends StatelessWidget {
  const _ResultTable({required this.table});

  final PhysicalFitnessTable table;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (table.headers.any((header) => header.contains('体测项目'))) {
      final metrics = table.rows
          .map(_FitnessMetric.fromRow)
          .whereType<_FitnessMetric>()
          .toList();
      final totals = metrics.where((item) => item.name == '成绩总分').toList();
      final total = totals.isEmpty ? null : totals.first;
      final items = metrics.where((item) => item.name != '成绩总分').toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (total != null) _TotalScoreCard(total: total),
          const SizedBox(height: 14),
          for (final item in items) _MetricCard(item: item),
          const SizedBox(height: 8),
        ],
      );
    }

    final labelRow = table.rows.firstWhere(
      (row) => row.any((value) => value == '标准分'),
      orElse: () => const [],
    );
    final valueIndex = table.rows.indexOf(labelRow) + 1;
    final valueRow = valueIndex > 0 && valueIndex < table.rows.length
        ? table.rows[valueIndex]
        : const <String>[];
    final year = table.headers.firstWhere(
      (value) => value.contains('学年'),
      orElse: () => '本学年',
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(year, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          Row(
            children: [
              _SummaryValue(label: '标准分', value: _at(valueRow, 0)),
              _SummaryValue(label: '附加分', value: _at(valueRow, 1)),
              _SummaryValue(
                label: '学年总分',
                value: _at(valueRow, 2),
                emphasized: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _at(List<String> values, int index) =>
      index < values.length && values[index].isNotEmpty ? values[index] : '--';
}

class _FitnessMetric {
  const _FitnessMetric({
    required this.name,
    required this.value,
    required this.unit,
    required this.score,
    required this.level,
  });

  final String name;
  final String value;
  final String unit;
  final String score;
  final String level;

  static _FitnessMetric? fromRow(List<String> row) {
    if (row.length < 3) return null;
    final nameIndex = row.indexWhere((value) => value.isNotEmpty);
    if (nameIndex < 0) return null;
    final name = row[nameIndex];
    if (name.isEmpty || name == '体测项目') return null;
    if (name == '成绩总分') {
      final numbers = row
          .where((value) => double.tryParse(value) != null)
          .toList();
      final level = row.lastWhere(
        (value) => value.isNotEmpty && double.tryParse(value) == null,
        orElse: () => '',
      );
      return _FitnessMetric(
        name: name,
        value: '',
        unit: '',
        score: numbers.isEmpty ? '--' : numbers.last,
        level: level,
      );
    }
    return _FitnessMetric(
      name: name,
      value: row.length > nameIndex + 1 ? row[nameIndex + 1] : '--',
      unit: row.length > nameIndex + 2 ? row[nameIndex + 2] : '',
      score: row.length > nameIndex + 3 ? row[nameIndex + 3] : '--',
      level: row.length > nameIndex + 5 ? row[nameIndex + 5] : '',
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: colors.onSurfaceVariant)),
          const SizedBox(height: 5),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
              color: emphasized ? colors.primary : colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalScoreCard extends StatelessWidget {
  const _TotalScoreCard({required this.total});

  final _FitnessMetric total;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.assessment_outlined, color: colors.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '成绩总分',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            total.score,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: colors.onPrimaryContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (total.level.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              total.level,
              style: TextStyle(color: colors.onPrimaryContainer),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.item});

  final _FitnessMetric item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 5),
                Text(
                  [
                    item.value,
                    item.unit,
                  ].where((value) => value.isNotEmpty).join(' '),
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                item.score,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.primary,
                ),
              ),
              if (item.level.isNotEmpty)
                Text(
                  item.level,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
