import 'package:flutter/material.dart';

import '../models/campus_card_bill.dart';
import '../services/campus_card_bill_service.dart';

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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '查询条件',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _loading ? null : () => _pickDate(true),
                          icon: const Icon(
                            Icons.calendar_today_outlined,
                            size: 18,
                          ),
                          label: Text(
                            '开始 ${CampusCardBillQuery.formatDate(_begin)}',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _loading ? null : () => _pickDate(false),
                          icon: const Icon(Icons.event_outlined, size: 18),
                          label: Text(
                            '结束 ${CampusCardBillQuery.formatDate(_end)}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final type in CampusCardTradeType.values)
                          ChoiceChip(
                            label: Text(type.label),
                            selected: _type == type,
                            onSelected: _loading
                                ? null
                                : (_) => _changeFilters(() => _type = type),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '默认查询近 7 天，起止日期间隔最长 31 天。',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _loading ? null : _query,
                      icon: const Icon(Icons.search_rounded),
                      label: Text(_loading ? '正在查询…' : '查询账单'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _queried && !_loading && _error == null
                  ? '交易记录 · ${_records.length} 笔'
                  : '交易记录',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '金额单位为元，按校园卡平台返回的金额与时间显示。',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
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
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < _records.length; i++) ...[
                      _BillRow(record: _records[i], fallback: _type),
                      if (i < _records.length - 1)
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            record.merchantName.trim().isEmpty ? '校园卡交易' : record.merchantName,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: colors.onSurface),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                '$label · ${record.time.isEmpty ? '时间未提供' : record.time}',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              Text(
                record.amount.isEmpty ? '金额未提供' : '¥ ${record.amount}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
