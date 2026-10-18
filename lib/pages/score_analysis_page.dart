import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/score_model.dart';
import '../services/score_service.dart';

class ScoreAnalysisPage extends StatefulWidget {
  const ScoreAnalysisPage({super.key, this.loadScores});
  final Future<Map<SemesterModel, List<ScoreModel>>> Function()? loadScores;

  @override
  State<ScoreAnalysisPage> createState() => _ScoreAnalysisPageState();
}

class _ScoreAnalysisPageState extends State<ScoreAnalysisPage> {
  late Future<_AnalysisSnapshot> _analysisFuture;

  @override
  void initState() {
    super.initState();
    _analysisFuture = _load();
  }

  Future<_AnalysisSnapshot> _load() async => _AnalysisSnapshot.from(
    await (widget.loadScores ?? ScoreService.instance.fetchAllScores)(),
  );

  Future<void> _reload() async {
    final next = _load();
    setState(() {
      _analysisFuture = next;
    });
    // FutureBuilder renders errors; also consume this future for pull-to-refresh.
    try {
      await next;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('成绩分析'),
      actions: [
        IconButton(
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: '重新分析',
        ),
      ],
    ),
    body: FutureBuilder<_AnalysisSnapshot>(
      future: _analysisFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError ||
            snapshot.data == null ||
            snapshot.data!.isEmpty) {
          return _AnalysisStatus(error: snapshot.hasError, onRetry: _reload);
        }
        return RefreshIndicator(
          onRefresh: _reload,
          child: _AnalysisContent(analysis: snapshot.data!),
        );
      },
    ),
  );
}

class _AnalysisContent extends StatelessWidget {
  const _AnalysisContent({required this.analysis});
  final _AnalysisSnapshot analysis;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.insights_rounded, color: colors.onPrimaryContainer),
              const SizedBox(height: 12),
              Text(
                analysis.headline,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${analysis.semesters.length} 个学期 · ${analysis.courseCount} 门课程 · ${analysis.totalCredits.toStringAsFixed(1)} 学分',
                style: TextStyle(color: colors.onPrimaryContainer, height: 1.5),
              ),
            ],
          ),
        ),
        const _SectionTitle(title: '整体表现', caption: '所有已获取成绩的统计'),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
            final columns = constraints.maxWidth / scale >= 720
                ? 4
                : constraints.maxWidth / scale >= 280
                ? 2
                : 1;
            final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricCard(
                  width: width,
                  label: '累计均分',
                  value: '${analysis.average.toStringAsFixed(1)} 分',
                  icon: Icons.auto_graph_rounded,
                ),
                _MetricCard(
                  width: width,
                  label: '通过率',
                  value: '${analysis.passRate.toStringAsFixed(1)}%',
                  icon: Icons.check_circle_outline_rounded,
                ),
                _MetricCard(
                  width: width,
                  label: '修读课程',
                  value: '${analysis.courseCount} 门',
                  icon: Icons.menu_book_outlined,
                ),
                _MetricCard(
                  width: width,
                  label: '优秀成绩',
                  value: '${analysis.excellentCount} 门',
                  icon: Icons.stars_outlined,
                ),
              ],
            );
          },
        ),
        const _SectionTitle(title: '学期趋势', caption: '按时间从早到晚排列，图下可查看完整学期数据'),
        _AnalysisCard(child: _TrendChart(stats: analysis.semesters)),
        const _SectionTitle(title: '成绩分布', caption: '各成绩区间的课程数量和占比'),
        _AnalysisCard(
          child: Column(
            children: [
              for (var i = 0; i < analysis.distribution.length; i++) ...[
                _DistributionRow(item: analysis.distribution[i]),
                if (i < analysis.distribution.length - 1)
                  const SizedBox(height: 20),
              ],
            ],
          ),
        ),
        const _SectionTitle(title: '学期明细', caption: '均分、通过率与较上一学期的变化'),
        for (final stat in analysis.semesters) ...[
          _SemesterCard(stat: stat),
          const SizedBox(height: 12),
        ],
        if (analysis.topCourses.isNotEmpty) ...[
          const _SectionTitle(title: '表现亮眼', caption: '成绩最高的课程'),
          _CourseGroup(courses: analysis.topCourses),
        ],
        if (analysis.needsAttention.isNotEmpty) ...[
          const _SectionTitle(title: '值得关注', caption: '成绩低于 75 分的课程，优先关注较低分项'),
          _CourseGroup(courses: analysis.needsAttention),
        ],
        const SizedBox(height: 24),
        Text(
          '统计说明：均分为课程成绩的算术平均，未按学分加权；60 分及以上计为通过，90 分及以上计为优秀。等级制成绩按对应区间估算，暂无成绩的课程不参与分析。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.caption});
  final String title;
  final String caption;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          caption,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
  });
  final double width;
  final String label;
  final String value;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: _AnalysisCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DistributionRow extends StatelessWidget {
  const _DistributionRow({required this.item});
  final _DistributionItem item;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = switch (item.label) {
      '90+' => '90 分及以上',
      '<60' => '60 分以下',
      _ => '${item.label} 分',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            Text(
              label,
              style: TextStyle(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${item.count} 门 · ${(item.ratio * 100).toStringAsFixed(1)}%',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: item.ratio,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
          color: colors.primary,
          backgroundColor: colors.surfaceContainerHighest,
          semanticsLabel: '$label，${item.count} 门',
        ),
      ],
    );
  }
}

