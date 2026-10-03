import 'package:html/parser.dart' as html;

class SunshineStatistics {
  final int total;
  final int processing;
  final int completed;
  const SunshineStatistics(this.total, this.processing, this.completed);
  factory SunshineStatistics.fromJson(Map<String, dynamic> json) => SunshineStatistics(
        int.tryParse('${json['TCount'] ?? 0}') ?? 0,
        int.tryParse('${json['ZCount'] ?? 0}') ?? 0,
        int.tryParse('${json['YCount'] ?? 0}') ?? 0,
      );
}

class SunshineLetter {
  final String id, title, department, type, date, status;
  const SunshineLetter({required this.id, required this.title, required this.department, required this.type, required this.date, required this.status});
  factory SunshineLetter.fromJson(Map<String, dynamic> json) => SunshineLetter(
        id: '${json['ID'] ?? ''}', title: '${json['Title'] ?? ''}',
        department: '${json['CirDepName'] ?? ''}', type: '${json['bTypeName'] ?? ''}',
        date: '${json['AddTime'] ?? ''}'.split(' ').first, status: '${json['Status'] ?? ''}',
      );
  String get statusLabel => status == '2' ? '已办结' : status == '0' || status == '1' ? '办理中' : '状态未知';
}

class SunshineTicketDetail {
  final String id, title, submitter, expectedDepartment, handlingDepartment, finishTime, status, content, remark, type;
  const SunshineTicketDetail({required this.id, required this.title, required this.submitter, required this.expectedDepartment, required this.handlingDepartment, required this.finishTime, required this.status, required this.content, required this.remark, required this.type});
  factory SunshineTicketDetail.fromJson(Map<String, dynamic> json, {String id = ''}) => SunshineTicketDetail(
        id: id.isEmpty ? '${json['ID'] ?? ''}' : id, title: '${json['Title'] ?? ''}',
        submitter: _surname('${json['LinkName'] ?? ''}'), expectedDepartment: '${json['DepName'] ?? ''}',
        handlingDepartment: '${json['CirDepName'] ?? ''}', finishTime: '${json['FinishTime'] ?? ''}',
        status: '${json['Status'] ?? ''}', content: '${json['Content'] ?? ''}', remark: '${json['Remark'] ?? ''}', type: '${json['bTypeName'] ?? ''}',
      );
  static String _surname(String value) => value.trim().isEmpty ? '' : value.trim().substring(0, 1);
  String get statusLabel => status == '2' ? '已办结' : status == '0' || status == '1' ? '办理中' : '状态未知';
}

class SunshineDepartment {
  final String code, name;
  const SunshineDepartment(this.code, this.name);
  factory SunshineDepartment.fromJson(Map<String, dynamic> json) => SunshineDepartment('${json['Company_code'] ?? ''}', '${json['Company_name'] ?? ''}');
}

class SunshineIdentity {
  final String cardCode, name, phone, email;
  const SunshineIdentity(this.cardCode, this.name, this.phone, this.email);
  static SunshineIdentity? fromHtml(String source) {
    final doc = html.parse(source);
    String value(String id) => doc.getElementById(id)?.attributes['value']?.trim() ?? '';
    final card = value('h_CardCode');
    final name = value('UserName');
    if (card.isEmpty || name.isEmpty) return null;
    return SunshineIdentity(card, name, value('telPhone'), value('email'));
  }
}

class SunshineFormData {
  final SunshineIdentity identity;
  final List<SunshineDepartment> departments;
  const SunshineFormData(this.identity, this.departments);
}
