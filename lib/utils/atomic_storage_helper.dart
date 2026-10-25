import 'dart:convert';
import 'dart:io';

import '../services/app_logger.dart';

/// 本地原子写盘与损坏隔离工具
///
/// 1. 原子写盘：先写入临时文件 `${file.path}.tmp`（带 `flush: true`），
///    再通过 `tmpFile.rename(file.path)` 原子替换，防止写入中途断电/崩溃导致 0 字节损坏。
///    在写入前如果原文件存在且有效，自动保留/更新 `${file.path}.bak` 备份文件。
///
/// 2. 损坏隔离与容灾恢复：读取 JSON 遇到 `FormatException` 或损坏时，
///    将损坏文件重命名为 `${file.path}.corrupted.${DateTime.now().millisecondsSinceEpoch}` 隔离保存，
///    若存在 `.bak` 文件则尝试从备份恢复并回写，绝不静默吞掉空列表导致后续写盘覆盖云端。
class AtomicStorageHelper {
  static final _logger = AppLogger.instance;

  /// 原子写入字符串到文件。
  static Future<void> atomicWriteString(File file, String content) async {
    final parentDir = file.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    final tmpFile = File('${file.path}.tmp');
    try {
      await tmpFile.writeAsString(content, flush: true);

      // 在替换前，如果原文件存在且非空，先备份至 .bak
      if (await file.exists()) {
        try {
          final length = await file.length();
          if (length > 0) {
            final bakFile = File('${file.path}.bak');
            await file.copy(bakFile.path);
          }
        } catch (e) {
          _logger.w('Failed to create backup (.bak) for ${file.path}: $e');
        }
      }

      // 原子重命名替换
      try {
        await tmpFile.rename(file.path);
      } on FileSystemException {
        // Windows 等平台上若目标文件已存在可能报错，退化为删除后重命名
        if (await file.exists()) {
          await file.delete();
        }
        await tmpFile.rename(file.path);
      }
    } catch (e) {
      if (await tmpFile.exists()) {
        try {
          await tmpFile.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// 安全读取 JSON 文件。
  /// 若发生 FormatException 或损坏：
  /// 1. 将损坏文件隔离重命名为 `${file.path}.corrupted.${stamp}`；
  /// 2. 若存在 `.bak` 文件尝试从中恢复；
  /// 3. 若均无法恢复则返回 null 并记录警告日志。
  static Future<dynamic> readJsonWithRecovery(
    File file, {
    String logTag = 'Storage',
  }) async {
    if (!await file.exists()) {
      return null;
    }

    String content;
    try {
      content = await file.readAsString();
    } catch (e) {
      _logger.w('[$logTag] Error reading file ${file.path}: $e');
      return null;
    }

    // 0 字节文件被视为写入中断残留损坏
    if (content.trim().isEmpty) {
      return await _isolateAndRecover(
        file,
        logTag,
        'File is empty (0 bytes)',
      );
    }

    try {
      return jsonDecode(content);
    } on FormatException catch (e) {
      return await _isolateAndRecover(
        file,
        logTag,
        'FormatException: ${e.message}',
      );
    } catch (e) {
      return await _isolateAndRecover(
        file,
        logTag,
        'Unexpected decode error: $e',
      );
    }
  }

  /// 隔离损坏文件并尝试从 .bak 恢复
  static Future<dynamic> _isolateAndRecover(
    File file,
    String logTag,
    String reason,
  ) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final corruptedFile = File('${file.path}.corrupted.$stamp');
    try {
      await file.rename(corruptedFile.path);
      _logger.w(
        '[$logTag] Corrupted file ${file.path} ($reason) quarantined to ${corruptedFile.path}',
      );
    } catch (e) {
      _logger.e('[$logTag] Failed to quarantine corrupted file ${file.path}: $e');
    }

    // 检查并尝试从 .bak 恢复
    final bakFile = File('${file.path}.bak');
    if (await bakFile.exists()) {
      try {
        final bakContent = await bakFile.readAsString();
        if (bakContent.trim().isNotEmpty) {
          final decoded = jsonDecode(bakContent);
          try {
            await bakFile.copy(file.path);
          } catch (_) {}
          _logger.i('[$logTag] Successfully recovered ${file.path} from .bak');
          return decoded;
        }
      } catch (e) {
        _logger.w('[$logTag] Backup file ${bakFile.path} is also invalid: $e');
      }
    }

    _logger.w(
      '[$logTag] No valid backup (.bak) found for ${file.path}. Isolation complete without recovery.',
    );
    return null;
  }

  /// 删除文件以及相关的 .tmp 和 .bak 备份
  static Future<void> deleteWithBackups(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
    try {
      final tmp = File('${file.path}.tmp');
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
    try {
      final bak = File('${file.path}.bak');
      if (await bak.exists()) await bak.delete();
    } catch (_) {}
  }
}
