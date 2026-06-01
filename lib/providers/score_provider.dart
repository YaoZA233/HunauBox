import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/score_model.dart';
import '../services/score_service.dart';

class ScoreState {
  final bool isLoading;
  final List<ScoreModel> scores;
  final List<SemesterModel> semesters;
  final SemesterModel? selectedSemester;
  final String? errorMessage;

  ScoreState({
    required this.isLoading,
    required this.scores,
    required this.semesters,
    this.selectedSemester,
    this.errorMessage,
  });

  ScoreState.initial()
      : isLoading = true,
        scores = const [],
        semesters = const [],
        selectedSemester = null,
        errorMessage = null;

  ScoreState copyWith({
    bool? isLoading,
    List<ScoreModel>? scores,
    List<SemesterModel>? semesters,
    SemesterModel? selectedSemester,
    String? errorMessage,
  }) {
    return ScoreState(
      isLoading: isLoading ?? this.isLoading,
      scores: scores ?? this.scores,
      semesters: semesters ?? this.semesters,
      selectedSemester: selectedSemester ?? this.selectedSemester,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class ScoreNotifier extends StateNotifier<ScoreState> {
  ScoreNotifier() : super(ScoreState.initial()) {
    fetchInitialData();
  }

  final _service = ScoreService.instance;

  Future<void> fetchInitialData() async {
    try {
      state = state.copyWith(isLoading: true, errorMessage: null);

      final data = await _service.fetchScores();
      final semesters = (data['semesters'] as List<SemesterModel>);
      final scores = (data['scores'] as List<ScoreModel>);

      final SemesterModel? active = semesters.cast<SemesterModel?>().firstWhere(
            (s) => s?.isActive ?? false,
            orElse: () => semesters.isNotEmpty ? semesters.first : null,
          );

      state = state.copyWith(
        isLoading: false,
        semesters: semesters,
        scores: scores,
        selectedSemester: active,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> changeSemester(SemesterModel semester) async {
    if (semester == state.selectedSemester) return;

    try {
      state = state.copyWith(
        isLoading: true,
        selectedSemester: semester,
        errorMessage: null,
      );

      final data = await _service.fetchScores(xn: semester.value, xq: semester.xq);

      state = state.copyWith(
        isLoading: false,
        scores: data['scores'] as List<ScoreModel>,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }
}

final scoreProvider = StateNotifierProvider.autoDispose<ScoreNotifier, ScoreState>((ref) {
  return ScoreNotifier();
});
