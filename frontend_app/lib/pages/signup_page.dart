import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/auth/auth_services.dart';
import '../widgets/policy_dialog.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  static final RegExp _emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
  static const int _sendCodeCooldownSeconds = 60;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _verificationCodeController =
      TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isLoading = false;
  bool _isSendingVerificationCode = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  int _remainingSendCodeSeconds = 0;
  Timer? _sendCodeTimer;

  InputDecoration _inputDecoration({
    required String label,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(prefixIcon),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ── 品牌区域 ──
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        Icons.person_add_outlined,
                        size: 36,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '创建账户',
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '请填写以下信息完成注册',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── 表单字段 ──
                    TextFormField(
                      controller: _usernameController,
                      decoration: _inputDecoration(
                        label: '用户名',
                        prefixIcon: Icons.person_outline,
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '用户名不能为空';
                        }
                        if (value.trim().length < 5) {
                          return '用户名至少需要5个字符';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      decoration: _inputDecoration(
                        label: '邮箱',
                        prefixIcon: Icons.email_outlined,
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '邮箱不能为空';
                        }
                        final emailRegex = RegExp(
                          r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                        );
                        if (!emailRegex.hasMatch(value.trim())) {
                          return '请输入有效的邮箱地址';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _verificationCodeController,
                      decoration: _inputDecoration(
                        label: '验证码',
                        prefixIcon: Icons.security_outlined,
                        suffixIcon: Padding(
                          padding: const EdgeInsets.only(right: 4.0),
                          child: TextButton(
                            onPressed:
                                _isLoading ||
                                    _isSendingVerificationCode ||
                                    _remainingSendCodeSeconds > 0
                                ? null
                                : _handleSendVerificationCode,
                            child: Text(
                              _isSendingVerificationCode
                                  ? '...'
                                  : _remainingSendCodeSeconds > 0
                                  ? '${_remainingSendCodeSeconds}s'
                                  : '发送',
                            ),
                          ),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '验证码不能为空';
                        }
                        if (value.trim().length != 6) {
                          return '请输入6位数字验证码';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      decoration: _inputDecoration(
                        label: '密码',
                        prefixIcon: Icons.lock_outline,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.isEmpty) return '密码不能为空';
                        if (value.length < 8) return '密码至少需要8个字符';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmPasswordController,
                      decoration: _inputDecoration(
                        label: '确认密码',
                        prefixIcon: Icons.check_outlined,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () => setState(
                            () => _obscureConfirmPassword =
                                !_obscureConfirmPassword,
                          ),
                        ),
                      ),
                      obscureText: _obscureConfirmPassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _handleRegister(),
                      validator: (value) {
                        if (value == null || value.isEmpty) return '请确认密码';
                        if (value != _passwordController.text) {
                          return '两次输入的密码不一致';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 28),

                    // ── 注册按钮 ──
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isLoading ? null : _handleRegister,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.onPrimary,
                                ),
                              )
                            : const Text(
                                '注册',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '已有账户？',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('立即登录'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '注册即表示同意',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () {
                            showPolicyDialog(
                              context,
                              title: '用户协议',
                              content: userAgreementContent,
                            );
                          },
                          child: Text(
                            '用户协议',
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '与',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () {
                            showPolicyDialog(
                              context,
                              title: '隐私政策',
                              content: privacyPolicyContent,
                            );
                          },
                          child: Text(
                            '隐私政策',
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleRegister() async {
    setState(() {
      _isLoading = true;
    });

    final authServices = context.read<AuthServices>();
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final verificationCode = _verificationCodeController.text.trim();
    final password = _passwordController.text;

    try {
      if (!_formKey.currentState!.validate()) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      await authServices.register(username, email, password, verificationCode);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('注册成功，请登录')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('注册失败: $message')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleSendVerificationCode() async {
    final email = _emailController.text.trim();
    if (!_emailRegex.hasMatch(email)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效的邮箱地址')));
      return;
    }

    setState(() {
      _isSendingVerificationCode = true;
    });

    try {
      await context.read<AuthServices>().sendVerificationCode(email: email);
      if (!mounted) return;
      _startSendCodeCooldown(_sendCodeCooldownSeconds);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('验证码已发送，请查收邮箱')));
    } catch (e) {
      if (!mounted) return;

      if (e is AuthActionException && e.retryAfterSeconds != null) {
        _startSendCodeCooldown(e.retryAfterSeconds!);
      }

      final message = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          _isSendingVerificationCode = false;
        });
      }
    }
  }

  void _startSendCodeCooldown(int seconds) {
    _sendCodeTimer?.cancel();
    setState(() {
      _remainingSendCodeSeconds = seconds;
    });

    _sendCodeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _remainingSendCodeSeconds <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _remainingSendCodeSeconds = 0;
          });
        }
        return;
      }

      setState(() {
        _remainingSendCodeSeconds -= 1;
      });
    });
  }

  @override
  void dispose() {
    _sendCodeTimer?.cancel();
    _usernameController.dispose();
    _emailController.dispose();
    _verificationCodeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
