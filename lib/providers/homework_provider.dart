import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import '../models/homework_model.dart';
import '../services/homework_service.dart';
import '../services/homework_storage.dart';
import '../services/app_cookie_manager.dart';
import '../services/secure_storage_helper.dart';

final homeworkServiceProvider = Provider((ref) {
  final dio = Dio();
  dio.interceptors.add(CookieManager(AppCookieManager().dioCookieJar));
  return HomeworkService(dio);
});

final homeworkStorageProvider = Provider((ref) => HomeworkStorage());

final homeworkProvider = StateNotifierProvider<HomeworkNotifier, AsyncValue<List<HomeworkModel>>>((ref) {
  return HomeworkNotifier(ref);
});

class HomeworkNotifier extends StateNotifier<AsyncValue<List<HomeworkModel>>> {
  final Ref _ref;

  HomeworkNotifier(this._ref) : super(const AsyncValue.loading()) {
    _init();
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
    try {
      final username = await SecureStorageHelper().getUsername();
      if (username == null) return;
      state = const AsyncValue.loading();
      await AppCookieManager().syncMultiDomainCookiesFromWebView();

      final scraped = await _ref.read(homeworkServiceProvider).fetchHomeworkList(username);

      final current = state.value ?? [];
      final manualList = current.where((e) => e.isManual).toList();

      // 合并：保留手动，更新爬取
      final combined = [...scraped, ...manualList];
      
      await _ref.read(homeworkStorageProvider).saveHomeworkList(combined);
      state = AsyncValue.data(combined);
    } catch (e, st) {
      // 保留原有数据并报出错误
      final current = state.value ?? [];
      state = AsyncValue<List<HomeworkModel>>.error(e, st).copyWithPrevious(AsyncValue.data(current));
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
  }

  Future<void> clearAll() async {
    await _ref.read(homeworkStorageProvider).deleteHomeworkList();
    state = const AsyncValue.data([]);
  }
}
