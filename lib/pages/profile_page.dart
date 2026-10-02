import 'dart:io';

import 'package:flutter/material.dart';

import '../services/app_cookie_manager.dart';
import '../services/agent_settings_store.dart';
import '../services/electricity_service.dart';
import '../services/secure_storage_helper.dart';
import 'about_page.dart';
import 'help_feedback_page.dart';
import 'settings_page.dart';

class ProfilePage extends StatelessWidget {
  final String? realName;
  final String? avatarUrl;
  final String? studentId;
  final VoidCallback onLogout;
  final bool isLoggedIn;
  final VoidCallback? onLogin;

  const ProfilePage({
    super.key,
    this.realName,
    this.avatarUrl,
    this.studentId,
    required this.onLogout,
    this.isLoggedIn = true,
    this.onLogin,
  });

  Future<void> _handleLogout(BuildContext context) async {
    try {
      await AgentSettingsStore.instance.clear();
    } catch (_) {
      // 内存中已关闭 Agent；后续 clearAll 再清理设备凭据。
    }
    final storage = SecureStorageHelper();
    await storage.clearAll();
    await ElectricityService.instance.clearSavedRoom();
    try {
      await AppCookieManager().clearAllCookies();
    } catch (_) {}
    onLogout();
    if (context.mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasAvatar = avatarUrl != null && avatarUrl!.isNotEmpty;
    final displayName = !isLoggedIn
        ? '未登录'
        : realName?.trim().isNotEmpty == true
        ? realName!
        : '校园用户';
    final displayStudentId = studentId?.trim().isNotEmpty == true
        ? studentId!
        : '暂未获取';

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(title: const Text('个人中心'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: colors.primaryContainer,
                  backgroundImage: hasAvatar
                      ? FileImage(File(avatarUrl!))
                      : null,
                  child: hasAvatar
                      ? null
                      : Icon(
                          Icons.person_outline_rounded,
                          size: 30,
                          color: colors.onPrimaryContainer,
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        isLoggedIn
                            ? '学号 $displayStudentId'
                            : '登录后使用校园服务，设置无需登录',
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            '账户与服务',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
              children: [
                _ProfileMenuItem(
                  icon: Icons.settings_outlined,
                  title: '设置',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SettingsPage(),
                      ),
                    );
                  },
                ),
                Divider(height: 1, indent: 60, color: colors.outlineVariant),
                _ProfileMenuItem(
                  icon: Icons.info_outline_rounded,
                  title: '关于应用',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AboutPage()),
                    );
                  },
                ),
                Divider(height: 1, indent: 60, color: colors.outlineVariant),
                _ProfileMenuItem(
                  icon: Icons.help_outline_rounded,
                  title: '帮助与反馈',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HelpFeedbackPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
          OutlinedButton.icon(
            onPressed: isLoggedIn ? () => _handleLogout(context) : onLogin,
            icon: Icon(
              isLoggedIn ? Icons.logout_rounded : Icons.login_rounded,
              size: 19,
            ),
            label: Text(isLoggedIn ? '退出登录' : '登录校园账号'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.error,
              side: BorderSide(color: colors.error.withValues(alpha: 0.45)),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _ProfileMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _ProfileMenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(icon, color: colors.onSurfaceVariant, size: 22),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: colors.onSurface,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: colors.onSurfaceVariant,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: onTap,
    );
  }
}
