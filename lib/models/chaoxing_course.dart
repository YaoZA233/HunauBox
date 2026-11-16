class ChaoxingCourse {
  const ChaoxingCourse({
    required this.id,
    required this.name,
    required this.url,
    this.teacher = '',
    this.school = '',
    this.coverUrl = '',
    this.schedule = '',
    this.folder = '',
    this.personInfo = '',
    this.finishedJobs,
    this.totalJobs,
  });

  final String id;
  final String name;
  final String url;
  final String teacher;
  final String school;
  final String coverUrl;
  final String schedule;
  final String folder;
  final String personInfo;
  final int? finishedJobs;
  final int? totalJobs;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'teacher': teacher,
    'school': school,
    'coverUrl': coverUrl,
    'schedule': schedule,
    'folder': folder,
    'personInfo': personInfo,
    'finishedJobs': finishedJobs,
    'totalJobs': totalJobs,
  };

  factory ChaoxingCourse.fromJson(Map<String, dynamic> json) => ChaoxingCourse(
    id: json['id'] as String,
    name: json['name'] as String,
    url: json['url'] as String,
    teacher: json['teacher'] as String? ?? '',
    school: json['school'] as String? ?? '',
    coverUrl: json['coverUrl'] as String? ?? '',
    schedule: json['schedule'] as String? ?? '',
    folder: json['folder'] as String? ?? '',
    personInfo: json['personInfo'] as String? ?? '',
    finishedJobs: json['finishedJobs'] as int?,
    totalJobs: json['totalJobs'] as int?,
  );

  double? get progress =>
      totalJobs != null && totalJobs! > 0 && finishedJobs != null
      ? (finishedJobs! / totalJobs!).clamp(0.0, 1.0)
      : null;

  ChaoxingCourse withJobs(int finished, int total) => ChaoxingCourse(
    id: id,
    name: name,
    url: url,
    teacher: teacher,
    school: school,
    coverUrl: coverUrl,
    schedule: schedule,
    folder: folder,
    personInfo: personInfo,
    finishedJobs: finished,
    totalJobs: total,
  );
}
