import 'dart:io';
import 'package:flutter/material.dart';
import '../services/secure_storage_helper.dart';
import '../services/app_cookie_manager.dart';
import 'settings_page.dart';
import 'help_feedback_page.dart';

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
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('个人中心'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // 顶部用户信息卡片
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary.withOpacity(0.8),
                  Theme.of(context).colorScheme.primary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    backgroundImage: avatarUrl != null
                        ? FileImage(File(avatarUrl!)) as ImageProvider
                        : null,
                    child: avatarUrl == null
                        ? const Icon(Icons.person, size: 40, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        realName ?? '未命名用户',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '学号: ${studentId ?? "未知"}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // 功能操作组
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 12),
            child: Text(
              '服务与设置',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildItem(
                  context,
                  icon: Icons.settings_rounded,
                  iconColor: Colors.blueAccent,
                  title: '设置',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SettingsPage()),
                    );
                  },
                ),
                const Divider(height: 1, indent: 56, endIndent: 24, color: Color(0xFFEEEEEE)),
                _buildItem(
                  context,
                  icon: Icons.info_rounded,
                  iconColor: Colors.orangeAccent,
                  title: '关于',
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: 'Life@HUNAU',
                      applicationVersion: '1.0.0',
                      applicationIcon: Icon(Icons.school, size: 64, color: Theme.of(context).colorScheme.primary),
                      children: const [
                        Text('智慧农大提供校园生活一站式服务。'),
                      ],
                    );
                  },
                ),
                const Divider(height: 1, indent: 56, endIndent: 24, color: Color(0xFFEEEEEE)),
                _buildItem(
                  context,
                  icon: Icons.help_rounded,
                  iconColor: Colors.green,
                  title: '帮助与反馈',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const HelpFeedbackPage()),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),

          // 退出登录按钮
          ElevatedButton(
            onPressed: () => _handleLogout(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              '退出登录',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, {required IconData icon, required Color iconColor, required String title, required VoidCallback onTap}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(
        title, 
        style: const TextStyle(
          fontSize: 16, 
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onTap: onTap,
    );
  }
}
