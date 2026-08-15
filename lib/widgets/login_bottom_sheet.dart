import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class LoginBottomSheet extends StatefulWidget {
  const LoginBottomSheet({super.key});

  @override
  State<LoginBottomSheet> createState() => _LoginBottomSheetState();
}

class _LoginBottomSheetState extends State<LoginBottomSheet> with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscureText = true;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnimation = CurvedAnimation(parent: _animationController, curve: Curves.easeOut);
    _animationController.forward();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _performLogin() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入学号和密码')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final auth = AuthService();
      await auth.login(_usernameController.text, _passwordController.text, context);
      final userInfo = await auth.fetchFullUserInfo();
      
      if (mounted) {
        Navigator.pop(context, userInfo); // 登录成功，返回用户信息
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString().contains('LOGIN_ERROR') 
            ? e.toString().split('LOGIN_ERROR:').last.trim() 
            : "网络超时或教务系统不可用";
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(errorMsg),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 获取键盘高度，以便弹起键盘时把底部内容顶起
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final colors = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SafeArea(
        top: false,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            24,
            14,
            24,
            bottomInset > 0 ? bottomInset + 18 : 28,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: colors.outlineVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "欢迎登录",
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "连接农大智慧校园服务",
              style: TextStyle(
                fontSize: 14,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            
            // 学号输入框
            TextField(
              controller: _usernameController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "学号",
                hintText: "请输入您的学号",
                prefixIcon: Icon(Icons.person_outline, color: colors.primary),
              ),
            ),
            const SizedBox(height: 14),
            
            // 密码输入框
            TextField(
              controller: _passwordController,
              obscureText: _obscureText,
              decoration: InputDecoration(
                labelText: "密码",
                hintText: "统一身份认证密码",
                prefixIcon: Icon(Icons.lock_outline, color: colors.primary),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: colors.onSurfaceVariant,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureText = !_obscureText;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 28),
            
            // 登录按钮 (带动画)
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _performLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        "立即登录",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}
