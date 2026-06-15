import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/biometric_service.dart';

enum ChangePasswordStep {
  auth,
  newPassword,
  selectOtp,
  verifyOtp,
  success,
}

class ChangePasswordFlowPage extends StatefulWidget {
  final String email;

  const ChangePasswordFlowPage({super.key, required this.email});

  @override
  State<ChangePasswordFlowPage> createState() => _ChangePasswordFlowPageState();
}

class _ChangePasswordFlowPageState extends State<ChangePasswordFlowPage> {
  static const _accent = Color.fromARGB(255, 55, 194, 21);
  static const _boxCount = 6;

  ChangePasswordStep _currentStep = ChangePasswordStep.auth;

  // Step 1: Auth fields
  final _currentPasswordController = TextEditingController();
  bool _obscureCurrentPassword = true;
  bool _isVerifyingCurrent = false;
  bool _biometricAvailable = false;

  // Step 2: New Password fields
  final _newPasswordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscureNewPassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  // Step 3: Select OTP fields
  List<Map<String, dynamic>> _destinations = [];
  bool _loadingDestinations = true;
  Map<String, dynamic>? _selectedDestination;
  bool _isSendingOtp = false;

  // Step 4: Verify OTP fields
  late final List<TextEditingController> _otpControllers;
  late final List<FocusNode> _otpFocusNodes;
  bool _isVerifyingOtp = false;
  String _otpError = '';
  int _resendSeconds = 60;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _currentPasswordController.addListener(_rebuild);
    _newPasswordController.addListener(_rebuild);
    _confirmController.addListener(_rebuild);

    // Initialize OTP controllers & focus nodes
    _otpControllers = List.generate(_boxCount, (_) => TextEditingController());
    _otpFocusNodes = List.generate(_boxCount, (i) {
      final node = FocusNode();
      node.onKeyEvent = (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace &&
            _otpControllers[i].text.isEmpty &&
            i > 0) {
          _otpControllers[i - 1].clear();
          _otpFocusNodes[i - 1].requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      };
      return node;
    });

    _checkBiometric();
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _resendTimer?.cancel();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _checkBiometric() async {
    final available = await BiometricService.isBiometricAvailable();
    final enrolledEmail = await BiometricService.getBiometricEmail();
    setState(() {
      _biometricAvailable = available && enrolledEmail == widget.email;
    });
  }

  // ── Password strength helpers ──────────────────────────────────────────────
  String get _newPassword => _newPasswordController.text;

  bool get _hasLength => _newPassword.length >= 8;
  bool get _hasUpper => _newPassword.contains(RegExp(r'[A-Z]'));
  bool get _hasLower => _newPassword.contains(RegExp(r'[a-z]'));
  bool get _hasDigit => _newPassword.contains(RegExp(r'[0-9]'));
  bool get _hasSpecial => _newPassword.contains(
        RegExp(
          r'[!@#$%^&*(),.?":{}|<>\-_=+\[\]\\;'
          r"'/`~]",
        ),
      );

  int get _strength {
    int s = 0;
    if (_hasLength) s++;
    if (_hasUpper) s++;
    if (_hasLower) s++;
    if (_hasDigit) s++;
    if (_hasSpecial) s++;
    return s;
  }

  Color _strengthColor(int level) {
    switch (level) {
      case 1:
        return Colors.red;
      case 2:
        return Colors.orange;
      case 3:
        return const Color(0xFFCDDC39);
      case 4:
        return const Color(0xFF8BC34A);
      case 5:
        return _accent;
      default:
        return Colors.grey.withValues(alpha: 0.3);
    }
  }

  String _strengthLabel() {
    switch (_strength) {
      case 1:
        return 'Weak';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Strong';
      case 5:
        return 'Very Strong';
      default:
        return '';
    }
  }

  bool get _passwordsMatch => _newPassword == _confirmController.text;

  bool get _canSubmitNewPassword =>
      _strength >= 3 && _passwordsMatch && _confirmController.text.isNotEmpty;

