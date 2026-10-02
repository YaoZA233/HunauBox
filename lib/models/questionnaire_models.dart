import 'package:html/parser.dart' as html;

/// 问卷说明含 HTML 时仅展示文本，不执行服务端页面脚本。
String questionnaireText(Object? value) {
  return html.parseFragment(value?.toString() ?? '').text?.trim() ?? '';
}

class QuestionnaireItem {
  const QuestionnaireItem({
    required this.dm,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.taskTimeM,
    this.doneInd = '',
    this.flag = '',
    this.zt = '',
    this.shzt = '',
  });

  final String dm;
  final String title;
  final String startTime;
  final String endTime;
  final String taskTimeM;
  final String doneInd;
  final String flag;
  final String zt;
  final String shzt;

  factory QuestionnaireItem.fromJson(Map<String, dynamic> json) =>
      QuestionnaireItem(
        dm: (json['DM'] ?? '').toString(),
        title: questionnaireText(json['MC']),
        startTime: (json['KSSJ'] ?? '').toString(),
        endTime: (json['JSSJ'] ?? '').toString(),
        taskTimeM: (json['TASK_TIME_M'] ?? '').toString(),
        doneInd: (json['DONE_IND'] ?? '').toString(),
        flag: (json['FLAG'] ?? '').toString(),
        zt: (json['ZT'] ?? '').toString(),
        shzt: (json['SHZT'] ?? '').toString(),
      );

  bool get isSubmitted => zt == '1' || shzt == '1' || doneInd == '1';
  bool get isExpired =>
      DateTime.tryParse(endTime)?.isBefore(DateTime.now()) ?? false;
  bool get isUpcoming =>
      DateTime.tryParse(startTime)?.isAfter(DateTime.now()) ?? false;
  bool get isPending => !isSubmitted && !isExpired && !isUpcoming;
  String get statusLabel => isSubmitted
      ? '已提交'
      : isExpired
      ? '已截止'
      : isUpcoming
      ? '未开始'
      : '待填写';
}

class QuestionnaireOption {
  const QuestionnaireOption({required this.dm, required this.name});
  final String dm;
  final String name;

  factory QuestionnaireOption.fromJson(Map<String, dynamic> json) =>
      QuestionnaireOption(
        dm: (json['dm'] ?? '').toString(),
        name: questionnaireText(json['mc']),
      );
}

class QuestionnaireQuestion {
  const QuestionnaireQuestion({
    required this.dm,
    required this.title,
    this.desc = '',
    this.stType = '',
    this.txType = '',
    this.required = false,
    this.options = const [],
    this.answer = '',
  });
  final String dm;
  final String title;
  final String desc;
  final String stType;
  final String txType;
  final bool required;
  final List<QuestionnaireOption> options;
  final String answer;

  factory QuestionnaireQuestion.fromJson(Map<String, dynamic> json) {
    final options = json['stxxList'];
    return QuestionnaireQuestion(
      dm: (json['dm'] ?? '').toString(),
      title: questionnaireText(json['stmc']),
      desc: questionnaireText(json['stsm']),
      stType: (json['stType'] ?? '').toString(),
      txType: (json['txType'] ?? '').toString(),
      required: (json['btInd'] ?? '').toString() == '1',
      answer: questionnaireText(json['jg']),
      options: options is List
          ? options
                .whereType<Map>()
                .map(
                  (e) => QuestionnaireOption.fromJson(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .toList()
          : const [],
    );
  }

  bool get isChoice => options.isNotEmpty || stType == '1' || stType == '2';
  bool get isMultiChoice => stType == '2';
  bool get isDate => stType == '4' && (txType == '3' || txType == '4');
  bool get isPhone => stType == '4' && txType == '2';
  bool get isSupported => stType == '1' || stType == '2' || stType == '4';
  String get typeLabel => isMultiChoice
      ? '多选'
      : isChoice
      ? '单选'
      : isDate
      ? '日期'
      : '填空';

  /// 已提交答案可能是选项 ID，也可能是选项名称；只做精确匹配。
  dynamic get initialAnswer {
    if (!isChoice) return answer;
    String? resolve(String value) {
      for (final option in options) {
        if (option.dm == value || option.name == value) return option.dm;
      }
      return null;
    }

    if (!isMultiChoice) return resolve(answer.trim()) ?? '';
    return answer
        .split(RegExp(r'[,，、;；]'))
        .map((e) => resolve(e.trim()))
        .whereType<String>()
        .toSet()
        .toList();
  }

  bool isAnswered(dynamic value) => value is List
      ? value.isNotEmpty
      : value is String && value.trim().isNotEmpty;
}

class QuestionnaireDetail {
  const QuestionnaireDetail({
    required this.dm,
    required this.title,
    required this.jgM,
    this.desc = '',
    this.canSubmit = true,
    this.questions = const [],
  });
  final String dm;
  final String title;
  final String desc;
  final String jgM;
  final bool canSubmit;
  final List<QuestionnaireQuestion> questions;

  factory QuestionnaireDetail.fromJson(Map<String, dynamic> json) {
    final questions = json['stList'];
    return QuestionnaireDetail(
      dm: (json['dm'] ?? '').toString(),
      title: questionnaireText(json['mc'] ?? json['sm']),
      desc: questionnaireText(json['sm'] ?? json['bz']),
      jgM: (json['jgM'] ?? '').toString(),
      canSubmit:
          json['canSubmit'] == true ||
          (json['canSubmit'] ?? '1').toString() == '1',
      questions: questions is List
          ? questions
                .whereType<Map>()
                .map(
                  (e) => QuestionnaireQuestion.fromJson(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .toList()
          : const [],
    );
  }

  String? validate(Map<String, dynamic> answers) {
    if (!canSubmit) return '该问卷当前不可提交';
    if (jgM.isEmpty ||
        questions.isEmpty ||
        questions.any((q) => q.dm.isEmpty) ||
        questions.map((q) => q.dm).toSet().length != questions.length) {
      return '问卷数据不完整，请刷新后重试';
    }
    for (final q in questions) {
      if (!q.isSupported) return '问卷包含暂不支持的题型，请在学工系统网页填写';
      final value = answers[q.dm];
      if (q.required && !q.isAnswered(value)) return '请填写：${q.title}';
      if (q.isChoice && q.isAnswered(value)) {
        final values = q.isMultiChoice && value is List
            ? value
            : !q.isMultiChoice && value is String
            ? [value]
            : null;
        if (values == null ||
            values.any((v) => !q.options.any((o) => o.dm == v))) {
          return '请重新选择：${q.title}';
        }
      }
      if (q.isDate &&
          q.isAnswered(value) &&
          DateTime.tryParse(value.toString()) == null) {
        return '请选择有效日期：${q.title}';
      }
    }
    return null;
  }
}
