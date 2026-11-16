import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chaoxing_course.dart';
import '../services/app_cookie_manager.dart';
import '../services/chaoxing_cache_store.dart';
import '../services/chaoxing_course_service.dart';
import '../services/session_cookie_manager.dart';

final chaoxingCacheProvider = Provider((ref) => ChaoxingCacheStore());
final chaoxingCourseFetcherProvider =
    Provider<Future<List<ChaoxingCourse>> Function()>((ref) {
      return () async {
        final cookies = AppCookieManager();
        await cookies.initialize();
        final dio = Dio(
          BaseOptions(connectTimeout: const Duration(seconds: 20)),
        );
        try {
          dio.interceptors.add(SessionCookieManager(cookies.dioCookieJar));
          return await ChaoxingCourseService(dio).fetchCourses();
        } finally {
          dio.close(force: true);
        }
      };
    });

/// Never let an unexpected empty refresh erase a previously useful snapshot.
void validateCourseRefresh(
  Map<String, dynamic>? cached,
  List<ChaoxingCourse> result,
) {
  final previous = cached?['items'];
  if (result.isEmpty && previous is List && previous.isNotEmpty) {
    throw const ChaoxingCourseException('本次未获取到课程，已保留上次的结果，请稍后重试或打开学习通确认');
  }
}

Future<List<ChaoxingCourse>> fetchAndCacheCourses(
  ChaoxingCacheStore cache,
  Future<List<ChaoxingCourse>> Function() fetch,
) async {
  final owner = await cache.account();
  final result = await fetch();
  if (owner != await cache.account()) throw StateError('账号已切换');
  final cached = await cache.read('courses');
  if (owner != await cache.account()) throw StateError('账号已切换');
  validateCourseRefresh(cached, result);
  await cache.write(owner, 'courses', {
    'items': result.map((c) => c.toJson()).toList(),
    'updatedAt': DateTime.now().toIso8601String(),
    'verifiedEmpty': result.isEmpty,
  });
  return result;
}

final chaoxingCoursesProvider =
    FutureProvider.autoDispose<List<ChaoxingCourse>>((ref) async {
      final cached = await ref.read(chaoxingCacheProvider).read('courses');
      try {
        final items = cached?['items'];
        if (items is List &&
            (items.isNotEmpty || cached?['verifiedEmpty'] == true)) {
          return items
              .map(
                (item) => ChaoxingCourse.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList();
        }
      } catch (_) {
        /* Invalid cache is treated as absent. */
      }
      return fetchAndCacheCourses(
        ref.read(chaoxingCacheProvider),
        ref.read(chaoxingCourseFetcherProvider),
      );
    });