  // ── Step 1: Authentication Logic ───────────────────────────────────────────
  Future<void> _verifyPasswordAuth() async {
    final password = _currentPasswordController.text;
    if (password.isEmpty) return;

    setState(() => _isVerifyingCurrent = true);
    final error = await ApiService.verifyCurrentPassword(password);
    if (!mounted) return;
    setState(() => _isVerifyingCurrent = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
    } else {
      setState(() {
        _currentStep = ChangePasswordStep.newPassword;
      });
    }
  }

  Future<void> _startBiometricAuth() async {
    final authenticated = await BiometricService.authenticate();
    if (!mounted) return;

    if (authenticated) {
      setState(() {
        _currentStep = ChangePasswordStep.newPassword;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Biometric authentication failed or cancelled.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ── Step 2 & 3: Destinations Loading & OTP Dispatch ───────────────────────
  Future<void> _handleNewPasswordSubmit() async {
    if (!_canSubmitNewPassword) return;

    setState(() => _isLoading = true);
    await _fetchDestinations();
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (_destinations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No registered email or phone numbers found.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_destinations.length > 1) {
      setState(() {
        _currentStep = ChangePasswordStep.selectOtp;
      });
    } else {
      // Only 1 destination exists (usually email) - auto-send OTP and go to verify step
      _selectedDestination = _destinations.first;
      final sent = await _sendOtpToDestination(_selectedDestination!);
      if (!mounted) return;
      if (sent) {
        setState(() {
          _currentStep = ChangePasswordStep.verifyOtp;
        });
        _startResendTimer();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _otpFocusNodes[0].requestFocus();
        });
      }
    }
  }

  Future<void> _fetchDestinations() async {
    try {
      final Set<String> uniquePhones = {};
      final methods = await ApiService.getPaymentMethods();

      for (final m in methods) {
        final type = m['type'] as String?;
        if (type == 'mpesa' || type == 'airtel') {
          final phone = m['phone_number'] as String?;
          if (phone != null && phone.trim().isNotEmpty) {
            uniquePhones.add(phone.trim());
          }
        }
      }

      _destinations = [];
      if (widget.email.isNotEmpty) {
        _destinations.add({
          'destination': widget.email,
          'type': 'email',
          'label': 'Email Address',
          'display': _maskEmail(widget.email),
        });
      }
      for (final p in uniquePhones) {
        _destinations.add({
          'destination': p,
          'type': 'sms',
          'label': p.startsWith('+2541') || p.startsWith('01') ? 'Airtel Number' : 'M-Pesa Number',
          'display': _maskPhone(p),
        });
      }

      if (_destinations.isNotEmpty) {
        _selectedDestination = _destinations.first;
      }
      _loadingDestinations = false;
    } catch (_) {
      _loadingDestinations = false;
    }
  }

  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final name = parts[0];
    final domain = parts[1];
    if (name.length <= 2) return '${name[0]}*@$domain';
    return '${name.substring(0, 2)}***${name.substring(name.length - 1)}@$domain';
  }

  String _maskPhone(String phone) {
    if (phone.length < 5) return phone;
    return '${phone.substring(0, 4)}***${phone.substring(phone.length - 3)}';
  }

  Future<bool> _sendOtpToDestination(Map<String, dynamic> dest) async {
    setState(() => _isSendingOtp = true);
    final sent = await ApiService.sendOtp(
      destination: dest['destination']!,
      type: dest['type']!,
      purpose: 'password_reset',
    );
    if (!mounted) return false;
    setState(() => _isSendingOtp = false);
    return sent;
  }

  // ── Step 4: OTP Verification & Password Save ──────────────────────────────
  String get _enteredOtp => _otpControllers.map((c) => c.text).join();

  void _onOtpBoxChanged(int index, String value) {
    if (value.isEmpty) return;
    setState(() => _otpError = '');
    if (index < _boxCount - 1) {
      _otpFocusNodes[index + 1].requestFocus();
    } else {
      _otpFocusNodes[index].unfocus();
    }
    if (_enteredOtp.length == _boxCount) _verifyOtpAndSavePassword();
  }

  void _startResendTimer() {
    _resendSeconds = 60;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_resendSeconds > 0) {
          _resendSeconds--;
        } else {
          t.cancel();
        }
      });
    });
  }

  Future<void> _resendOtp() async {
    if (_resendSeconds > 0 || _isSendingOtp) return;
    final sent = await _sendOtpToDestination(_selectedDestination!);
    if (!mounted) return;
    if (sent) {
      _startResendTimer();
      for (final c in _otpControllers) {
        c.clear();
      }
      _otpFocusNodes[0].requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Code resent to ${_selectedDestination!['display']}'),
          backgroundColor: _accent,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to resend code. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _verifyOtpAndSavePassword() async {
    if (_isVerifyingOtp) return;
    setState(() {
      _isVerifyingOtp = true;
      _otpError = '';
    });

    final verifyResult = await ApiService.verifyOtp(
      destination: _selectedDestination!['destination']!,
      otp: _enteredOtp,
      purpose: 'password_reset',
    );

    if (!mounted) return;

    if (verifyResult.token != null) {
      final changeError = await ApiService.changePasswordConfirm(
        verificationToken: verifyResult.token!,
        newPassword: _newPasswordController.text,
      );

      if (!mounted) return;

      if (changeError == null) {
        setState(() {
          _isVerifyingOtp = false;
          _currentStep = ChangePasswordStep.success;
        });
      } else {
        setState(() {
          _isVerifyingOtp = false;
          _otpError = changeError;
          for (final c in _otpControllers) {
            c.clear();
          }
        });
        _otpFocusNodes[0].requestFocus();
      }
    } else {
      setState(() {
        _isVerifyingOtp = false;
        _otpError = verifyResult.errorMsg ?? 'Incorrect code. Please try again.';
        for (final c in _otpControllers) {
          c.clear();
        }
      });
      _otpFocusNodes[0].requestFocus();
    }
  }

  // ── Render Helpers ─────────────────────────────────────────────────────────
  Widget _label(String text, Color color) => Text(
        text,
        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500),
      );

  Widget _inputContainer({
    required Widget child,
    required Color surfaceColor,
    Color? borderColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor ?? Colors.grey.withValues(alpha: 0.3),
        ),
      ),
      child: child,
    );
  }

  Widget _requirement(String label, bool met, Color subtleColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 16,
            color: met ? _accent : subtleColor.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: met ? _accent : subtleColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build Steps ────────────────────────────────────────────────────────────

  Widget _buildAuthStep(Color textColor, Color subtleColor, Color surfaceColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          'Verify your identity',
          style: TextStyle(color: textColor, fontSize: 26, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Please enter your current password or use biometric authentication to verify it\'s you.',
          style: TextStyle(color: subtleColor, fontSize: 14, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        _label('Current Password', subtleColor),
        const SizedBox(height: 6),
        _inputContainer(
          surfaceColor: surfaceColor,
          child: TextField(
            controller: _currentPasswordController,
            obscureText: _obscureCurrentPassword,
            style: TextStyle(color: textColor, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Enter your password',
              hintStyle: TextStyle(color: subtleColor.withValues(alpha: 0.6)),
              prefixIcon: const Icon(Icons.lock_rounded, color: _accent, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureCurrentPassword ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  color: subtleColor,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureCurrentPassword = !_obscureCurrentPassword),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          onPressed: (_isVerifyingCurrent || _currentPasswordController.text.isEmpty)
              ? null
              : _verifyPasswordAuth,
          child: _isVerifyingCurrent
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : const Text('Verify Password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        if (_biometricAvailable) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: Divider(color: subtleColor.withValues(alpha: 0.3))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('OR', style: TextStyle(color: subtleColor, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Expanded(child: Divider(color: subtleColor.withValues(alpha: 0.3))),
            ],
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _accent),
              padding: const EdgeInsets.symmetric(vertical: 14.0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            onPressed: _startBiometricAuth,
            icon: const Icon(Icons.fingerprint_rounded, color: _accent, size: 28),
            label: const Text(
              'Verify with Biometrics',
              style: TextStyle(fontSize: 16, color: _accent, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNewPasswordStep(Color textColor, Color subtleColor, Color surfaceColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          'Create new password',
          style: TextStyle(color: textColor, fontSize: 26, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Please choose a strong password to secure your K-PESA account.',
          style: TextStyle(color: subtleColor, fontSize: 14, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        _label('New Password', subtleColor),
        const SizedBox(height: 6),
        _inputContainer(
          surfaceColor: surfaceColor,
          child: TextField(
            controller: _newPasswordController,
            obscureText: _obscureNewPassword,
            style: TextStyle(color: textColor, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Min. 8 characters',
              hintStyle: TextStyle(color: subtleColor.withValues(alpha: 0.6)),
              prefixIcon: const Icon(Icons.lock_rounded, color: _accent, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureNewPassword ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  color: subtleColor,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (_newPassword.isNotEmpty) ...[
          Row(
            children: [
              ...List.generate(5, (i) {
                final filled = i < _strength;
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: i < 4 ? 4 : 0),
                    height: 4,
                    decoration: BoxDecoration(
                      color: filled ? _strengthColor(_strength) : Colors.grey.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
              const SizedBox(width: 10),
              Text(
                _strengthLabel(),
                style: TextStyle(
                  color: _strengthColor(_strength),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _requirement('At least 8 characters', _hasLength, subtleColor),
          _requirement('One uppercase letter (A–Z)', _hasUpper, subtleColor),
          _requirement('One lowercase letter (a–z)', _hasLower, subtleColor),
          _requirement('One number (0–9)', _hasDigit, subtleColor),
          _requirement(r'One special character (!@#\$…)', _hasSpecial, subtleColor),
        ],
        const SizedBox(height: 20),
        _label('Confirm New Password', subtleColor),
        const SizedBox(height: 6),
        _inputContainer(
          surfaceColor: surfaceColor,
          borderColor: _confirmController.text.isNotEmpty
              ? (_passwordsMatch ? _accent.withValues(alpha: 0.5) : Colors.red.withValues(alpha: 0.5))
              : Colors.grey.withValues(alpha: 0.3),
          child: TextField(
            controller: _confirmController,
            obscureText: _obscureConfirm,
            style: TextStyle(color: textColor, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Re-enter your new password',
              hintStyle: TextStyle(color: subtleColor.withValues(alpha: 0.6)),
              prefixIcon: Icon(
                Icons.lock_outline_rounded,
                color: _confirmController.text.isNotEmpty ? (_passwordsMatch ? _accent : Colors.red) : _accent,
                size: 20,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  color: subtleColor,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
        if (_confirmController.text.isNotEmpty && !_passwordsMatch) ...[
          const SizedBox(height: 6),
          Text(
            'Passwords do not match',
            style: TextStyle(color: Colors.red[400], fontSize: 12),
          ),
        ],
        const SizedBox(height: 36),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          onPressed: (_isLoading || !_canSubmitNewPassword) ? null : _handleNewPasswordSubmit,
          child: _isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _buildSelectOtpStep(Color textColor, Color subtleColor, Color cardColor) {
    if (_loadingDestinations) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40.0),
          child: CircularProgressIndicator(color: _accent),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          'Select OTP Destination',
          style: TextStyle(color: textColor, fontSize: 26, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Choose where you want the 6-digit verification code to be sent.',
          style: TextStyle(color: subtleColor, fontSize: 14, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        ..._destinations.map((dest) {
          final isSelected = _selectedDestination == dest;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? _accent : Colors.grey.withValues(alpha: 0.2),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: ListTile(
              onTap: () {
                setState(() {
                  _selectedDestination = dest;
                });
              },
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  dest['type'] == 'email' ? Icons.email_rounded : Icons.phone_android_rounded,
                  color: _accent,
                  size: 20,
                ),
              ),
              title: Text(
                dest['label']!,
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              subtitle: Text(
                dest['display']!,
                style: TextStyle(color: subtleColor, fontSize: 13),
              ),
              trailing: isSelected
                  ? const Icon(Icons.check_circle_rounded, color: _accent)
                  : const Icon(Icons.radio_button_off_rounded, color: Colors.grey),
            ),
          );
        }),
        const SizedBox(height: 32),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          onPressed: _isSendingOtp ? null : () async {
            final sent = await _sendOtpToDestination(_selectedDestination!);
            if (!mounted) return;
            if (sent) {
              setState(() {
                _currentStep = ChangePasswordStep.verifyOtp;
              });
              _startResendTimer();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _otpFocusNodes[0].requestFocus();
              });
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Failed to send verification code. Please try again.'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          child: _isSendingOtp
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : const Text('Send Code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _buildVerifyOtpStep(Color textColor, Color subtleColor, Color cardColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _selectedDestination?['type'] == 'email' ? Icons.email_rounded : Icons.sms_rounded,
              color: _accent,
              size: 36,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Verify your identity',
          style: TextStyle(color: textColor, fontSize: 26, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'We sent a 6-digit code to',
          style: TextStyle(color: subtleColor, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          _selectedDestination?['display'] ?? '',
          style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            _boxCount,
            (i) => SizedBox(
              width: 46,
              height: 56,
              child: TextField(
                controller: _otpControllers[i],
                focusNode: _otpFocusNodes[i],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(1),
                ],
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _accent, width: 2),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (v) => _onOtpBoxChanged(i, v),
              ),
            ),
          ),
        ),
        if (_otpError.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            _otpError,
            style: TextStyle(color: Colors.red[400], fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 36),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          onPressed: (_isVerifyingOtp || _enteredOtp.length < _boxCount) ? null : _verifyOtpAndSavePassword,
          child: _isVerifyingOtp
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : const Text('Verify & Save', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Didn\'t receive a code? ', style: TextStyle(color: subtleColor, fontSize: 14)),
            _isSendingOtp
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
                  )
                : GestureDetector(
                    onTap: _resendOtp,
                    child: Text(
                      _resendSeconds > 0 ? 'Resend in ${_resendSeconds}s' : 'Resend',
                      style: TextStyle(
                        color: _resendSeconds > 0 ? subtleColor : _accent,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ],
        ),
      ],
    );
  }

  Widget _buildSuccessStep(Color textColor, Color subtleColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              color: _accent,
              size: 54,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Password Changed!',
          style: TextStyle(color: textColor, fontSize: 26, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Your password has been successfully updated. Use your new password the next time you sign in.',
          style: TextStyle(color: subtleColor, fontSize: 14, height: 1.6),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 48),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          onPressed: () {
            Navigator.pop(context); // Go back to profile page
          },
          child: const Text('Back to Profile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, Color textColor, Color subtleColor, Color surfaceColor, Color cardColor) {
    switch (_currentStep) {
      case ChangePasswordStep.auth:
        return _buildAuthStep(textColor, subtleColor, surfaceColor);
      case ChangePasswordStep.newPassword:
        return _buildNewPasswordStep(textColor, subtleColor, surfaceColor);
      case ChangePasswordStep.selectOtp:
        return _buildSelectOtpStep(textColor, subtleColor, cardColor);
      case ChangePasswordStep.verifyOtp:
        return _buildVerifyOtpStep(textColor, subtleColor, cardColor);
      case ChangePasswordStep.success:
        return _buildSuccessStep(textColor, subtleColor);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtleColor = isDark ? Colors.white70 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF131313) : const Color(0xFFF8F9FA);
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final surfaceColor = isDark ? Colors.grey[850]! : const Color(0xFFF5F5F5);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _currentStep == ChangePasswordStep.success
            ? null
            : IconButton(
                icon: Icon(Icons.arrow_back, color: textColor),
                onPressed: () {
                  if (_currentStep == ChangePasswordStep.auth) {
                    Navigator.pop(context);
                  } else if (_currentStep == ChangePasswordStep.newPassword) {
                    setState(() {
                      _currentStep = ChangePasswordStep.auth;
                      _currentPasswordController.clear();
                    });
                  } else if (_currentStep == ChangePasswordStep.selectOtp) {
                    setState(() {
                      _currentStep = ChangePasswordStep.newPassword;
                    });
                  } else if (_currentStep == ChangePasswordStep.verifyOtp) {
                    if (_destinations.length > 1) {
                      setState(() {
                        _currentStep = ChangePasswordStep.selectOtp;
                      });
                    } else {
                      setState(() {
                        _currentStep = ChangePasswordStep.newPassword;
                      });
                    }
                  }
                },
              ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: _buildBody(context, textColor, subtleColor, surfaceColor, cardColor),
        ),
      ),
    );
  }
}
