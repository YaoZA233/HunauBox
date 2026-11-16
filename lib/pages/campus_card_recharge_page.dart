import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/app_logger.dart';
import '../services/campus_card_service.dart';
import '../widgets/campus_card_payment_sheet.dart';
import 'campus_card_bill_page.dart';

class CampusCardRechargePage extends StatefulWidget {
  const CampusCardRechargePage({super.key});

  @override
  State<CampusCardRechargePage> createState() => _CampusCardRechargePageState();
}

class _CampusCardRechargePageState extends State<CampusCardRechargePage> {
  final _logger = AppLogger.instance;
  final TextEditingController _amountController = TextEditingController();

  CampusCardInfo? _info;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _refreshError;
  DateTime? _updatedAt;
  String? _error;

  double? _selectedAmount;
  final List<double> _presetAmounts = [10, 30, 50, 100, 200, 500];
  PaymentMethod _paymentMethod = PaymentMethod.wechat;

  @override
  void initState() {
    super.initState();
    _restoreAndRefresh();
  }

  Future<void> _restoreAndRefresh() async {
    final service = CampusCardService.instance;
    final cached = service.displayInfo;
    if (cached != null) {
      _info = cached;
      _updatedAt = service.infoUpdatedAt;
      _isLoading = false;
    } else {
      final snapshot = await service.getStoredCardInfo();
      if (!mounted) return;
      if (snapshot != null) {
        setState(() {
          _info = CampusCardInfo(
            name: snapshot.data['name'] as String,
            idserial: snapshot.data['idserial'] as String,
            balance: snapshot.data['balance'] as String,
          );
          _updatedAt = snapshot.updatedAt;
          _isLoading = false;
        });
      }
    }
    if (mounted) await _loadInfo();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadInfo() async {
    if (_isRefreshing) return;
    setState(() {
      _isLoading = _info == null;
      _isRefreshing = true;
      _error = null;
      _refreshError = null;
    });
    try {
      final service = CampusCardService.instance;
      final info = await service.fetchRechargeInfo();
      if (mounted) {
        setState(() {
          _info = info;
          _updatedAt = service.infoUpdatedAt;
          _isLoading = false;
        });
      }
    } catch (e) {
      _logger.e('Failed to load recharge info: $e');
      if (mounted) {
        setState(() {
          if (_info == null) _error = e.toString();
          _refreshError = '更新失败，显示上次余额';
          _isLoading = false;
        });
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  void _handlePresetAmountSelect(double amount) {
    setState(() {
      _selectedAmount = amount;
      _amountController.text = amount.toStringAsFixed(0);
    });
  }

  Future<void> _handleRecharge(PaymentMethod method) async {
    final amountText = _amountController.text.trim();
    final amount = int.tryParse(amountText);

    if (amount == null || amount < 1 || amount > 1000) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入 1–1000 元的整数金额')));
      return;
    }

    if (_info == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => CampusCardPaymentSheet(
        amount: amountText,
        merchantName: '校园卡充值',
        info: _info!,
        paymentMethod: method,
      ),
    ).then((_) {
      if (mounted) _loadInfo();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final amount = int.tryParse(_amountController.text.trim());
    final canRecharge = _info != null && amount != null && amount >= 1 && amount <= 1000;
    return Scaffold(
      appBar: AppBar(
        title: const Text('校园卡充值'),
        actions: [
          IconButton(
            tooltip: '刷新余额',
            onPressed: _isRefreshing ? null : _loadInfo,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '校园卡账单',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CampusCardBillPage()),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _RechargeError(message: _error!, onRetry: _loadInfo)
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.credit_card_outlined, color: colors.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _info?.name ?? '校园卡',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.titleSmall
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '卡号 ${_info?.idserial ?? '---'}',
                                      style: Theme.of(context).textTheme.bodySmall
                                          ?.copyWith(color: colors.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              if (_isRefreshing)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            '可用余额',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '¥ ${_info?.balance ?? '0.00'}',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _refreshError ??
                                (_updatedAt == null
                                    ? '余额尚未更新'
                                    : '更新于 ${_updatedAt!.month}/${_updatedAt!.day} ${_updatedAt!.hour.toString().padLeft(2, '0')}:${_updatedAt!.minute.toString().padLeft(2, '0')}'),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _refreshError == null
                                  ? colors.onSurfaceVariant
                                  : colors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            '选择充值金额',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '1–1000 元',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 2.25,
                          ),
                      itemCount: _presetAmounts.length,
                      itemBuilder: (context, index) {
                        final value = _presetAmounts[index];
                        final selected = _selectedAmount == value;
                        return _AmountOption(
                          amount: value,
                          selected: selected,
                          onTap: () => _handlePresetAmountSelect(value),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: '其他金额',
                        prefixText: '¥ ',
                        suffixText: '元',
                        filled: true,
                        fillColor: colors.surfaceContainerLow,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: colors.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: colors.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: colors.primary, width: 1.5),
                        ),
                      ),
                      onChanged: (_) => setState(() => _selectedAmount = null),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '支付方式',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          avatar: SvgPicture.string(kWechatSvg, width: 18, height: 18),
                          label: const Text('微信支付'),
                          selected: _paymentMethod == PaymentMethod.wechat,
                          onSelected: (_) => setState(
                            () => _paymentMethod = PaymentMethod.wechat,
                          ),
                        ),
                        ChoiceChip(
                          avatar: SvgPicture.string(kAlipaySvg, width: 18, height: 18),
                          label: const Text('支付宝'),
                          selected: _paymentMethod == PaymentMethod.alipay,
                          onSelected: (_) => setState(
                            () => _paymentMethod = PaymentMethod.alipay,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _info == null || _error != null
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(top: BorderSide(color: colors.outlineVariant)),
                ),
                child: SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: canRecharge
                        ? () => _handleRecharge(_paymentMethod)
                        : null,
                    child: Text(
                      canRecharge ? '确认充值  ¥${amount.toString()}' : '选择充值金额',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _AmountOption extends StatelessWidget {
  const _AmountOption({
    required this.amount,
    required this.selected,
    required this.onTap,
  });

  final double amount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.primaryContainer : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Text(
            '¥ ${amount.toStringAsFixed(0)}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: selected ? colors.onPrimaryContainer : colors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _RechargeError extends StatelessWidget {
  const _RechargeError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.credit_card_off_outlined, size: 36, color: colors.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