class _SemesterCard extends StatelessWidget {
  const _SemesterCard({required this.stat});
  final _SemesterStat stat;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delta = stat.delta;
    final change = delta == null
        ? '首个学期'
        : delta == 0
        ? '较上一学期持平'
        : '较上一学期${delta > 0 ? '上升' : '下降'} ${delta.abs().toStringAsFixed(1)} 分';
    return _AnalysisCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stat.name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              Text(
                '均分 ${stat.average.toStringAsFixed(1)} 分',
                style: theme.textTheme.titleMedium,
              ),
              Text(
                '通过率 ${stat.passRate.toStringAsFixed(1)}%',
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                '${stat.courseCount} 门课程',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: (stat.average / 100).clamp(0.0, 1.0),
            minHeight: 6,
            color: theme.colorScheme.primary,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 10),
          Text(
            change,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CourseGroup extends StatelessWidget {
  const _CourseGroup({required this.courses});
  final List<_CourseScore> courses;
  @override
  Widget build(BuildContext context) => _AnalysisCard(
    child: Column(
      children: [
        for (var i = 0; i < courses.length; i++) ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                courses[i].name,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                '${courses[i].score.toStringAsFixed(1)} 分',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (i < courses.length - 1) const Divider(height: 28),
        ],
      ],
    ),
  );
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.stats});
  final List<_SemesterStat> stats;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            _Legend(color: colors.primary, label: '均分（分）'),
            _Legend(color: colors.tertiary, label: '通过率（%）'),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          '纵轴 0–100 · 横轴为学期顺序',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final slot = math.max(84.0, 72 * scale);
            final axisWidth = 32 * scale;
            final chartHeight = math.max(160.0, 100 * scale);
            final width = math.max(
              constraints.maxWidth - axisWidth - 8,
              stats.length * slot,
            );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: axisWidth,
                  height: chartHeight,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final value in [100, 75, 50, 25, 0])
                        Text(
                          '$value',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: width,
                      child: Column(
                        children: [
                          Semantics(
                            label: '学期均分和通过率趋势；详细数值见下方学期明细',
                            image: true,
                            child: SizedBox(
                              height: chartHeight,
                              width: width,
                              child: CustomPaint(
                                painter: _TrendPainter(
                                  stats: stats,
                                  averageColor: colors.primary,
                                  passColor: colors.tertiary,
                                  gridColor: colors.outlineVariant,
                                  surface: colors.surface,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < stats.length; i++)
                                Expanded(
                                  child: Text(
                                    '学期 ${i + 1}',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < stats.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${i + 1} · ${stats[i].name}',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Text(label),
    ],
  );
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.stats,
    required this.averageColor,
    required this.passColor,
    required this.gridColor,
    required this.surface,
  });
  final List<_SemesterStat> stats;
  final Color averageColor;
  final Color passColor;
  final Color gridColor;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final chart = Rect.fromLTRB(0, 8, size.width, size.height - 8);
    for (var i = 0; i <= 4; i++) {
      final y = chart.top + chart.height * i / 4;
      canvas.drawLine(
        Offset(0, y),
        Offset(chart.right, y),
        Paint()
          ..color = gridColor
          ..strokeWidth = 1,
      );
    }
    void series(Color color, double Function(_SemesterStat) value) {
      final points = [
        for (var i = 0; i < stats.length; i++)
          Offset(
            size.width * (i + 0.5) / stats.length,
            chart.bottom - chart.height * value(stats[i]).clamp(0, 100) / 100,
          ),
      ];
      if (points.isEmpty) return;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke,
      );
      for (final point in points) {
        canvas.drawCircle(point, 4, Paint()..color = color);
        canvas.drawCircle(point, 1.5, Paint()..color = surface);
      }
    }

    series(passColor, (stat) => stat.passRate);
    series(averageColor, (stat) => stat.average);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.stats != stats ||
      old.averageColor != averageColor ||
      old.passColor != passColor ||
      old.gridColor != gridColor ||
      old.surface != surface;
}

class _AnalysisStatus extends StatelessWidget {
  const _AnalysisStatus({required this.error, required this.onRetry});
  final bool error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            error ? Icons.cloud_off_outlined : Icons.insights_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            error ? '暂时无法获取完整成绩' : '还没有可分析的成绩',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            error ? '请检查网络或登录状态，稍后再试。' : '获取到成绩后，这里会显示统计和学期趋势。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新获取'),
          ),
        ],
      ),
    ),
  );
}

class _AnalysisSnapshot {
  _AnalysisSnapshot({
    required this.semesters,
    required this.distribution,
    required this.average,
    required this.passRate,
    required this.courseCount,
    required this.excellentCount,
    required this.totalCredits,
    required this.topCourses,
    required this.needsAttention,
  });

