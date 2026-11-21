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
                        ? const Center(child: CampusLoadingMark(size: 22))
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in table.rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < row.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${i < table.headers.length ? table.headers[i] : '项目'}  ${row[i]}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: i == row.length - 1
                              ? colors.onSurface
                              : colors.onSurfaceVariant,
                          fontWeight: i == row.length - 1
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Divider(color: colors.outlineVariant),
        ],
      ),
    );
  }
}
