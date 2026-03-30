import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/signup_data.dart';
import '../services/api_service.dart';
import 'affiliate_screen.dart';

class OtpScreen extends StatefulWidget {
  final String destination;
  final bool isEmail;
  final SignupData signupData;

  const OtpScreen({
    super.key,
    required this.destination,
    required this.isEmail,
    required this.signupData,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const _accent = Color.fromARGB(255, 55, 194, 21);
  static const _boxCount = 6;

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  late String _currentDest;
  bool _isEditingDest = false;
  late final TextEditingController _destController;
  bool _isVerifying = false;
  bool _isResending = false;
  String _error = '';
  int _resendSeconds = 60;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _currentDest = widget.destination;
    _destController = TextEditingController(text: widget.destination);
    _controllers = List.generate(_boxCount, (_) => TextEditingController());

    _focusNodes = List.generate(_boxCount, (i) {
      final node = FocusNode();
      node.onKeyEvent = (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace &&
            _controllers[i].text.isEmpty &&
            i > 0) {
          _controllers[i - 1].clear();
          _focusNodes[i - 1].requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      };
      return node;
    });

    _startResendTimer();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNodes[0].requestFocus(),
    );
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _destController.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
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

  String get _enteredOtp => _controllers.map((c) => c.text).join();

  void _onChanged(int index, String value) {
    if (value.isEmpty) return;
    setState(() => _error = '');
    if (index < _boxCount - 1) {
      _focusNodes[index + 1].requestFocus();
    } else {
      _focusNodes[index].unfocus();
    }
    if (_enteredOtp.length == _boxCount) _verify();
  }

  // ── Verify (calls backend /otp/verify) ────────────────────────────────────

  Future<void> _verify() async {
    if (_isVerifying) return;
    setState(() {
      _isVerifying = true;
      _error = '';
    });

    final result = await ApiService.verifyOtp(
      destination: _currentDest,
      otp: _enteredOtp,
      purpose: 'signup',
    );

    if (!mounted) return;

    if (result.token != null) {
      // OTP verified — attach verificationToken and proceed to affiliate step
      final updatedData = widget.signupData.copyWith(
        verificationToken: result.token,
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AffiliateScreen(signupData: updatedData),
        ),
      );
    } else {
      setState(() {
        _isVerifying = false;
        _error = result.errorMsg ?? 'Incorrect code. Please try again.';
        for (final c in _controllers) {
          c.clear();
        }
      });
      _focusNodes[0].requestFocus();
    }
  }

  // ── Resend (calls backend /otp/send) ──────────────────────────────────────

  Future<void> _resend() async {
    if (_resendSeconds > 0 || _isResending) return;
    setState(() => _isResending = true);

    final sent = await ApiService.sendOtp(
      destination: _currentDest,
      type: widget.isEmail ? 'email' : 'sms',
      purpose: 'signup',
    );

    if (!mounted) return;
    setState(() {
      _error = '';
      _isResending = false;
      for (final c in _controllers) {
        c.clear();
      }
    });
    _startResendTimer();
    _focusNodes[0].requestFocus();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent
              ? 'New code sent to $_currentDest'
              : 'Could not send code. Please try again.',
        ),
        backgroundColor: sent ? _accent : Colors.red,
      ),
    );
  }

  Future<void> _resendToNewEmail(String newEmail) async {
    setState(() => _isResending = true);

    final sent = await ApiService.sendOtp(
      destination: newEmail,
      type: 'email',
      purpose: 'signup',
    );

    if (!mounted) return;
    setState(() {
      if (sent) {
        _currentDest = newEmail;
        _destController.text = newEmail;
      }
      _isEditingDest = false;
      _isResending = false;
      for (final c in _controllers) {
        c.clear();
      }
    });
    if (sent) {
      _startResendTimer();
      _focusNodes[0].requestFocus();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent ? 'New code sent to $newEmail' : 'Could not send to $newEmail.',
        ),
        backgroundColor: sent ? _accent : Colors.red,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtleColor = isDark ? Colors.white70 : Colors.black54;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 56),
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.isEmail ? Icons.email_rounded : Icons.sms_rounded,
                      color: _accent,
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Verify your identity',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'We sent a 6-digit code to',
                  style: TextStyle(color: subtleColor, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),

                // ── Destination row (editable for email flow) ──────────────────
                if (widget.isEmail && _isEditingDest) ...[
                  TextField(
                    controller: _destController,
                    keyboardType: TextInputType.emailAddress,
                    textAlign: TextAlign.center,
                    autofocus: true,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: 'new@example.com',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: _accent,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() {
                          _destController.text = _currentDest;
                          _isEditingDest = false;
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    onPressed:
                        (_isResending || _destController.text.trim().isEmpty)
                        ? null
                        : () => _resendToNewEmail(_destController.text.trim()),
                    icon: _isResending
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Send OTP to this address'),
                  ),
                ] else ...[
                  GestureDetector(
                    onTap: widget.isEmail
                        ? () => setState(() => _isEditingDest = true)
                        : null,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _currentDest,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (widget.isEmail) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.edit_rounded,
                            size: 14,
                            color: subtleColor,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 40),

                // ── OTP boxes ──────────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(
                    _boxCount,
                    (i) => _otpBox(i, cardColor, textColor),
                  ),
                ),

                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error,
                    style: TextStyle(color: Colors.red[400], fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],

                const SizedBox(height: 36),

                // ── Verify button ──────────────────────────────────────────────
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: (_isVerifying || _enteredOtp.length < _boxCount)
                      ? null
                      : _verify,
                  child: _isVerifying
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Verify',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(height: 20),

                // ── Resend row ─────────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Didn't receive a code? ",
                      style: TextStyle(color: subtleColor, fontSize: 14),
                    ),
                    _isResending
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _accent,
                            ),
                          )
                        : GestureDetector(
                            onTap: _resend,
                            child: Text(
                              _resendSeconds > 0
                                  ? 'Resend in ${_resendSeconds}s'
                                  : 'Resend',
                              style: TextStyle(
                                color: _resendSeconds > 0
                                    ? subtleColor
                                    : _accent,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _otpBox(int index, Color cardColor, Color textColor) {
    return SizedBox(
      width: 46,
      height: 56,
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(1),
        ],
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
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
        onChanged: (v) => _onChanged(index, v),
      ),
    );
  }
}
