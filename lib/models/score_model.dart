class ScoreModel {
  final String courseName;
  final String score;
  final String? credit;
  final String? dailyScore;
  final String? examType;

  ScoreModel({
    required this.courseName,
    required this.score,
    this.credit,
    this.dailyScore,
    this.examType,
  });

  @override
  String toString() => 'ScoreModel(courseName: $courseName, score: $score)';
}

class SemesterModel {
  final String value;
  final String xq;
  final String name;
  final bool isActive;

  SemesterModel({
    required this.value,
    required this.xq,
    required this.name,
    this.isActive = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SemesterModel && runtimeType == other.runtimeType && value == other.value && xq == other.xq;

  @override
  int get hashCode => value.hashCode ^ xq.hashCode;
}
