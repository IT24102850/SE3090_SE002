import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/ui/ui.dart';

/// Email-code password recovery, matching the web flow:
/// request code -> verify code -> choose a new password.
class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  int _step = 0;
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _emailError(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your account email';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String _apiError(Object error, String fallback) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return 'The server took too long to respond. Please try again.';
      }
    }
    return fallback;
  }

  void _setMessage(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = error;
    });
  }

  Future<void> _requestCode() async {
    final email = _emailController.text.trim();
    final validation = _emailError(email);
    if (validation != null) {
      _setMessage(validation, error: true);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final response = await ApiService.dio
          .post('/auth/forgot-password', data: {'email': email});
      if (!mounted) return;
      _codeController.clear();
      setState(() {
        _step = 1;
        _busy = false;
        _message = response.data is Map<String, dynamic>
            ? response.data['message'] as String? ??
                'If the account exists, a recovery code will arrive shortly.'
            : 'If the account exists, a recovery code will arrive shortly.';
        _messageIsError = false;
      });
    } catch (error) {
      _setMessage(
          _apiError(
              error, 'Could not request a recovery code. Please try again.'),
          error: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _setMessage('Enter all 6 digits from the email.', error: true);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final response =
          await ApiService.dio.post('/auth/verify-reset-code', data: {
        'email': _emailController.text.trim(),
        'code': code,
      });
      if (!mounted) return;
      setState(() {
        _step = 2;
        _busy = false;
        _message = response.data is Map<String, dynamic>
            ? response.data['message'] as String? ??
                'Code verified. Choose a new password.'
            : 'Code verified. Choose a new password.';
        _messageIsError = false;
      });
    } catch (error) {
      _setMessage(
          _apiError(error,
              'That code could not be verified. Check it and try again.'),
          error: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final password = _passwordController.text;
    if (password.length < 6) {
      _setMessage('Password must be at least 6 characters long.', error: true);
      return;
    }
    if (password != _confirmController.text) {
      _setMessage('The passwords do not match. Please check both fields.',
          error: true);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final response = await ApiService.dio.post('/auth/reset-password', data: {
        'email': _emailController.text.trim(),
        'code': _codeController.text.trim(),
        'newPassword': password,
      });
      if (!mounted) return;
      setState(() {
        _step = 3;
        _busy = false;
        _message = response.data is Map<String, dynamic>
            ? response.data['message'] as String? ??
                'Your password has been reset.'
            : 'Your password has been reset.';
        _messageIsError = false;
      });
    } catch (error) {
      _setMessage(
          _apiError(error,
              'Password reset failed. Verify the code is still valid and try again.'),
          error: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_step) {
      0 => 'Recover your account',
      1 => 'Verify your email',
      2 => 'Choose a new password',
      _ => 'Password updated',
    };

    return AppBackgroundScaffold(
      showParticles: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to sign in',
        ),
        title: Text('Account recovery', style: AppTextStyles.title),
        centerTitle: true,
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: GlassCard(
                padding: const EdgeInsets.all(24),
                child: _step == 3
                    ? _buildSuccess()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(
                            _step == 0
                                ? Icons.mark_email_read_outlined
                                : _step == 1
                                    ? Icons.verified_user_outlined
                                    : Icons.lock_reset_rounded,
                            color: AppColors.cyan,
                            size: 38,
                          ),
                          const SizedBox(height: 16),
                          Text(title,
                              style: AppTextStyles.headlineSmall,
                              textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          Text(
                            _step == 0
                                ? 'We’ll email you a secure, one-time code to confirm it’s your account.'
                                : _step == 1
                                    ? 'Enter the 6-digit code sent to ${_emailController.text.trim()}. Your new-password fields unlock after verification.'
                                    : 'Your email is verified. Create a new password for your account.',
                            style: AppTextStyles.bodyMuted,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          if (_step == 0) ...[
                            NeonInputField(
                              label: 'Account email',
                              hintText: 'name@example.com',
                              icon: Icons.mail_outline,
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.email],
                              validator: _emailError,
                            ),
                            const SizedBox(height: 18),
                            NeonButton(
                                label: 'Send recovery code',
                                icon: Icons.arrow_forward_rounded,
                                isLoading: _busy,
                                onPressed: _busy ? null : _requestCode),
                          ],
                          if (_step == 1) ...[
                            NeonInputField(
                              label: '6-digit verification code',
                              hintText: '123456',
                              icon: Icons.pin_outlined,
                              controller: _codeController,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              maxLines: 1,
                              autofillHints: const [AutofillHints.oneTimeCode],
                              onChanged: (_) {
                                if (_messageIsError) {
                                  setState(() => _message = null);
                                }
                              },
                            ),
                            const SizedBox(height: 18),
                            NeonButton(
                                label: 'Verify code',
                                icon: Icons.verified_rounded,
                                isLoading: _busy,
                                onPressed: _busy ? null : _verifyCode),
                            const SizedBox(height: 10),
                            TextButton(
                                onPressed: _busy ? null : _requestCode,
                                child: const Text('Resend code')),
                            TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                          _step = 0;
                                          _message = null;
                                        }),
                                child: const Text('Change email address')),
                          ],
                          if (_step == 2) ...[
                            NeonInputField(
                              label: 'New password',
                              hintText: 'At least 6 characters',
                              icon: Icons.lock_outline,
                              controller: _passwordController,
                              obscurable: true,
                              autofillHints: const [AutofillHints.newPassword],
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 16),
                            NeonInputField(
                              label: 'Confirm new password',
                              hintText: 'Enter it again',
                              icon: Icons.lock_outline,
                              controller: _confirmController,
                              obscurable: true,
                              autofillHints: const [AutofillHints.newPassword],
                              textInputAction: TextInputAction.done,
                            ),
                            const SizedBox(height: 18),
                            NeonButton(
                                label: 'Save new password',
                                icon: Icons.check_rounded,
                                isLoading: _busy,
                                onPressed: _busy ? null : _resetPassword),
                            TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                          _step = 1;
                                          _message = null;
                                        }),
                                child: const Text('Back to verification code')),
                          ],
                          if (_message != null) ...[
                            const SizedBox(height: 14),
                            _StatusMessage(
                                message: _message!, isError: _messageIsError),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle_rounded,
              color: Color(0xFF34D399), size: 52),
          const SizedBox(height: 16),
          Text('You’re all set',
              style: AppTextStyles.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
              _message ??
                  'Your password has been reset. You can sign in with your new password.',
              style: AppTextStyles.bodyMuted,
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          NeonButton(
              label: 'Return to sign in',
              icon: Icons.login_rounded,
              onPressed: () => Navigator.of(context).pop()),
        ],
      );
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppColors.danger : const Color(0xFF34D399);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: color,
              size: 19),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: AppTextStyles.bodyMuted
                      .copyWith(color: AppColors.textPrimary))),
        ],
      ),
    );
  }
}
