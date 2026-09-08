import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/score_model.dart';
import '../services/score_service.dart';

class ScoreAnalysisPage extends StatefulWidget {
  const ScoreAnalysisPage({super.key});

  @override
  State<ScoreAnalysisPage> createState() => _ScoreAnalysisPageState();
}

class _ScoreAnalysisPageState extends State<ScoreAnalysisPage> {
  late Future<_AnalysisSnapshot> _analysisFuture;

  @override
  void initState() {
    super.initState();
    _analysisFuture = _loadAnalysis();
  }

  Future<_AnalysisSnapshot> _loadAnalysis() async {
    final allScores = await ScoreService.instance.fetchAllScores();
    return _AnalysisSnapshot.from(allScores);
  }

  void _reload() {
    setState(() => _analysisFuture = _loadAnalysis());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          if (snapshot.hasError) {
            return _AnalysisError(onRetry: _reload);
          }
          final analysis = snapshot.data!;
          if (analysis.isEmpty) {
            return _AnalysisEmpty(onRetry: _reload);
          }
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _analysisFuture;
            },
            child: _AnalysisContent(analysis: analysis),
          );
        },
      ),
    );
  }
}

class _AnalysisContent extends StatelessWidget {
  const _AnalysisContent({required this.analysis});

  final _AnalysisSnapshot analysis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _AnalysisIntro(analysis: analysis),
        const SizedBox(height: 16),
        _SectionTitle(title: '整体表现', caption: '把零散成绩汇成一条清晰的线'),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.72,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _MetricCard(
              label: '累计均分',
              value: analysis.average.toStringAsFixed(1),
              suffix: '分',
              icon: Icons.auto_graph_rounded,
              color: primary,
            ),
            _MetricCard(
              label: '通过率',
              value: analysis.passRate.toStringAsFixed(0),
              suffix: '%',
              icon: Icons.check_circle_outline_rounded,
              color: const Color(0xFF4C8A72),
            ),
            _MetricCard(
              label: '修读课程',
              value: '${analysis.courseCount}',
              suffix: '门',
              icon: Icons.menu_book_rounded,
              color: const Color(0xFF5A80A8),
            ),
            _MetricCard(
              label: '优秀成绩',
              value: '${analysis.excellentCount}',
              suffix: '门',
              icon: Icons.stars_rounded,
              color: const Color(0xFFD28A3D),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _SectionTitle(title: '学期趋势', caption: '均分和通过率的变化'),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
            child: Column(
              children: [
                _TrendChart(analysis: analysis, primary: primary),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _LegendDot(color: primary, label: '学期均分'),
                    const SizedBox(width: 20),
                    _LegendDot(color: const Color(0xFFD28A3D), label: '通过率'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        _SectionTitle(title: '成绩结构', caption: '看看分数集中在哪个区间'),
        const SizedBox(height: 10),
        _DistributionCard(items: analysis.distribution),
        const SizedBox(height: 22),
        _SectionTitle(title: '学期均分', caption: '柱状图更直观地比较每个学期'),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
            child: _SemesterBarChart(analysis: analysis, color: primary),
          ),
        ),
        const SizedBox(height: 22),
        _SectionTitle(title: '学期对比', caption: '每一学期都值得被看见'),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < analysis.semesters.length; i++) ...[
                _SemesterRow(stat: analysis.semesters[i]),
                if (i < analysis.semesters.length - 1)
                  Divider(height: 1, color: theme.dividerColor),
              ],
            ],
          ),
        ),
        if (analysis.topCourses.isNotEmpty ||
            analysis.needsAttention.isNotEmpty) ...[
          const SizedBox(height: 22),
          _SectionTitle(title: '课程画像', caption: '优势要保持，短板有方向'),
          const SizedBox(height: 10),
          _CourseInsightPanel(analysis: analysis),
        ],
        const SizedBox(height: 20),
        Text(
          '分析基于已获取的数字成绩，等级制成绩会按对应区间估算。',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: onSurface.withValues(alpha: 0.52),
          ),
        ),
      ],
    );
  }
}

class _AnalysisIntro extends StatelessWidget {
  const _AnalysisIntro({required this.analysis});

