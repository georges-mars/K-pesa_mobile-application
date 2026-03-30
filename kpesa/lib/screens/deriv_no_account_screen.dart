import 'package:flutter/material.dart';

class DerivNoAccountScreen extends StatefulWidget {
  const DerivNoAccountScreen({super.key});

  @override
  State<DerivNoAccountScreen> createState() => _DerivNoAccountScreenState();
}

class _DerivNoAccountScreenState extends State<DerivNoAccountScreen> {
  bool _showNotice = true;

  static const _accent = Color.fromARGB(255, 55, 194, 21);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtleColor = isDark ? Colors.white70 : Colors.black54;
    final surfaceColor = isDark ? Colors.grey[900]! : Colors.white;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // ── Main content ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 48),
                  Text(
                    'Sign in to Deriv',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(),
                  Text(
                    'Link a live Deriv account to your K-PESA account.',
                    style: TextStyle(
                      color: subtleColor,
                      fontSize: 14,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    onPressed: () {
                      // TODO: re-launch Deriv OAuth
                    },
                    child: const Text(
                      'Continue to Deriv',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Go Back',
                      style: TextStyle(
                        color: _accent,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),

            // ── Notice overlay ───────────────────────────────────────────────
            if (_showNotice)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                      decoration: BoxDecoration(
                        color: surfaceColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Icon
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: _accent.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.info_outline_rounded,
                              color: _accent,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Notice',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "You don't have a live trading account. "
                            "Please create a live account on the Deriv "
                            "website before continuing.",
                            style: TextStyle(
                              color: subtleColor,
                              fontSize: 14,
                              height: 1.6,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          Divider(color: Colors.grey.withValues(alpha: 0.2)),
                          TextButton(
                            onPressed: () =>
                                setState(() => _showNotice = false),
                            child: const Text(
                              'OK',
                              style: TextStyle(
                                color: _accent,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
