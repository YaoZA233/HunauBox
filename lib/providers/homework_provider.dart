import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import '../models/homework_model.dart';
import '../services/homework_service.dart';
import '../services/homework_storage.dart';
import '../services/app_cookie_manager.dart';
import '../services/secure_storage_helper.dart';
import '../services/course_notification_service.dart';

final homeworkServiceProvider = Provider((ref) {
  final dio = Dio();
  dio.interceptors.add(CookieManager(AppCookieManager().dioCookieJar));
  return HomeworkService(dio);
});

final homeworkStorageProvider = Provider((ref) => HomeworkStorage());

final homeworkProvider =
    StateNotifierProvider<HomeworkNotifier, AsyncValue<List<HomeworkModel>>>((
      ref,
    ) {
      return HomeworkNotifier(ref);
    });

class HomeworkNotifier extends StateNotifier<AsyncValue<List<HomeworkModel>>> {
  final Ref _ref;
  late final Future<void> _initialization;

  HomeworkNotifier(this._ref) : super(const AsyncValue.loading()) {
    _initialization = _init();
  }

  Future<void> _init() async {
    // 先读缓存
    final cached = await _ref.read(homeworkStorageProvider).readHomeworkList();
    if (cached != null) {
      state = AsyncValue.data(cached);
    } else {
      state = const AsyncValue.data([]);
    }
  }

  Future<void> refresh() async {
    final previousHomework = state.value ?? const <HomeworkModel>[];
    try {
      final username = await SecureStorageHelper().getUsername();
      if (username == null) return;
      state = const AsyncValue.loading();
      await AppCookieManager().syncMultiDomainCookiesFromWebView();

      final scraped = await _ref
          .read(homeworkServiceProvider)
          .fetchHomeworkList(username);

      final manualList = previousHomework.where((e) => e.isManual).toList();

      // 合并：保留手动，更新爬取
      final combined = [...scraped, ...manualList];

      await _ref.read(homeworkStorageProvider).saveHomeworkList(combined);
      state = AsyncValue.data(combined);
      await CourseNotificationService.instance.notifyNewHomework(
        scraped.where((item) => item.status == HomeworkStatus.pending).toList(),
      );
      await CourseNotificationService.instance.rescheduleIfEnabled();
    } catch (e, st) {
      // 保留原有数据并报出错误
      final current = state.value ?? [];
      state = AsyncValue<List<HomeworkModel>>.error(
        e,
        st,
      ).copyWithPrevious(AsyncValue.data(current));
    }
  }

  void toggleStatus(String id) {
    if (state.value == null) return;
    final list = state.value!.map((item) {
      if (item.id == id) {
        final nextStatus = item.status == HomeworkStatus.completed
            ? HomeworkStatus.pending
            : HomeworkStatus.completed;
        return item.copyWith(status: nextStatus);
      }
      return item;
    }).toList();

    _ref.read(homeworkStorageProvider).saveHomeworkList(list);
    state = AsyncValue.data(list);
    CourseNotificationService.instance.rescheduleIfEnabled();
  }

  /// Agent 修改只适用于手动作业；持久化成功后才更新 UI。
  Future<void> addManualHomework(
    HomeworkModel item, {
    void Function()? checkActive,
  }) async {
    await _initialization;
    checkActive?.call();
    if (state.isLoading || state.value == null) throw StateError('作业仍在加载');
    if (!item.isManual) throw ArgumentError('仅支持手动作业');
    final list = [...state.value!, item];
    await _ref
        .read(homeworkStorageProvider)
        .saveHomeworkList(list, throwOnError: true);
    state = AsyncValue.data(list);
    try {
      await CourseNotificationService.instance.rescheduleIfEnabled();
    } catch (_) {}
  }

  Future<void> completeManualHomework(
    String id, {
    void Function()? checkActive,
  }) async {
    await _initialization;
    checkActive?.call();
    if (state.isLoading || state.value == null) throw StateError('作业仍在加载');
    final item = state.value!.firstWhere((h) => h.id == id);
    if (!item.isManual) throw ArgumentError('学习通作业必须在学习通完成');
    final list = state.value!
        .map(
          (h) => h.id == id ? h.copyWith(status: HomeworkStatus.completed) : h,
        )
        .toList();
    await _ref
        .read(homeworkStorageProvider)
        .saveHomeworkList(list, throwOnError: true);
    state = AsyncValue.data(list);
    try {
      await CourseNotificationService.instance.rescheduleIfEnabled();
    } catch (_) {}
  }

  Future<void> clearAll() async {
    await _ref.read(homeworkStorageProvider).deleteHomeworkList();
    state = const AsyncValue.data([]);
    await CourseNotificationService.instance.rescheduleIfEnabled();
  }
}