  final _AnalysisSnapshot analysis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.insights_rounded,
            color: theme.colorScheme.primary,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  analysis.headline,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${analysis.semesters.length} 个学期 · ${analysis.courseCount} 门课程 · ${analysis.totalCredits.toStringAsFixed(1)} 学分',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.78,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.suffix,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String suffix;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 20, color: color),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 3),
                Padding(
                  padding: const EdgeInsets.only(bottom: 1),
                  child: Text(suffix, style: theme.textTheme.labelMedium),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.caption});

  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            caption,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.analysis, required this.primary});

  final _AnalysisSnapshot analysis;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    final width = math.max(340.0, analysis.semesters.length * 68.0);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: width,
        height: 198,
        child: CustomPaint(
          painter: _TrendPainter(
            stats: analysis.semesters,
            lineColor: primary,
            passColor: const Color(0xFFD28A3D),
            gridColor: theme.dividerColor,
            textColor: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _DistributionCard extends StatelessWidget {
  const _DistributionCard({required this.items});

  final List<_DistributionItem> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 390;
            final chartSize = compact ? 142.0 : 158.0;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: chartSize,
                  height: chartSize,
                  child: CustomPaint(painter: _PiePainter(items: items)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        _DistributionRow(item: items[i]),
                        if (i < items.length - 1) const SizedBox(height: 11),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SemesterBarChart extends StatelessWidget {
  const _SemesterBarChart({required this.analysis, required this.color});

  final _AnalysisSnapshot analysis;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = math.max(340.0, analysis.semesters.length * 68.0);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: width,
        height: 208,
        child: CustomPaint(
          painter: _BarPainter(
            stats: analysis.semesters,
            barColor: color,
            gridColor: theme.dividerColor,
            textColor: theme.colorScheme.onSurfaceVariant,
          ),
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
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(item.label, style: theme.textTheme.bodySmall),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: item.ratio,
              minHeight: 9,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(item.color),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 56,
          child: Text(
            '${item.count} 门',
            textAlign: TextAlign.end,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _SemesterRow extends StatelessWidget {
  const _SemesterRow({required this.stat});

  final _SemesterStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trendColor = stat.delta == null
        ? theme.colorScheme.onSurfaceVariant
        : stat.delta! >= 0
        ? const Color(0xFF4C8A72)
        : const Color(0xFFD9785E);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.name,
                  softWrap: true,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${stat.courseCount} 门课程 · 通过率 ${stat.passRate.toStringAsFixed(0)}%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (stat.delta != null)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Text(
                '${stat.delta! >= 0 ? '+' : ''}${stat.delta!.toStringAsFixed(1)}',
                style: theme.textTheme.labelMedium?.copyWith(color: trendColor),
              ),
            ),
          Text(
            stat.average.toStringAsFixed(1),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: trendColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseInsightPanel extends StatelessWidget {
  const _CourseInsightPanel({required this.analysis});

  final _AnalysisSnapshot analysis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          children: [
            if (analysis.topCourses.isNotEmpty)
              _CourseGroup(
                title: '表现亮眼',
                icon: Icons.trending_up_rounded,
                color: const Color(0xFF4C8A72),
                courses: analysis.topCourses,
              ),
            if (analysis.topCourses.isNotEmpty &&
                analysis.needsAttention.isNotEmpty)
              Divider(height: 24, color: theme.dividerColor),
            if (analysis.needsAttention.isNotEmpty)
              _CourseGroup(
                title: '值得关注',
                icon: Icons.flag_outlined,
                color: const Color(0xFFD9785E),
                courses: analysis.needsAttention,
              ),
          ],
        ),
      ),
    );
  }
}

class _CourseGroup extends StatelessWidget {
  const _CourseGroup({
    required this.title,
    required this.icon,
    required this.color,
    required this.courses,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<_CourseScore> courses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 7),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(color: color),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final course in courses)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(child: Text(course.name, softWrap: true)),
                Text(
                  course.score.toStringAsFixed(0),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.stats,
    required this.lineColor,
    required this.passColor,
    required this.gridColor,
    required this.textColor,
  });

  final List<_SemesterStat> stats;
  final Color lineColor;
  final Color passColor;
  final Color gridColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (stats.isEmpty) return;
    const left = 34.0;
    const right = 12.0;
    const top = 10.0;
    const bottom = 30.0;
    final chart = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.65)
      ..strokeWidth = 0.8;
    final labelStyle = TextStyle(fontSize: 10, color: textColor);

    for (var i = 0; i <= 4; i++) {
      final y = chart.top + chart.height * i / 4;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      final label = '${100 - i * 25}';
      _drawText(canvas, label, Offset(0, y - 6), labelStyle);
    }

    final averagePoints = <Offset>[];
    final passPoints = <Offset>[];
    for (var i = 0; i < stats.length; i++) {
      final x = stats.length == 1
          ? chart.center.dx
          : chart.left + chart.width * i / (stats.length - 1);
      final averageY = _valueToY(chart, stats[i].average);
      final passY = _valueToY(chart, stats[i].passRate);
      averagePoints.add(Offset(x, averageY));
      passPoints.add(Offset(x, passY));
      if (stats.length <= 7 || i.isEven || i == stats.length - 1) {
        _drawText(
          canvas,
          _shortSemesterLabel(stats[i].name, i),
          Offset(x - 16, chart.bottom + 9),
          labelStyle,
        );
      }
    }

    _drawSeries(canvas, averagePoints, lineColor);
    _drawSeries(canvas, passPoints, passColor);
  }

  double _valueToY(Rect chart, double value) {
    final normalized = (value.clamp(0, 100).toDouble() / 100).clamp(0.0, 1.0);
    return (chart.bottom - normalized * chart.height).clamp(
      chart.top,
      chart.bottom,
    );
  }

  void _drawSeries(Canvas canvas, List<Offset> points, Color color) {
    if (points.isEmpty) return;
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, linePaint);
    final dotPaint = Paint()..color = color;
    for (final point in points) {
      canvas.drawCircle(point, 4, dotPaint);
      canvas.drawCircle(point, 1.8, Paint()..color = Colors.white);
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.stats != stats ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.passColor != passColor;
}

class _PiePainter extends CustomPainter {
  _PiePainter({required this.items});

  final List<_DistributionItem> items;

  @override
  void paint(Canvas canvas, Size size) {
    final total = items.fold<int>(0, (sum, item) => sum + item.count);
    if (total == 0) return;
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    final stroke = radius * 0.30;
    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);
    var start = -math.pi / 2;
    for (final item in items) {
      if (item.count == 0) continue;
      final sweep = item.count / total * math.pi * 2;
      final paint = Paint()
        ..color = item.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
    canvas.drawCircle(
      center,
      radius * 0.35,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    final totalPainter = TextPainter(
      text: TextSpan(
        text: '$total',
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    totalPainter.paint(
      canvas,
      center - Offset(totalPainter.width / 2, totalPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) =>
      oldDelegate.items != items;
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.stats,
    required this.barColor,
    required this.gridColor,
    required this.textColor,
  });

  final List<_SemesterStat> stats;
  final Color barColor;
  final Color gridColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (stats.isEmpty) return;
    const left = 34.0;
    const right = 12.0;
    const top = 10.0;
    const bottom = 35.0;
    final chart = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final labelStyle = TextStyle(fontSize: 10, color: textColor);
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.65)
      ..strokeWidth = 0.8;
    for (var i = 0; i <= 4; i++) {
      final y = chart.top + chart.height * i / 4;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      _drawText(canvas, '${100 - i * 10}', Offset(0, y - 6), labelStyle);
    }
    final slot = chart.width / stats.length;
    final barWidth = math.min(34.0, slot * 0.54);
    for (var i = 0; i < stats.length; i++) {
      final x = chart.left + slot * i + (slot - barWidth) / 2;
      final value = stats[i].average.clamp(60, 100).toDouble();
      final topY = chart.bottom - ((value - 60) / 40) * chart.height;
      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(x, topY, x + barWidth, chart.bottom),
        const Radius.circular(6),
      );
      canvas.drawRRect(
        barRect,
        Paint()..color = barColor.withValues(alpha: 0.86),
      );
      _drawText(
        canvas,
        _shortSemesterLabel(stats[i].name, i),
        Offset(x + barWidth / 2 - 16, chart.bottom + 10),
        labelStyle,
      );
      _drawText(
        canvas,
        stats[i].average.toStringAsFixed(1),
        Offset(x + barWidth / 2 - 12, topY - 17),
        labelStyle,
      );
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _BarPainter oldDelegate) =>
      oldDelegate.stats != stats || oldDelegate.barColor != barColor;
}

String _shortSemesterLabel(String name, int index) {
  final match = RegExp(r'(\d{4})[-—–至](\d{4}).*').firstMatch(name);
  if (match != null) {
    return '${match.group(1)!.substring(2)}-${match.group(2)!.substring(2)}';
  }
  final compact = name.replaceAll('学年', '').replaceAll('学期', '');
  return compact.length > 7 ? '第${index + 1}学期' : compact;
}

class _AnalysisError extends StatelessWidget {
  const _AnalysisError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            const Text(
              '暂时无法获取完整成绩',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '请检查网络或登录状态，稍后再试。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
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
}

class _AnalysisEmpty extends StatelessWidget {
  const _AnalysisEmpty({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_graph_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            const Text(
              '还没有可分析的成绩',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '获取到成绩后，这里会自动生成学期趋势。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('再试一次'),
            ),
          ],
        ),
      ),
    );
  }
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

    for (final entry in source.entries) {
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
    if (value != null) {
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
