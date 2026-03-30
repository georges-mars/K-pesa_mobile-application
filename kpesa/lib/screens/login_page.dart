import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/biometric_service.dart';
import 'sign_up_page.dart';
import 'home_page.dart';
import 'forgot_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onToggleTheme});

  final VoidCallback onToggleTheme;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  // Biometric state
  bool _biometricAvailable = false;
  String? _biometricEmail;

  Color get _accentColor => const Color.fromARGB(255, 55, 194, 21);

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final available = await BiometricService.isBiometricAvailable();
    final email = await BiometricService.getBiometricEmail();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricEmail = email;
    });

    // Auto-trigger biometric prompt if enrolled
    if (available && email != null && email.isNotEmpty) {
      _biometricLogin();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtleColor = isDark ? Colors.white70 : Colors.black54;
    final borderColor = isDark ? Colors.white54 : Colors.black38;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      color: isDark ? Colors.black : Colors.white,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: Icon(
                      isDark ? Icons.light_mode : Icons.dark_mode,
                      color: subtleColor,
                    ),
                    tooltip: isDark
                        ? 'Switch to light mode'
                        : 'Switch to dark mode',
                    onPressed: widget.onToggleTheme,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Image.asset(
                      isDark
                          ? 'assets/K-PESA.png'
                          : 'assets/K-pesa_light_mode.png',
                      key: ValueKey(isDark),
                      width: 650,
                      height: 650,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildEmailField(textColor, subtleColor, borderColor),
                const SizedBox(height: 16),
                _buildPasswordField(textColor, subtleColor, borderColor),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _forgotPassword,
                    child: Text(
                      'Forgot password?',
                      style: TextStyle(color: _accentColor, fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentColor,
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: _isLoading ? null : _signIn,
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
                          'Sign in',
                          style: TextStyle(fontSize: 18, color: Colors.white),
                        ),
                ),
                // ── Biometric login button ────────────────────────────────
                if (_biometricAvailable && _biometricEmail != null) ...[
                  const SizedBox(height: 12),
                  _buildBiometricButton(subtleColor),
                ],
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account?",
                      style: TextStyle(color: subtleColor),
                    ),
                    TextButton(
                      onPressed: _signUp,
                      child: Text(
                        'Sign up',
                        style: TextStyle(color: _accentColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Biometric button ────────────────────────────────────────────────────────

  Widget _buildBiometricButton(Color subtleColor) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: _accentColor),
        padding: const EdgeInsets.symmetric(vertical: 14.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
      onPressed: _isLoading ? null : _biometricLogin,
      icon: Icon(Icons.fingerprint, color: _accentColor, size: 28),
      label: Text(
        'Sign in with Biometrics',
        style: TextStyle(fontSize: 16, color: _accentColor),
      ),
    );
  }

  // ── Biometric login flow ──────────────────────────────────────────────────

  Future<void> _biometricLogin() async {
    setState(() => _isLoading = true);
    try {
      final authenticated = await BiometricService.authenticate();
      if (!authenticated) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final deviceId = await BiometricService.getDeviceId();
      final error = await ApiService.biometricLogin(deviceId);
      if (!mounted) return;

      if (error != null) {
        setState(() => _isLoading = false);
        // Device might have been revoked server-side
        if (error.contains('not enrolled')) {
          await BiometricService.clearBiometricEmail();
          setState(() => _biometricEmail = null);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
        return;
      }

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
        (_) => false,
      );
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Fields ──────────────────────────────────────────────────────────────────

  Widget _buildEmailField(
    Color textColor,
    Color subtleColor,
    Color borderColor,
  ) {
    return TextField(
      controller: _emailController,
      style: TextStyle(color: textColor),
      keyboardType: TextInputType.emailAddress,
      decoration: InputDecoration(
        labelText: 'Email',
        labelStyle: TextStyle(color: subtleColor),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide(color: _accentColor),
        ),
      ),
    );
  }

  Widget _buildPasswordField(
    Color textColor,
    Color subtleColor,
    Color borderColor,
  ) {
    return TextField(
      controller: _passwordController,
      style: TextStyle(color: textColor),
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: 'Password',
        labelStyle: TextStyle(color: subtleColor),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide(color: _accentColor),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
            color: subtleColor,
          ),
          onPressed: () {
            setState(() {
              _obscurePassword = !_obscurePassword;
            });
          },
        ),
      ),
    );
  }

  // ── Password sign-in (with biometric enrollment prompt) ────────────────────

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) return;

    setState(() => _isLoading = true);
    final error = await ApiService.login(email, password);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error != null) {
      if (_isNetworkError(error)) {
        _showErrorDialog(error);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      }
      return;
    }

    // ── Offer biometric enrollment if device supports it ──────────────────
    if (_biometricAvailable && _biometricEmail == null) {
      await _offerBiometricEnrollment(email);
    }

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
      (_) => false,
    );
  }

  /// Shows a dialog asking whether to enable biometric login on this device.
  Future<void> _offerBiometricEnrollment(String email) async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Enable Biometric Login?'),
        content: const Text(
          'Would you like to use your fingerprint or face to sign in next time?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accentColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enable',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (accepted != true || !mounted) return;

    // Verify biometrics locally first
    final authenticated = await BiometricService.authenticate();
    if (!authenticated) return;

    final deviceId = await BiometricService.getDeviceId();
    final deviceName = await BiometricService.getDeviceName();

    final enrollError = await ApiService.enrollBiometric(
      deviceId: deviceId,
      deviceName: deviceName,
    );

    if (enrollError == null) {
      await BiometricService.saveBiometricEmail(email);
      if (mounted) {
        setState(() => _biometricEmail = email);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric login enabled!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  bool _isNetworkError(String error) {
    return error.contains('Network error') ||
        error.contains('timed out') ||
        error.contains('connection');
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connection Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ok'),
          ),
        ],
      ),
    );
  }

  void _forgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
    );
  }

  void _signUp() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SignUpPage()),
    );
  }
}
