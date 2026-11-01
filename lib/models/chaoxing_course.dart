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
