import 'dart:io';

import 'package:flutter/material.dart';

import '../services/app_cookie_manager.dart';
import '../services/secure_storage_helper.dart';
import 'about_page.dart';
import 'help_feedback_page.dart';
import 'settings_page.dart';

class ProfilePage extends StatelessWidget {
  final String? realName;
  final String? avatarUrl;
  final String? studentId;
  final VoidCallback onLogout;

  const ProfilePage({
    super.key,
    this.realName,
    this.avatarUrl,
    this.studentId,
    required this.onLogout,
  });

  Future<void> _handleLogout(BuildContext context) async {
    final storage = SecureStorageHelper();
    await storage.clearAll();
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
    final displayName = realName?.trim().isNotEmpty == true ? realName! : '校园用户';
    final displayStudentId = studentId?.trim().isNotEmpty == true
        ? studentId!
        : '暂未获取';

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('个人中心'),
        centerTitle: false,
      ),
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
                  backgroundImage:
                      hasAvatar ? FileImage(File(avatarUrl!)) : null,
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
                        '学号 $displayStudentId',
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
            onPressed: () => _handleLogout(context),
            icon: const Icon(Icons.logout_rounded, size: 19),
            label: const Text('退出登录'),
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
