import 'package:shared_preferences/shared_preferences.dart';

class OnboardingStore {
  const OnboardingStore();
  static const completionKey = 'onboarding_completed_v1';

  Future<bool> isComplete() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(completionKey) ?? false;
  }

  Future<void> complete() async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setBool(completionKey, true)) {
      throw StateError('引导状态保存失败');
    }
  }
}
