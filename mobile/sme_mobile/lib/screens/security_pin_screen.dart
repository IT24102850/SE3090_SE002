import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../inventory/app_notifications.dart';
import '../services/biometric_auth_service.dart';
import '../services/secure_storage_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ui/ui.dart';

/// Lets a signed-in user create, change, or remove the device's Quick PIN.
class SecurityPinScreen extends StatefulWidget {
  const SecurityPinScreen({super.key});

  @override
  State<SecurityPinScreen> createState() => _SecurityPinScreenState();
}

class _SecurityPinScreenState extends State<SecurityPinScreen> {
  final _oldPin = TextEditingController();
  final _pin = TextEditingController();
  final _confirmation = TextEditingController();
  bool _configured = false;
  bool _loading = true;
  bool _biometricsEnabled = false;
  bool _biometricsAvailable = false;
  bool _updatingBiometrics = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final configured = await SecureStorageService.hasPin();
      var biometricsEnabled = await SecureStorageService.isBiometricsEnabled();
      if (!configured && biometricsEnabled) {
        await SecureStorageService.setBiometricsEnabled(false);
        biometricsEnabled = false;
      }
      final biometricsAvailable =
          await BiometricAuthService.isBiometricsAvailable();
      if (!mounted) return;
      setState(() {
        _configured = configured;
        _biometricsEnabled = biometricsEnabled;
        _biometricsAvailable = biometricsAvailable;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'Could not load security settings. Please reopen this page.';
        _messageIsError = true;
      });
    }
  }

  Future<void> _setBiometricsEnabled(bool enabled) async {
    if (_updatingBiometrics) return;
    if (enabled && !_configured) {
      _showMessage('Set up a Quick PIN before enabling biometric unlock.',
          error: true);
      return;
    }
    if (enabled && !_biometricsAvailable) {
      _showMessage(
          'Enroll a fingerprint or face unlock in your device settings first.',
          error: true);
      return;
    }

    setState(() => _updatingBiometrics = true);
    try {
      if (enabled && !await SecureStorageService.hasPin()) {
        if (!mounted) return;
        setState(() {
          _configured = false;
          _biometricsEnabled = false;
        });
        _showMessage('Set up a Quick PIN before enabling biometric unlock.',
            error: true);
        return;
      }
      await SecureStorageService.setBiometricsEnabled(enabled);
      final saved = await SecureStorageService.isBiometricsEnabled();
      if (saved != enabled) {
        throw StateError('Biometric preference was not saved.');
      }
      if (!mounted) return;
      setState(() => _biometricsEnabled = enabled);
      _showMessage(enabled
          ? 'Biometric unlock enabled. Your Quick PIN remains available.'
          : 'Biometric unlock disabled. You can still use your Quick PIN.');
    } catch (_) {
      if (!mounted) return;
      _showMessage('Could not update biometric settings. Please try again.',
          error: true);
    } finally {
      if (mounted) setState(() => _updatingBiometrics = false);
    }
  }

  Future<void> _savePin() async {
    final isUpdate = _configured;
    if (_configured) {
      final savedPin = await SecureStorageService.getPin();
      if (savedPin == null || _oldPin.text != savedPin) {
        if (!mounted) return;
        _showMessage('Your current PIN is incorrect.', error: true);
        return;
      }
      if (!mounted) return;
    }

    final pin = _pin.text;
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      _showMessage('Enter a 4-digit PIN.', error: true);
      return;
    }
    if (_confirmation.text != pin) {
      _showMessage('The PINs do not match. Please try again.', error: true);
      _confirmation.clear();
      return;
    }

    final confirmed = await showAppConfirmation(
      context: context,
      title: isUpdate ? 'Update your Quick PIN?' : 'Set up Quick PIN?',
      message:
          'Your 4-digit PIN will be saved securely on this device and used to unlock your saved Unify session. Continue?',
      confirmLabel: isUpdate ? 'Update PIN' : 'Save PIN',
      icon: Icons.lock_person_rounded,
      accent: AppColors.cyan,
    );
    if (!confirmed || !mounted) return;

    try {
      await SecureStorageService.savePin(pin);
      final savedPin = await SecureStorageService.getPin();
      if (savedPin == pin) {
        if (!mounted) return;
        _oldPin.clear();
        _pin.clear();
        _confirmation.clear();
        setState(() => _configured = true);
        _showMessage(isUpdate
            ? 'Quick PIN updated successfully. Use it the next time you open Unify.'
            : 'Quick PIN created successfully. Use it the next time you open Unify.');
        return;
      }
      if (!mounted) return;
      _showMessage('Could not save your PIN. Please try again.', error: true);
    } catch (_) {
      if (!mounted) return;
      _showMessage('Could not save your PIN. Please try again.', error: true);
    }
  }

  Future<void> _removePin() async {
    final savedPin = await SecureStorageService.getPin();
    if (savedPin == null || _oldPin.text != savedPin) {
      if (!mounted) return;
      _showMessage('Enter your current PIN to remove it.', error: true);
      return;
    }
    if (!mounted) return;
    final confirmed = await showAppConfirmation(
      context: context,
      title: 'Remove your Quick PIN?',
      message:
          'You will need your work email and password to sign in next time.',
      confirmLabel: 'Remove PIN',
      icon: Icons.delete_outline_rounded,
      accent: AppColors.danger,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await SecureStorageService.setBiometricsEnabled(false);
      if (mounted) {
        setState(() => _biometricsEnabled = false);
      }
      await SecureStorageService.deletePin();
      final stillConfigured = await SecureStorageService.hasPin();
      final biometricsStillEnabled =
          await SecureStorageService.isBiometricsEnabled();
      if (stillConfigured || biometricsStillEnabled) {
        throw StateError('PIN security settings could not be removed.');
      }
      if (!mounted) return;
      _oldPin.clear();
      setState(() {
        _configured = false;
        _biometricsEnabled = false;
      });
      _showMessage(
          'Quick PIN removed. Your next sign-in will use your password.');
    } catch (_) {
      if (!mounted) return;
      _showMessage('Could not remove your PIN. Please try again.', error: true);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    setState(() {
      _message = message;
      _messageIsError = error;
    });
    if (error) {
      AppSnackBar.error(context, message);
    } else {
      AppSnackBar.success(context, message);
    }
  }

  @override
  void dispose() {
    _oldPin.dispose();
    _pin.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppBackgroundScaffold(
      appBar: const GlassAppBar(title: 'Security & PIN'),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24),
                  border:
                      Border.all(color: AppColors.cyan.withValues(alpha: 0.35)),
                ),
                child: const Icon(Icons.lock_person_rounded,
                    color: AppColors.cyan, size: 36),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _configured
                  ? 'Your account is protected'
                  : 'Make sign-in quicker',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _configured
                  ? 'Your 4-digit Quick PIN protects the saved session on this device.'
                  : 'Create a 4-digit Quick PIN to unlock your saved Unify session on this device.',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 24),
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_configured) ...[
                          _PinField(controller: _oldPin, label: 'Current PIN'),
                          const SizedBox(height: 16),
                        ],
                        _PinField(
                            controller: _pin,
                            label: _configured ? 'New PIN' : '4-digit PIN'),
                        const SizedBox(height: 16),
                        _PinField(
                            controller: _confirmation, label: 'Confirm PIN'),
                        const SizedBox(height: 20),
                        NeonButton(
                          label: _configured
                              ? 'Update Quick PIN'
                              : 'Set up Quick PIN',
                          onPressed: _savePin,
                        ),
                        if (_configured) ...[
                          const SizedBox(height: 10),
                          TextButton.icon(
                            onPressed: _removePin,
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('Remove Quick PIN'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.danger,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Container(
                          key: const Key('biometric-unlock-setting'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.glassFill,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: AppColors.cyan.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _biometricsAvailable
                                      ? Icons.fingerprint_rounded
                                      : Icons.phonelink_lock_rounded,
                                  color: AppColors.cyan,
                                  size: 21,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Biometric unlock',
                                      style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      !_configured
                                          ? 'Set up a Quick PIN first.'
                                          : !_biometricsAvailable
                                              ? 'No enrolled face or fingerprint found on this device.'
                                              : _biometricsEnabled
                                                  ? 'Enabled. Your Quick PIN is still available.'
                                                  : 'Use face or fingerprint to unlock this device.',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (_updatingBiometrics)
                                const SizedBox(
                                  key: Key('biometric-setting-progress'),
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else
                                Switch.adaptive(
                                  key: const Key('biometric-unlock-switch'),
                                  value: _biometricsEnabled,
                                  onChanged: _configured &&
                                          (_biometricsAvailable ||
                                              _biometricsEnabled)
                                      ? _setBiometricsEnabled
                                      : null,
                                ),
                            ],
                          ),
                        ),
                        if (_message != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _message!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _messageIsError
                                  ? AppColors.danger
                                  : AppColors.cyan,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your PIN stays on this device in secure storage. If you forget it, sign in with your work email and password.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textMuted, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinField extends StatelessWidget {
  const _PinField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        obscureText: true,
        obscuringCharacter: '●',
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4)
        ],
        style: const TextStyle(color: AppColors.textPrimary, letterSpacing: 10),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          hintText: '••••',
          hintStyle:
              const TextStyle(color: AppColors.textMuted, letterSpacing: 8),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.cyan),
          ),
        ),
      );
}
