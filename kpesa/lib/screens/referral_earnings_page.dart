import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';

class ReferralEarningsPage extends StatefulWidget {
  const ReferralEarningsPage({super.key});

  @override
  State<ReferralEarningsPage> createState() => _ReferralEarningsPageState();
}

class _ReferralEarningsPageState extends State<ReferralEarningsPage> {
  static const _accent = Color.fromARGB(255, 55, 194, 21);
  bool _isLoading = true;
  double _earnings = 0.0;
  int _referralsCount = 0;
  String _terms = '';
  String _referralCode = '';

  @override
  void initState() {
    super.initState();
    _fetchEarnings();
  }

  Future<void> _fetchEarnings() async {
    setState(() => _isLoading = true);
    final data = await ApiService.getEarnings();
    if (!mounted) return;
    if (data != null) {
      setState(() {
        _earnings = (data['earnings'] as num?)?.toDouble() ?? 0.0;
        _referralsCount = (data['referralsCount'] as num?)?.toInt() ?? 0;
        _terms = data['terms'] as String? ?? 'No referral agreement found.';
        _referralCode = data['referralCode'] as String? ?? '';
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtleColor = isDark ? Colors.white70 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF131313) : const Color(0xFFF8F9FA);
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Referral Earnings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : RefreshIndicator(
              onRefresh: _fetchEarnings,
              color: _accent,
              child: ListView(
                padding: const EdgeInsets.all(24.0),
                children: [
                  // Earnings Circle
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.monetization_on_rounded,
                        color: _accent,
                        size: 50,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Total Earnings Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: isDark
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Ksh. ${_earnings.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Total Earnings',
                          style: TextStyle(color: subtleColor, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Referrals Count Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: isDark
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Successful Referrals',
                          style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                        Text(
                          '$_referralsCount',
                          style: TextStyle(color: _accent, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Agreement Terms Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: isDark
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Agreement Terms',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _terms,
                          style: TextStyle(
                            color: subtleColor,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Referral Code Card
                  if (_referralCode.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: _accent.withValues(alpha: 0.2), width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'YOUR REFERRAL CODE',
                                  style: TextStyle(
                                    color: subtleColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _referralCode,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, color: _accent),
                            tooltip: 'Copy referral code',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _referralCode));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Referral code copied to clipboard!'),
                                  backgroundColor: _accent,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
