import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chaoxing_course.dart';
import '../services/app_cookie_manager.dart';
import '../services/chaoxing_course_service.dart';
import '../services/session_cookie_manager.dart';

final chaoxingCoursesProvider =
    FutureProvider.autoDispose<List<ChaoxingCourse>>((ref) async {
      final cookies = AppCookieManager();
      await cookies.initialize();
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 20)));
      ref.onDispose(() => dio.close(force: true));
      dio.interceptors.add(SessionCookieManager(cookies.dioCookieJar));
      return ChaoxingCourseService(dio).fetchCourses();
    });
