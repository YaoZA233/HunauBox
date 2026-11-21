import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/score_model.dart';
import '../services/score_cache_store.dart';
import '../services/score_service.dart';

class ScoreState {
  final bool isLoading;
  final List<ScoreModel> scores;
  final List<SemesterModel> semesters;
  final SemesterModel? selectedSemester;
  final String? errorMessage;
  final DateTime? cachedAt;

  ScoreState({
    required this.isLoading,
    required this.scores,
    required this.semesters,
    this.selectedSemester,
    this.errorMessage,
    this.cachedAt,
  });

  ScoreState.initial()
      : isLoading = true,
        scores = const [],
        semesters = const [],
        selectedSemester = null,
        errorMessage = null,
        cachedAt = null;

  ScoreState copyWith({
    bool? isLoading,
    List<ScoreModel>? scores,
    List<SemesterModel>? semesters,
    SemesterModel? selectedSemester,
    String? errorMessage,
    DateTime? cachedAt,
    bool clearError = false,
  }) {
    return ScoreState(
      isLoading: isLoading ?? this.isLoading,
      scores: scores ?? this.scores,
      semesters: semesters ?? this.semesters,
      selectedSemester: selectedSemester ?? this.selectedSemester,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      cachedAt: cachedAt ?? this.cachedAt,
    );
  }
}

class ScoreNotifier extends StateNotifier<ScoreState> {
  ScoreNotifier({ScoreState? initialState, bool fetchOnCreate = true})
    : super(initialState ?? ScoreState.initial()) {
    if (fetchOnCreate) fetchInitialData();
  }

  final _service = ScoreService.instance;
  final _cache = ScoreCacheStore();
  final Map<String, List<ScoreModel>> _scoresBySemester = {};
  String? _cacheOwner;
  int _requestId = 0;

  Future<void> fetchInitialData() async {
    final requestId = ++_requestId;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final owner = await _cache.account();
      if (!mounted || requestId != _requestId) return;
      if (_cacheOwner != owner) {
        _scoresBySemester.clear();
        _cacheOwner = owner;
      }
      final cached = await _cache.read(owner: owner);
      if (!mounted || requestId != _requestId) return;
      if (cached != null) {
        _scoresBySemester
          ..clear()
          ..addAll(cached.scoresBySemester);
        final selected = cached.semesters.where(
          (item) => item.value == cached.selectedSemester,
        );
        final cachedSemester = selected.isNotEmpty
            ? selected.first
            : cached.semesters.where((item) => item.isActive).firstOrNull ??
                  cached.semesters.firstOrNull;
        state = state.copyWith(
          semesters: cached.semesters,
          scores: cachedSemester == null
              ? const []
              : cached.scoresBySemester[cachedSemester.value] ?? const [],
          selectedSemester: cachedSemester,
          cachedAt: cached.updatedAt,
        );
      }

      final data = await _service.fetchScores();
      if (!mounted || requestId != _requestId) return;
      final semesters = (data['semesters'] as List<SemesterModel>);
      final scores = (data['scores'] as List<ScoreModel>);

      final SemesterModel? active = semesters.cast<SemesterModel?>().firstWhere(
            (s) => s?.isActive ?? false,
            orElse: () => semesters.isNotEmpty ? semesters.first : null,
          );

      _scoresBySemester[active?.value ?? ''] = scores;
      final now = DateTime.now();
      await _cache.write(
        owner: owner,
        semesters: semesters,
        scoresBySemester: _scoresBySemester,
        selectedSemester: active?.value,
        updatedAt: now,
      );
      if (!mounted || requestId != _requestId) return;
      state = state.copyWith(
        isLoading: false,
        semesters: semesters,
        scores: scores,
        selectedSemester: active,
        cachedAt: now,
        clearError: true,
      );
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> changeSemester(SemesterModel semester) async {
    if (semester == state.selectedSemester) return;
    final requestId = ++_requestId;
    final cachedScores = _scoresBySemester[semester.value];
    state = state.copyWith(
      isLoading: true,
      selectedSemester: semester,
      scores: cachedScores ?? const [],
      clearError: true,
    );

    try {
      final owner = await _cache.account();
      if (!mounted || requestId != _requestId) return;
      if (_cacheOwner != owner) {
        _scoresBySemester.clear();
        _cacheOwner = owner;
      }
      final data = await _service.fetchScores(xn: semester.value, xq: semester.xq);
      if (!mounted || requestId != _requestId) return;
      final scores = data['scores'] as List<ScoreModel>;
      _scoresBySemester[semester.value] = scores;
      final now = DateTime.now();
      await _cache.write(
        owner: owner,
        semesters: state.semesters,
        scoresBySemester: _scoresBySemester,
        selectedSemester: semester.value,
        updatedAt: now,
      );
      if (!mounted || requestId != _requestId) return;
      state = state.copyWith(
        isLoading: false,
        scores: scores,
        cachedAt: now,
        clearError: true,
      );
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
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
