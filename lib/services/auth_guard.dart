import 'package:flutter/material.dart';

import '../widgets/login_bottom_sheet.dart';
import 'secure_storage_helper.dart';

class AuthGuardResult {
  final bool allowed;
  final Map<String, String?>? userInfo;

  const AuthGuardResult._({required this.allowed, this.userInfo});

  const AuthGuardResult.allowed({Map<String, String?>? userInfo})
    : this._(allowed: true, userInfo: userInfo);

  const AuthGuardResult.denied() : this._(allowed: false);
}

class AuthGuard {
  const AuthGuard._();

  static Future<bool> hasSavedCredentials() async {
    final storage = SecureStorageHelper();
    final username = await storage.getUsername();
    final password = await storage.getPassword();
    return username?.trim().isNotEmpty == true &&
        password?.trim().isNotEmpty == true;
  }

  static Future<AuthGuardResult> ensureLoggedIn(
    BuildContext context, {
    String message = '请先登录后再使用该功能',
  }) async {
    if (await hasSavedCredentials()) {
      return const AuthGuardResult.allowed();
    }

    if (!context.mounted) return const AuthGuardResult.denied();

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1500),
      ),
    );

    final userInfo = await showModalBottomSheet<Map<String, String?>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (context) => const LoginBottomSheet(),
    );

    if (userInfo == null) {
      return const AuthGuardResult.denied();
    }

    return AuthGuardResult.allowed(userInfo: userInfo);
  }
}
