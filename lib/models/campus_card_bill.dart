enum CampusCardTradeType {
  all('-1', '全部'),
  consume('1', '消费'),
  recharge('2', '充值'),
  subsidy('3', '补助'),
  transfer('4', '转账');

  const CampusCardTradeType(this.value, this.label);
  final String value;
  final String label;
}

class CampusCardBill {
  const CampusCardBill({
    required this.merchantName,
    required this.amount,
    required this.time,
    this.tradeType = '',
  });

  final String merchantName;
  // Preserve the server's currency unit and sign; do not infer debit/credit
  // from an amount when the server omits the transaction type.
  final String amount;
  final String time;
  final String tradeType;

  factory CampusCardBill.fromJson(Map<String, dynamic> json) => CampusCardBill(
    merchantName: (json['mername'] ?? json['mercname'] ?? '').toString(),
    amount: (json['txamt'] ?? '').toString(),
    time: (json['txdate'] ?? json['paytime'] ?? '').toString(),
    tradeType:
        (json['tradeType'] ??
                json['tradetype'] ??
                json['type'] ??
                json['txtype'] ??
                '')
            .toString(),
  );
}

class CampusCardBillQuery {
  const CampusCardBillQuery({
    required this.beginDate,
    required this.endDate,
    this.type = CampusCardTradeType.all,
  });

  final DateTime beginDate;
  final DateTime endDate;
  final CampusCardTradeType type;

  static DateTime _day(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);

  String? validate({DateTime? now}) {
    final begin = _day(beginDate);
    final end = _day(endDate);
    if (begin.isAfter(end)) return '开始日期不能晚于结束日期';
    if (end.isAfter(_day(now ?? DateTime.now()))) return '结束日期不能超过今天';
    if (end.difference(begin).inDays > 31) return '起止日期间隔不能超过 31 天';
    return null;
  }

  static String formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
