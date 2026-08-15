import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppBackgroundSettings {
  const AppBackgroundSettings({this.imagePath, this.blurSigma = 0});

  final String? imagePath;
  final double blurSigma;

  bool get hasImage => imagePath != null && imagePath!.isNotEmpty;

  AppBackgroundSettings copyWith({String? imagePath, double? blurSigma}) {
    return AppBackgroundSettings(
      imagePath: imagePath ?? this.imagePath,
      blurSigma: blurSigma ?? this.blurSigma,
    );
  }
}

final appBackgroundProvider =
    StateNotifierProvider<AppBackgroundNotifier, AppBackgroundSettings>((ref) {
      return AppBackgroundNotifier();
    });

class AppBackgroundNotifier extends StateNotifier<AppBackgroundSettings> {
  AppBackgroundNotifier() : super(const AppBackgroundSettings()) {
    _load();
  }

  static const _pathKey = 'app_background_path';
  static const _blurKey = 'app_background_blur';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_pathKey);
    final blur = prefs.getDouble(_blurKey) ?? 0;
    final validPath = path != null && await File(path).exists() ? path : null;
    state = AppBackgroundSettings(
      imagePath: validPath,
      blurSigma: blur.clamp(0, 30),
    );
  }

  Future<void> importImage(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) return;

    final directory = await getApplicationDocumentsDirectory();
    final dotIndex = sourcePath.lastIndexOf('.');
    final extension = dotIndex >= 0 ? sourcePath.substring(dotIndex) : '.jpg';
    final oldPath = state.imagePath;
    final targetPath =
        '${directory.path}${Platform.pathSeparator}custom_app_background_'
        '${DateTime.now().millisecondsSinceEpoch}$extension';
    final saved = await source.copy(targetPath);

    state = AppBackgroundSettings(
      imagePath: saved.path,
      blurSigma: state.blurSigma,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pathKey, saved.path);

    final managedPrefix =
        '${directory.path}${Platform.pathSeparator}custom_app_background_';
    if (oldPath != null && oldPath.startsWith(managedPrefix)) {
      final oldFile = File(oldPath);
      if (await oldFile.exists()) await oldFile.delete();
    }
  }

  Future<void> updateBlur(double value) async {
    final normalized = value.clamp(0, 30).toDouble();
    state = state.copyWith(blurSigma: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_blurKey, normalized);
  }

  Future<void> clear() async {
    final path = state.imagePath;
    state = AppBackgroundSettings(blurSigma: state.blurSigma);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pathKey);

    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }
}
