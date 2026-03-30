import 'package:flutter/material.dart';

import '../models/signup_data.dart';
import 'set_password_screen.dart';

class AffiliateScreen extends StatefulWidget {
  final SignupData signupData;

  const AffiliateScreen({super.key, required this.signupData});

  @override
  State<AffiliateScreen> createState() => _AffiliateScreenState();
}

class _AffiliateScreenState extends State<AffiliateScreen> {
  static const _accent = Color.fromARGB(255, 55, 194, 21);

  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _continue(String? affiliateCode) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SetPasswordScreen(
          signupData: widget.signupData,
          affiliateCode:
              affiliateCode != null && affiliateCode.trim().isNotEmpty
              ? affiliateCode.trim()
              : null,
        ),
      ),
    );
  }

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
                const SizedBox(height: 56),

                // ── Icon ───────────────────────────────────────────────────────
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.card_giftcard_rounded,
                      color: _accent,
                      size: 38,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Title ──────────────────────────────────────────────────────
                Text(
                  'Referral Programme',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Were you referred to K-PESA by a friend?\nEnter their referral code below.',
                  style: TextStyle(
                    color: subtleColor,
                    fontSize: 14,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // ── Code input ────────────────────────────────────────────────
                Text(
                  'Referral Code (optional)',
                  style: TextStyle(
                    color: subtleColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
                  child: TextField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      letterSpacing: 2,
                    ),
                    decoration: InputDecoration(
                      hintText: 'e.g. KPESA123',
                      hintStyle: TextStyle(
                        color: subtleColor.withValues(alpha: 0.6),
                        letterSpacing: 0,
                      ),
                      prefixIcon: const Icon(
                        Icons.discount_rounded,
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
                const SizedBox(height: 48),

                // ── Continue button ───────────────────────────────────────────
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: () => _continue(_codeController.text),
                  child: const Text(
                    'Continue',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Skip button ───────────────────────────────────────────────
                TextButton(
                  onPressed: () => _continue(null),
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      color: subtleColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
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
}