  final List<_SemesterStat> semesters;
  final List<_DistributionItem> distribution;
  final double average;
  final double passRate;
  final int courseCount;
  final int excellentCount;
  final double totalCredits;
  final List<_CourseScore> topCourses;
  final List<_CourseScore> needsAttention;

  bool get isEmpty => courseCount == 0;

  String get headline {
    if (semesters.length < 2) return '你的第一份成绩画像';
    final delta = semesters.last.average - semesters.first.average;
    if (delta >= 3) return '保持这个节奏，成绩在稳步上扬';
    if (delta <= -3) return '找到变化的原因，下一学期会更好';
    return '基础稳定，继续积累每一次进步';
  }

  factory _AnalysisSnapshot.from(Map<SemesterModel, List<ScoreModel>> source) {
    final semesterStats = <_SemesterStat>[];
    final allCourses = <_CourseScore>[];
    var totalCredits = 0.0;

    final entries = source.entries.toList()
      ..sort((a, b) => a.key.value.compareTo(b.key.value));
    for (final entry in entries) {
      final scored = entry.value
          .map(_CourseScore.from)
          .whereType<_CourseScore>()
          .toList();
      if (scored.isEmpty) continue;
      final average =
          scored.map((e) => e.score).reduce((a, b) => a + b) / scored.length;
      final passed = scored.where((e) => e.score >= 60).length;
      totalCredits += entry.value.fold(
        0.0,
        (sum, score) => sum + (double.tryParse(score.credit ?? '') ?? 0),
      );
      semesterStats.add(
        _SemesterStat(
          name: entry.key.name,
          average: average,
          passRate: passed / scored.length * 100,
          courseCount: scored.length,
          delta: null,
        ),
      );
      allCourses.addAll(scored);
    }

    for (var i = 1; i < semesterStats.length; i++) {
      final current = semesterStats[i];
      semesterStats[i] = current.copyWith(
        delta: current.average - semesterStats[i - 1].average,
      );
    }
    final count = allCourses.length;
    final double average = count == 0
        ? 0.0
        : allCourses.map((e) => e.score).reduce((a, b) => a + b) / count;
    final passed = allCourses.where((e) => e.score >= 60).length;
    final excellent = allCourses.where((e) => e.score >= 90).length;
    final buckets = [
      ('90+', 90.0, 100.0, const Color(0xFFD28A3D)),
      ('80-89', 80.0, 90.0, const Color(0xFF4C8A72)),
      ('70-79', 70.0, 80.0, const Color(0xFF5A80A8)),
      ('60-69', 60.0, 70.0, const Color(0xFF8A6D9E)),
      ('<60', 0.0, 60.0, const Color(0xFFD9785E)),
    ];
    final distribution = buckets.map((bucket) {
      final bucketCount = allCourses
          .where(
            (course) =>
                (course.score >= bucket.$2 && course.score < bucket.$3) ||
                (bucket.$1 == '90+' && course.score >= 90),
          )
          .length;
      return _DistributionItem(
        label: bucket.$1,
        count: bucketCount,
        ratio: count == 0 ? 0 : bucketCount / count,
        color: bucket.$4,
      );
    }).toList();
    final sorted = [...allCourses]..sort((a, b) => b.score.compareTo(a.score));
    final low = [...allCourses]..sort((a, b) => a.score.compareTo(b.score));
    return _AnalysisSnapshot(
      semesters: semesterStats,
      distribution: distribution,
      average: average,
      passRate: count == 0 ? 0.0 : passed / count * 100,
      courseCount: count,
      excellentCount: excellent,
      totalCredits: totalCredits,
      topCourses: sorted.take(math.min(3, sorted.length)).toList(),
      needsAttention: low
          .where((course) => course.score < 75)
          .take(math.min(3, low.length))
          .toList(),
    );
  }
}

class _SemesterStat {
  const _SemesterStat({
    required this.name,
    required this.average,
    required this.passRate,
    required this.courseCount,
    required this.delta,
  });

  final String name;
  final double average;
  final double passRate;
  final int courseCount;
  final double? delta;

  _SemesterStat copyWith({double? delta}) => _SemesterStat(
    name: name,
    average: average,
    passRate: passRate,
    courseCount: courseCount,
    delta: delta ?? this.delta,
  );
}

class _DistributionItem {
  const _DistributionItem({
    required this.label,
    required this.count,
    required this.ratio,
    required this.color,
  });

  final String label;
  final int count;
  final double ratio;
  final Color color;
}

class _CourseScore {
  const _CourseScore({required this.name, required this.score});

  final String name;
  final double score;

  static _CourseScore? from(ScoreModel model) {
    final value = double.tryParse(model.score);
    if (value != null && value.isFinite && value >= 0 && value <= 100) {
      return _CourseScore(name: model.courseName, score: value);
    }
    final mapped = switch (model.score.trim()) {
      '优秀' => 95.0,
      '良好' => 85.0,
      '中等' => 75.0,
      '及格' => 60.0,
      '不及格' => 40.0,
      _ => null,
    };
    return mapped == null
        ? null
        : _CourseScore(name: model.courseName, score: mapped);
  }
}
