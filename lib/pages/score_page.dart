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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('成绩查询'),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ScoreAnalysisPage()),
              );
            },
            icon: const Icon(Icons.insights_rounded),
            tooltip: '成绩分析',
          ),
          IconButton(
            onPressed: () =>
                ref.read(scoreProvider.notifier).fetchInitialData(),
            icon: const Icon(Icons.refresh),
            tooltip: '重新加载',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSemesterPicker(context, ref, state),
          if (state.isLoading || state.errorMessage != null || state.cachedAt != null)
            _buildDataStatus(context, state),
          const Divider(height: 1),
          Expanded(child: _buildScoreList(context, ref, state)),
        ],
      ),
    );
  }

  Widget _buildDataStatus(BuildContext context, ScoreState state) {
    final colors = Theme.of(context).colorScheme;
    final time = state.cachedAt?.toLocal();
    final timeLabel = time == null
        ? null
        : '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final hasError = state.errorMessage != null;
    final message = hasError
        ? (state.scores.isEmpty
              ? '成绩同步失败'
              : '更新失败，显示上次保存的成绩${timeLabel == null ? '' : ' · $timeLabel'}')
        : state.isLoading
        ? (state.scores.isEmpty ? '正在同步成绩…' : '正在更新成绩，先显示已保存数据')
        : timeLabel == null
        ? null
        : '最近更新 $timeLabel';
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Row(
        children: [
          if (state.isLoading && !hasError) ...[
            SizedBox(
              width: 14,
              height: 14,
              child: CampusLoadingMark(size: 14, color: colors.primary),
            ),
          ] else ...[
            Icon(
              hasError ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
              size: 16,
              color: hasError ? colors.error : colors.onSurfaceVariant,
            ),
          ],
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
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

  Widget _buildSemesterPicker(
    BuildContext context,
    WidgetRef ref,
    ScoreState state,
  ) {
    if (state.semesters.isEmpty && !state.isLoading) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          const Text(
            '当前学期',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          if (state.isLoading && state.semesters.isEmpty)
            const SizedBox(
              width: 16,
              height: 16,
              child: CampusLoadingMark(size: 16),
            )
          else
            Expanded(
              child: DropdownButton<SemesterModel>(
                value: state.selectedSemester,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: state.semesters
                    .map(
                      (semester) => DropdownMenuItem<SemesterModel>(
                        value: semester,
                        child: Text(
                          semester.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    ref.read(scoreProvider.notifier).changeSemester(value);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScoreList(
    BuildContext context,
    WidgetRef ref,
    ScoreState state,
  ) {
    if (state.isLoading && state.scores.isEmpty) {
      return const Center(child: CampusLoadingMark(size: 36));
    }

    if (state.errorMessage != null && state.scores.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              state.errorMessage!,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () =>
                  ref.read(scoreProvider.notifier).fetchInitialData(),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (state.scores.isEmpty) {
      return Center(
        child: Text('本学期暂无成绩数据', style: TextStyle(color: Colors.grey[500])),
      );
    }

    return Stack(
      children: [
        ListView.separated(
          itemCount: state.scores.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final score = state.scores[index];
            return _buildScoreItem(score);
          },
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

  Widget _buildScoreItem(ScoreModel score) {
    final isExcellent = _isExcellent(score.score);
    final isFailed = _isFailed(score.score);

    Color scoreColor = const Color(0xFF0F8B57);
    if (isFailed) {
      scoreColor = Colors.red[700]!;
    } else if (isExcellent) {
      scoreColor = Colors.orange[700]!;
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: scoreColor.withOpacity(0.12),
        foregroundColor: scoreColor,
        child: Icon(
          isFailed ? Icons.warning_amber_rounded : Icons.menu_book_rounded,
        ),
      ),
      title: Text(
        score.courseName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '学分 ${score.credit ?? 'N/A'}  ·  ${score.examType ?? '正常考试'}',
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      trailing: Text(
        score.score,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: scoreColor,
        ),
      ),
    );
  }

  bool _isExcellent(String score) {
    final val = double.tryParse(score);
    if (val != null) return val >= 90;
    return score == '优秀';
  }

  bool _isFailed(String score) {
    final val = double.tryParse(score);
    if (val != null) return val < 60;
    return score == '不及格';
  }
}
