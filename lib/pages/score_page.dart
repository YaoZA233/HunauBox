import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/score_model.dart';
import '../providers/score_provider.dart';
import '../widgets/campus_loading_mark.dart';
import '../widgets/campus_progress_bar.dart';
import 'score_analysis_page.dart';

class ScorePage extends ConsumerWidget {
  const ScorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scoreProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('成绩查询'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ScoreAnalysisPage()),
            ),
            icon: const Icon(Icons.insights_outlined),
            tooltip: '成绩分析',
          ),
          IconButton(
            onPressed: state.isLoading
                ? null
                : () => ref.read(scoreProvider.notifier).fetchInitialData(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新成绩',
          ),
        ],
      ),
      body: Column(
        children: [
          _SemesterBar(
            state: state,
            onChanged: (semester) =>
                ref.read(scoreProvider.notifier).changeSemester(semester),
          ),
          if (state.scores.isNotEmpty) _Overview(scores: state.scores),
          if (state.isLoading ||
              state.errorMessage != null ||
              state.cachedAt != null)
            _DataStatus(state: state),
          const Divider(height: 1),
          Expanded(
            child: _ScoreList(
              state: state,
              onRetry: () =>
                  ref.read(scoreProvider.notifier).fetchInitialData(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SemesterBar extends StatelessWidget {
  const _SemesterBar({required this.state, required this.onChanged});
  final ScoreState state;
  final ValueChanged<SemesterModel> onChanged;

  @override
  Widget build(BuildContext context) {
    if (state.semesters.isEmpty && !state.isLoading) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
      child: Row(
        children: [
          Text('学期', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(width: 18),
          if (state.isLoading && state.semesters.isEmpty)
            const CampusLoadingMark(size: 16)
          else
            Expanded(
              child: DropdownButton<SemesterModel>(
                value: state.selectedSemester,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                icon: Icon(
                  Icons.expand_more_rounded,
                  color: colors.onSurfaceVariant,
                ),
                items: state.semesters
                    .map(
                      (semester) => DropdownMenuItem(
                        value: semester,
                        child: Text(
                          semester.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: state.isLoading
                    ? null
                    : (value) {
                        if (value != null) onChanged(value);
                      },
              ),
            ),
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.scores});
  final List<ScoreModel> scores;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final numeric = scores
        .map((item) => double.tryParse(item.score))
        .whereType<double>()
        .toList();
    final average = numeric.isEmpty
        ? null
        : numeric.reduce((a, b) => a + b) / numeric.length;
    final credits = scores
        .map((item) => double.tryParse(item.credit ?? ''))
        .whereType<double>()
        .fold<double>(0, (sum, value) => sum + value);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 5, 20, 9),
      child: Row(
        children: [
          _Metric(value: '${scores.length}', label: '课程'),
          const SizedBox(width: 30),
          _Metric(
            value: average == null ? '—' : average.toStringAsFixed(1),
            label: '平均分',
          ),
          const SizedBox(width: 30),
          _Metric(value: credits.toStringAsFixed(1), label: '学分'),
          const Spacer(),
          Icon(Icons.auto_graph_rounded, color: colors.primary, size: 20),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _DataStatus extends StatelessWidget {
  const _DataStatus({required this.state});
  final ScoreState state;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final time = state.cachedAt?.toLocal();
    final timeLabel = time == null
        ? null
        : '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final hasError = state.errorMessage != null;
    final message = hasError
        ? (state.scores.isEmpty ? '成绩同步失败' : '更新失败，继续显示已保存成绩')
        : state.isLoading
        ? (state.scores.isEmpty ? '正在同步成绩…' : '正在更新成绩')
        : timeLabel == null
        ? null
        : '最近更新 $timeLabel';
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 7),
      child: Row(
        children: [
          if (state.isLoading && !hasError)
            CampusLoadingMark(size: 14, color: colors.primary)
          else
            Icon(
              hasError ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
              size: 16,
              color: hasError ? colors.error : colors.onSurfaceVariant,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: hasError ? colors.error : colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreList extends StatelessWidget {
  const _ScoreList({required this.state, required this.onRetry});
  final ScoreState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.scores.isEmpty) {
      return const Center(child: CampusLoadingMark(size: 36));
    }
    if (state.errorMessage != null && state.scores.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(state.errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (state.scores.isEmpty) {
      return Center(
        child: Text(
          '本学期暂无成绩数据',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.only(top: 2, bottom: 20),
          itemCount: state.scores.length,
          separatorBuilder: (_, _) =>
              const Divider(height: 1, indent: 20, endIndent: 20),
          itemBuilder: (_, index) => _ScoreRow(score: state.scores[index]),
        ),
        if (state.isLoading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: CampusProgressBar(value: null, minHeight: 2),
          ),
      ],
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({required this.score});
  final ScoreModel score;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final value = double.tryParse(score.score);
    final failed = value != null ? value < 60 : score.score == '不及格';
    final excellent = value != null ? value >= 90 : score.score == '优秀';
    final scoreColor = failed
        ? colors.error
        : excellent
        ? colors.tertiary
        : colors.onSurface;
    final details = <String>[
      if (score.credit?.isNotEmpty == true) '${score.credit} 学分',
      if (score.examType?.isNotEmpty == true) score.examType!,
      if (score.dailyScore?.isNotEmpty == true) '平时 ${score.dailyScore}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  score.courseName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    details.join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            score.score,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: scoreColor,
            ),
          ),
        ],
      ),
    );
  }
}
