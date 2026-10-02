/// A temporary override for one occurrence of a course.
///
/// The original timetable remains intact; this record only describes how a
/// specific week should be displayed. Keeping it separate also makes syncing
/// a new timetable safe and reversible.
class TimetableAdjustment {
  const TimetableAdjustment({
    required this.id,
    required this.courseId,
    required this.sourceWeek,
    required this.sourceDay,
    required this.targetWeek,
    required this.targetDay,
    required this.targetStartPeriod,
    required this.targetEndPeriod,
    this.cancelled = false,
    this.note = '',
  });

  final String id;
  final String courseId;
  final int sourceWeek;
  final int sourceDay;
  final int targetWeek;
  final int targetDay;
  final int targetStartPeriod;
  final int targetEndPeriod;
  final bool cancelled;
  final String note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseId': courseId,
        'sourceWeek': sourceWeek,
        'sourceDay': sourceDay,
        'targetWeek': targetWeek,
        'targetDay': targetDay,
        'targetStartPeriod': targetStartPeriod,
        'targetEndPeriod': targetEndPeriod,
        'cancelled': cancelled,
        'note': note,
      };

  factory TimetableAdjustment.fromJson(Map<String, dynamic> json) {
    return TimetableAdjustment(
      id: json['id']?.toString() ?? '',
      courseId: json['courseId']?.toString() ?? '',
      sourceWeek: (json['sourceWeek'] as num?)?.toInt() ?? 1,
      sourceDay: (json['sourceDay'] as num?)?.toInt() ?? 1,
      targetWeek: (json['targetWeek'] as num?)?.toInt() ?? 1,
      targetDay: (json['targetDay'] as num?)?.toInt() ?? 1,
      targetStartPeriod: (json['targetStartPeriod'] as num?)?.toInt() ?? 1,
      targetEndPeriod: (json['targetEndPeriod'] as num?)?.toInt() ?? 2,
      cancelled: json['cancelled'] == true,
      note: json['note']?.toString() ?? '',
    );
  }
}
