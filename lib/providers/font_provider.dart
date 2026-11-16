import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FontImportException implements Exception {
  const FontImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SelectedFontFile {
  const SelectedFontFile({required this.path, required this.name});
  final String path;
  final String name;
}

final fontFilePickerProvider = Provider<Future<SelectedFontFile?> Function()>((
  ref,
) {
  return () async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ttf'],
      allowMultiple: false,
      withData: false,
    );
    if (result == null) return null;
    final file = result.files.single;
    if (file.path == null || file.path!.isEmpty) {
      throw const FontImportException('无法读取所选文件，请重新选择');
    }
    return SelectedFontFile(path: file.path!, name: file.name);
  };
});

class AppFontSettings {
  const AppFontSettings({
    this.family,
    this.name,
    this.loading = false,
    this.ready = false,
    this.error,
  });
  final String? family;
  final String? name;
  final bool loading;
  final bool ready;
  final String? error;
  bool get isCustom => family != null;
}

final appFontProvider = StateNotifierProvider<AppFontNotifier, AppFontSettings>(
  (ref) => AppFontNotifier(),
);

typedef FontRegistrar = Future<void> Function(String family, Uint8List bytes);

class AppFontNotifier extends StateNotifier<AppFontSettings> {
  AppFontNotifier({
    Future<Directory> Function()? directory,
    FontRegistrar? register,
  }) : _directory = directory ?? getApplicationSupportDirectory,
       _register = register ?? _registerFont,
       super(const AppFontSettings(loading: true)) {
    ready = _load();
  }

  static const preferenceKey = 'app_custom_font_v1';
  static const maxFontBytes = 100 * 1024 * 1024;
  static final _registered = <String>{};
  final Future<Directory> Function() _directory;
  final FontRegistrar _register;
  late final Future<void> ready;
  String? _digest;

  static Future<void> _registerFont(String family, Uint8List bytes) async {
    if (_registered.contains(family)) return;
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    _registered.add(family);
  }

  static String _family(String digest) => 'HunauBoxCustomFont_$digest';
  static String _path(Directory directory, String digest) =>
      '${directory.path}${Platform.pathSeparator}hunaubox_font_$digest.ttf';

  /// Check the sfnt header and table ranges before asking the engine to load it.
  static void validate(Uint8List bytes) {
    if (bytes.length < 12 || bytes.length > maxFontBytes) {
      throw const FontImportException('字体文件为空、过大或已损坏');
    }
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(0) != 0x00010000 && data.getUint32(0) != 0x74727565) {
      throw const FontImportException('请选择有效的 .ttf 字体文件');
    }
    final count = data.getUint16(4);
    final headerSize = 12 + count * 16;
    if (count == 0 || count > 512 || headerSize > bytes.length) {
      throw const FontImportException('字体文件已损坏，请更换文件');
    }
    final tables = <String>{};
    for (var i = 0; i < count; i++) {
      final at = 12 + i * 16;
      final tag = String.fromCharCodes(bytes.sublist(at, at + 4));
      final offset = data.getUint32(at + 8);
      final length = data.getUint32(at + 12);
      if (offset < headerSize ||
          offset > bytes.length ||
          length > bytes.length - offset) {
        throw const FontImportException('字体文件已损坏，请更换文件');
      }
      if (length > 0) tables.add(tag);
    }
    if (!tables.containsAll({
      'cmap',
      'head',
      'hhea',
      'hmtx',
      'maxp',
      'loca',
      'glyf',
    })) {
      throw const FontImportException('字体文件不完整，请更换有效的 .ttf 文件');
    }
  }

  Future<Uint8List> _read(File file) async {
    final length = await file.length();
    if (length == 0 || length > maxFontBytes) {
      throw const FontImportException('字体文件为空或超过 100 MB');
    }
    final bytes = await file.readAsBytes();
    validate(bytes);
    return bytes;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(preferenceKey);
      if (stored == null) {
        if (mounted) state = const AppFontSettings(ready: true);
        return;
      }
      final data = jsonDecode(stored);
      if (data is! Map ||
          data['digest'] is! String ||
          data['name'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['digest'] as String)) {
        throw const FontImportException('保存的字体信息无法读取');
      }
      final digest = data['digest'] as String;
      final directory = await _directory();
      final bytes = await _read(File(_path(directory, digest)));
      if (sha256.convert(bytes).toString() != digest) {
        throw const FontImportException('字体文件已改变');
      }
      final family = _family(digest);
      await _register(family, bytes);
      if (!mounted) return;
      _digest = digest;
      state = AppFontSettings(
        family: family,
        name: data['name'] as String,
        ready: true,
      );
    } catch (_) {
      if (mounted) {
        state = const AppFontSettings(
          ready: true,
          error: '上次的字体无法加载，已使用默认字体。请重新导入。',
        );
      }
    }
  }

  Future<void> importFont(SelectedFontFile file) async {
    if (!state.ready || state.loading) {
      throw const FontImportException('请等待当前操作完成');
    }
    final previous = state;
    final previousDigest = _digest;
    state = AppFontSettings(
      family: previous.family,
      name: previous.name,
      ready: true,
      loading: true,
    );
    String? createdPath;
    try {
      if (!file.name.toLowerCase().endsWith('.ttf')) {
        throw const FontImportException('请选择 .ttf 字体文件');
      }
      final bytes = await _read(File(file.path));
      final digest = sha256.convert(bytes).toString();
      final family = _family(digest);
      await _register(family, bytes);
      final directory = await _directory();
      await directory.create(recursive: true);
      final target = File(_path(directory, digest));
      if (digest != previousDigest || !await target.exists()) {
        createdPath = target.path;
        await target.writeAsBytes(bytes, flush: true);
      }
      final name = file.name.replaceAll(RegExp(r'[\\/\x00-\x1f]'), '_');
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(
        preferenceKey,
        jsonEncode({'name': name, 'digest': digest}),
      )) {
        throw const FontImportException('字体设置保存失败，请重试');
      }
      _digest = digest;
      if (previousDigest != null && previousDigest != digest) {
        await _deleteManaged(directory, previousDigest);
      }
      if (mounted) {
        state = AppFontSettings(family: family, name: name, ready: true);
      }
    } catch (error) {
      if (createdPath != null) {
        try {
          await File(createdPath).delete();
        } catch (_) {}
      }
      if (mounted) {
        state = AppFontSettings(
          family: previous.family,
          name: previous.name,
          ready: true,
          error: previous.error,
        );
      }
      if (error is FontImportException) rethrow;
      throw const FontImportException('字体导入失败，请检查文件后重试');
    }
  }

  Future<void> reset() async {
    if (!state.ready || state.loading) return;
    final previous = state;
    state = AppFontSettings(
      family: previous.family,
      name: previous.name,
      ready: true,
      loading: true,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.remove(preferenceKey)) {
        throw const FontImportException('恢复默认字体失败，请重试');
      }
      final old = _digest;
      _digest = null;
      if (old != null) {
        try {
          await _deleteManaged(await _directory(), old);
        } catch (_) {}
      }
      if (mounted) state = const AppFontSettings(ready: true);
    } catch (_) {
      if (mounted) state = previous;
      throw const FontImportException('恢复默认字体失败，请重试');
    }
  }

  Future<void> _deleteManaged(Directory directory, String digest) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) return;
    try {
      final file = File(_path(directory, digest));
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
