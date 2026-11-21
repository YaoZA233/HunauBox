import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../services/secure_storage_helper.dart';
import '../services/tuition_payment_service.dart';
import '../widgets/campus_loading_mark.dart';

class TuitionPaymentPage extends StatefulWidget {
  const TuitionPaymentPage({super.key});
  @override
  State<TuitionPaymentPage> createState() => _TuitionPaymentPageState();
}

class _TuitionPaymentPageState extends State<TuitionPaymentPage> {
  final _idCard = TextEditingController();
  final _name = TextEditingController();
  final _captcha = TextEditingController();
  final _service = TuitionPaymentService();
  Uint8List? _captchaImage;
  String? _captchaId;
  String? _error;
  bool _loading = false;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _loadIdentity();
    _refreshCaptcha();
  }

  Future<void> _loadIdentity() async {
    final storage = SecureStorageHelper();
    final idCard = await storage.getTuitionIdCard();
    final name = await storage.getTuitionName();
    if (!mounted) return;
    if (idCard != null) _idCard.text = idCard;
    if (name != null) _name.text = name;
  }

  Future<void> _refreshCaptcha() async {
    try {
      final data = await _service.fetchCaptcha();
      final id = data['data']?['id']?.toString() ?? data['id']?.toString();
      if (id == null) throw Exception('验证码标识缺失');
      final image = await _service.fetchCaptchaImage(id);
      if (mounted)
        setState(() {
          _captchaId = id;
          _captchaImage = image;
        });
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _query() async {
    if (_idCard.text.trim().isEmpty ||
        _name.text.trim().isEmpty ||
        _captcha.text.trim().isEmpty ||
        _captchaId == null) {
      setState(() => _error = '请填写身份证号、姓名和验证码');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final storage = SecureStorageHelper();
      await storage.saveTuitionIdCard(_idCard.text.trim());
      await storage.saveTuitionName(_name.text.trim());
      await _service.queryStudent(
        idCard: _idCard.text,
        name: _name.text,
        captchaId: _captchaId!,
        captchaCode: _captcha.text,
      );
      final items = await _service.getMyNotices(status: 'unpaid');
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _idCard.dispose();
    _name.dispose();
    _captcha.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('学费与学杂费')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            '费用查询',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '直接连接学校缴费 API，查询结果来自财务平台。',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _idCard,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '身份证号',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '姓名',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _captcha,
                  decoration: const InputDecoration(
                    labelText: '图形验证码',
                    prefixIcon: Icon(Icons.shield_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _refreshCaptcha,
                child: Container(
                  width: 110,
                  height: 52,
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.outline),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _captchaImage == null
                      ? const Center(child: CampusLoadingMark(size: 20))
                      : Image.memory(_captchaImage!, fit: BoxFit.cover),
                ),
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
            onPressed: _loading ? null : _query,
            icon: _loading
                ? const CampusLoadingMark(size: 18, color: Colors.white)
                : const Icon(Icons.search_rounded),
            label: Text(_loading ? '正在查询' : '查询应缴费用'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
          const SizedBox(height: 26),
          Text('待缴项目', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (!_loading && _items.isEmpty)
            Text(
              '完成身份核验后，这里会显示学校返回的待缴项目。',
              style: TextStyle(color: colors.onSurfaceVariant),
            )
          else
            ..._items.map((item) => _FeeItem(item: item)),
        ],
      ),
    );
  }
}

class _FeeItem extends StatelessWidget {
  const _FeeItem({required this.item});
  final Map<String, dynamic> item;
  @override
  Widget build(BuildContext context) {
    final title = (item['sflxmc'] ?? item['sfxmmc'] ?? item['name'] ?? '缴费项目')
        .toString();
    final amount =
        (item['dueAmt'] ??
                item['jfdx'] ??
                item['amount'] ??
                item['sfxmje'] ??
                '')
            .toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text(title),
        subtitle: Text(item['sfndmc']?.toString() ?? '学校财务平台'),
        trailing: amount.isEmpty
            ? null
            : Text(
                '¥$amount',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
      ),
    );
  }
}
