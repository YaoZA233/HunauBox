import 'package:flutter/material.dart';

import '../models/campus_card_bill.dart';
import '../services/campus_card_bill_service.dart';
import '../widgets/campus_loading_mark.dart';

class CampusCardBillPage extends StatefulWidget {
  const CampusCardBillPage({super.key, this.loadBills});
  final Future<List<CampusCardBill>> Function(CampusCardBillQuery)? loadBills;

  @override
  State<CampusCardBillPage> createState() => _CampusCardBillPageState();
}

class _CampusCardBillPageState extends State<CampusCardBillPage> {
  late DateTime _begin;
  late DateTime _end;
  CampusCardTradeType _type = CampusCardTradeType.all;
  List<CampusCardBill> _records = [];
  bool _loading = false;
  bool _queried = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _end = DateUtils.dateOnly(DateTime.now());
    _begin = DateTime(_end.year, _end.month, _end.day - 6);
    _query();
  }

  Future<void> _query() async {
    if (_loading) return;
    final query = CampusCardBillQuery(
      beginDate: _begin,
      endDate: _end,
      type: _type,
    );
    final validation = query.validate();
    setState(() {
      _error = validation;
      _queried = true;
      _records = [];
      _loading = validation == null;
    });
    if (validation != null) return;
    try {
      final records =
          await (widget.loadBills ?? CampusCardBillService.instance.query)(
            query,
          );
      if (!mounted) return;
      setState(() {
        _records = records;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is CampusCardBillException
            ? error.message
            : '账单加载失败，请稍后重试';
      });
    }
  }

  void _changeFilters(VoidCallback update) {
    setState(() {
      update();
      _records = [];
      _queried = false;
      _error = null;
    });
  }

  Future<void> _pickDate(bool begin) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: begin ? _begin : _end,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: begin ? '选择开始日期' : '选择结束日期',
    );
    if (picked != null && mounted) {
      _changeFilters(() {
        if (begin) {
          _begin = picked;
        } else {
          _end = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('校园卡账单')),
      body: RefreshIndicator(
        onRefresh: _query,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            Text('校园卡交易', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 5),
            Text(
              '按日期和类型筛选账户流水',
              style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            _buildFilters(colors),
            const SizedBox(height: 22),
            Row(
              children: [
                Text(
                  '交易记录',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (_queried && !_loading && _error == null)
                  Text(
                    '${_records.length} 笔',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CampusLoadingMark(size: 36)),
              )
            else if (_error != null)
              _message(context, Icons.cloud_off_outlined, _error!, retry: true)
            else if (!_queried)
              _message(
                context,
                Icons.manage_search_outlined,
                '条件已修改，点击“查询账单”查看记录',
              )
            else if (_records.isEmpty)
              _message(context, Icons.receipt_long_outlined, '所选日期和类型下暂无交易记录')
            else
              Column(
                children: [
                  for (var i = 0; i < _records.length; i++) ...[
                    _BillRow(record: _records[i], fallback: _type),
                    if (i < _records.length - 1)
                      Divider(height: 1, color: colors.outlineVariant),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '查询范围',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _DateSelector(
                label: '开始日期',
                date: _begin,
                enabled: !_loading,
                onTap: () => _pickDate(true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DateSelector(
                label: '结束日期',
                date: _end,
                enabled: !_loading,
                onTap: () => _pickDate(false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        Wrap(
          spacing: 7,
          runSpacing: 2,
          children: [
            for (final type in CampusCardTradeType.values)
              ChoiceChip(
                label: Text(type.label),
                selected: _type == type,
                visualDensity: VisualDensity.compact,
                onSelected: _loading
                    ? null
                    : (_) => _changeFilters(() => _type = type),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                '默认近 7 天 · 最长 31 天',
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _query,
              icon: const Icon(Icons.search_rounded, size: 18),
              label: Text(_loading ? '查询中' : '查询账单'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _message(
    BuildContext context,
    IconData icon,
    String text, {
    bool retry = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
    child: Column(
      children: [
        Icon(
          icon,
          size: 36,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center),
        if (retry) TextButton(onPressed: _query, child: const Text('重试')),
      ],
    ),
  );
}

class _BillRow extends StatelessWidget {
  const _BillRow({required this.record, required this.fallback});
  final CampusCardBill record;
  final CampusCardTradeType fallback;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final type = CampusCardTradeType.values
        .where(
          (t) => t != CampusCardTradeType.all && t.value == record.tradeType,
        )
        .firstOrNull;
    final label =
        type?.label ??
        (fallback == CampusCardTradeType.all ? '交易' : fallback.label);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  record.merchantName.trim().isEmpty
                      ? '校园卡交易'
                      : record.merchantName,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                record.amount.isEmpty ? '金额未提供' : '¥ ${record.amount}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$label · ${record.time.isEmpty ? '时间未提供' : record.time}',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DateSelector extends StatelessWidget {
  const _DateSelector({
    required this.label,
    required this.date,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      CampusCardBillQuery.formatDate(date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.calendar_month_outlined,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
