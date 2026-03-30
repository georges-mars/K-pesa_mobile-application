import 'package:flutter/material.dart';

import '../models/signup_data.dart';
import '../services/api_service.dart';
import 'home_page.dart';

class SetPasswordScreen extends StatefulWidget {
  final SignupData signupData;
  final String? affiliateCode;

  const SetPasswordScreen({
    super.key,
    required this.signupData,
    this.affiliateCode,
  });

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  static const _accent = Color.fromARGB(255, 55, 194, 21);

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_rebuild);
    _confirmController.addListener(_rebuild);
    _emailController.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // ── Password strength ─────────────────────────────────────────────────────

  String get _password => _passwordController.text;

  bool get _hasLength => _password.length >= 8;
  bool get _hasUpper => _password.contains(RegExp(r'[A-Z]'));
  bool get _hasLower => _password.contains(RegExp(r'[a-z]'));
  bool get _hasDigit => _password.contains(RegExp(r'[0-9]'));
  bool get _hasSpecial => _password.contains(
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

  // ── Validation ────────────────────────────────────────────────────────────

  bool get _emailValid {
    if (widget.signupData.hasKnownEmail) return true;
    final e = _emailController.text.trim();
    return e.contains('@') && e.contains('.') && e.length > 5;
  }

  bool get _passwordsMatch => _password == _confirmController.text;

  bool get _canSubmit =>
      _emailValid &&
      _strength >= 3 &&
      _passwordsMatch &&
      _confirmController.text.isNotEmpty;

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _isLoading = true);

    final email = widget.signupData.hasKnownEmail
        ? widget.signupData.derivEmail!
        : _emailController.text.trim();

    // Use derivName if available; otherwise fall back to the email prefix.
    final fullName = (widget.signupData.derivName?.trim().isNotEmpty == true)
        ? widget.signupData.derivName!
        : email.split('@').first;

    final error = await ApiService.register(
      email: email,
      password: _passwordController.text,
      verificationToken: widget.signupData.verificationToken ?? '',
      fullName: fullName,
      derivEmail: widget.signupData.derivEmail,
      derivName: widget.signupData.derivName,
      derivAccount: widget.signupData.derivAccount,
      derivAccessToken: widget.signupData.derivAccessToken,
      derivRefreshToken: widget.signupData.derivRefreshToken,
      derivTokenExpiresAt: widget.signupData.derivTokenExpiresAt,
      binanceId: widget.signupData.binanceId,
      mpesaPhone: widget.signupData.mpesaPhone,
      airtelPhone: widget.signupData.airtelPhone,
      bankName: widget.signupData.bankName,
      bankAccountName: widget.signupData.bankAccountName,
      bankAccountNumber: widget.signupData.bankAccountNumber,
      affiliateCode: widget.affiliateCode,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                color: _accent,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Account Created!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Welcome to K-PESA. Your account is ready.',
              style: TextStyle(fontSize: 14, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            onPressed: () {
              Navigator.of(ctx).pop(); // close dialog
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomePage()),
                (_) => false, // clear entire back stack
              );
            },
            child: const Text('Go to Home'),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtleColor = isDark ? Colors.white70 : Colors.black54;
    final surfaceColor = isDark ? Colors.grey[850]! : const Color(0xFFF5F5F5);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),

                // ── Title ──────────────────────────────────────────────────────
                Text(
                  'Create your password',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Almost done! Set a strong password\nto secure your K-PESA account.',
                  style: TextStyle(
                    color: subtleColor,
                    fontSize: 14,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),

                // ── Email field ────────────────────────────────────────────────
                if (widget.signupData.hasKnownEmail) ...[
                  // Read-only: email came from Deriv
                  _label('Email Address', subtleColor),
                  const SizedBox(height: 6),
                  _readonlyField(
                    text: widget.signupData.derivEmail!,
                    icon: Icons.email_rounded,
                    surfaceColor: surfaceColor,
                    subtleColor: subtleColor,
                    textColor: subtleColor,
                  ),
                ] else ...[
                  // User must provide email
                  _label('Email Address', subtleColor),
                  const SizedBox(height: 6),
                  _inputContainer(
                    surfaceColor: surfaceColor,
                    child: TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: TextStyle(color: textColor, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'you@example.com',
                        hintStyle: TextStyle(
                          color: subtleColor.withValues(alpha: 0.6),
                        ),
                        prefixIcon: const Icon(
                          Icons.email_rounded,
                          color: _accent,
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // ── Password field ─────────────────────────────────────────────
                _label('Password', subtleColor),
                const SizedBox(height: 6),
                _inputContainer(
                  surfaceColor: surfaceColor,
                  child: TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: TextStyle(color: textColor, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Min. 8 characters',
                      hintStyle: TextStyle(
                        color: subtleColor.withValues(alpha: 0.6),
                      ),
                      prefixIcon: const Icon(
                        Icons.lock_rounded,
                        color: _accent,
                        size: 20,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          color: subtleColor,
                          size: 20,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // ── Strength bar ───────────────────────────────────────────────
                if (_password.isNotEmpty) ...[
                  Row(
                    children: [
                      ...List.generate(5, (i) {
                        final filled = i < _strength;
                        return Expanded(
                          child: Container(
                            margin: EdgeInsets.only(right: i < 4 ? 4 : 0),
                            height: 4,
                            decoration: BoxDecoration(
                              color: filled
                                  ? _strengthColor(_strength)
                                  : Colors.grey.withValues(alpha: 0.25),
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

                  // ── Requirements list ────────────────────────────────────────
                  _requirement(
                    'At least 8 characters',
                    _hasLength,
                    subtleColor,
                  ),
                  _requirement(
                    'One uppercase letter (A–Z)',
                    _hasUpper,
                    subtleColor,
                  ),
                  _requirement(
                    'One lowercase letter (a–z)',
                    _hasLower,
                    subtleColor,
                  ),
                  _requirement('One number (0–9)', _hasDigit, subtleColor),
                  _requirement(
                    'One special character (!@#\$…)',
                    _hasSpecial,
                    subtleColor,
                  ),
                ],
                const SizedBox(height: 20),

                // ── Confirm password ───────────────────────────────────────────
                _label('Confirm Password', subtleColor),
                const SizedBox(height: 6),
                _inputContainer(
                  surfaceColor: surfaceColor,
                  borderColor: _confirmController.text.isNotEmpty
                      ? (_passwordsMatch
                            ? _accent.withValues(alpha: 0.5)
                            : Colors.red.withValues(alpha: 0.5))
                      : Colors.grey.withValues(alpha: 0.3),
                  child: TextField(
                    controller: _confirmController,
                    obscureText: _obscureConfirm,
                    style: TextStyle(color: textColor, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Re-enter your password',
                      hintStyle: TextStyle(
                        color: subtleColor.withValues(alpha: 0.6),
                      ),
                      prefixIcon: Icon(
                        Icons.lock_outline_rounded,
                        color: _confirmController.text.isNotEmpty
                            ? (_passwordsMatch ? _accent : Colors.red)
                            : _accent,
                        size: 20,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          color: subtleColor,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
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

                const SizedBox(height: 40),

                // ── Create Account button ──────────────────────────────────────
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: (_canSubmit && !_isLoading) ? _submit : null,
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Create Account',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

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

  Widget _readonlyField({
    required String text,
    required IconData icon,
    required Color surfaceColor,
    required Color subtleColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: subtleColor, size: 20),
          const SizedBox(width: 12),
          Text(text, style: TextStyle(color: textColor, fontSize: 15)),
        ],
      ),
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
}
