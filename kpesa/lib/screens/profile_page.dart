import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/biometric_service.dart';
import 'login_page.dart';
import 'payment_providers_page.dart';
import 'change_password_flow.dart';
import 'referral_earnings_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String _name = '';
  String _email = '';
  String _referralCode = '';
  double _referralEarnings = 0.0;
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  String _formatWithCommas(double value) {
    final parts = value.toStringAsFixed(2).split('.');
    final RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final String formattedInteger = parts[0].replaceAllMapped(reg, (Match match) => '${match[1]},');
    return '$formattedInteger.${parts[1]}';
  }

  Future<void> _fetchProfile() async {
    final profile = await ApiService.getProfile();
    if (!mounted || profile == null) return;
    setState(() {
      // Name priority: deriv_name → display_name (never full_name from registration)
      final derivName = profile['deriv_name'] as String?;
      final displayName = profile['display_name'] as String?;
      _name = (derivName != null && derivName.isNotEmpty)
          ? derivName
          : (displayName != null && displayName.isNotEmpty)
          ? displayName
          : '';
      _email = profile['email'] as String? ?? '';
    });

    final refProfile = await ApiService.getReferralProfile();
    if (!mounted) return;
    if (refProfile != null) {
      setState(() {
        _referralCode = refProfile['referralCode'] as String? ?? '';
        final earningsVal = refProfile['referralEarnings'];
        if (earningsVal is num) {
          _referralEarnings = earningsVal.toDouble();
        } else if (earningsVal is String) {
          _referralEarnings = double.tryParse(earningsVal) ?? 0.0;
        } else {
          _referralEarnings = 0.0;
        }
      });
    }

    _checkBiometricStatus();
  }

  Future<void> _checkBiometricStatus() async {
    final email = await BiometricService.getBiometricEmail();
    setState(() {
      _biometricEnabled = (email != null && email == _email);
    });
  }

  Future<void> _toggleBiometric() async {
    final available = await BiometricService.isBiometricAvailable();
    if (!mounted) return;
    if (!available) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Biometrics Not Available'),
          content: const Text(
            'Biometric authentication is not supported or not set up on this device. Please check your device system settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (_biometricEnabled) {
      // Prompt user to confirm disabling
      final disable = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Disable Biometric Login?'),
          content: const Text(
            'Are you sure you want to disable biometric login on this device?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Disable', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (disable != true || !mounted) return;

      final deviceId = await BiometricService.getDeviceId();
      if (!mounted) return;
      final error = await ApiService.removeBiometric(deviceId);
      
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      } else {
        await BiometricService.clearBiometricEmail();
        if (!mounted) return;
        setState(() {
          _biometricEnabled = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric login disabled.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      // Enable biometric login
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enable Biometric Login?'),
          content: const Text(
            'Would you like to use your fingerprint or face to sign in next time?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 55, 194, 21),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enable'),
            ),
          ],
        ),
      );

      if (accepted != true || !mounted) return;

      // Authenticate locally first
      final authenticated = await BiometricService.authenticate();
      if (!mounted) return;
      if (!authenticated) return;

      final deviceId = await BiometricService.getDeviceId();
      if (!mounted) return;
      final deviceName = await BiometricService.getDeviceName();
      if (!mounted) return;

      final enrollError = await ApiService.enrollBiometric(
        deviceId: deviceId,
        deviceName: deviceName,
      );

      if (!mounted) return;

      if (enrollError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(enrollError), backgroundColor: Colors.red),
        );
      } else {
        await BiometricService.saveBiometricEmail(_email);
        if (!mounted) return;
        setState(() {
          _biometricEnabled = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric login enabled!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }



  Future<void> _signOut() async {
    await ApiService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoginPage(onToggleTheme: () {})),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textColor = isDark ? Colors.white : Colors.black87;
    final subtleColor = isDark ? Colors.white70 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF131313) : const Color(0xFFF8F9FA);
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final innerCardBg = isDark
        ? const Color(0xFF262626)
        : const Color(0xFFF1F3F5);
    const accentColor = Color.fromARGB(255, 55, 194, 21);

    return Scaffold(
      backgroundColor: bgColor,
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity > 350) {
            Navigator.pop(context);
          }
        },
        child: SafeArea(
          child: Column(
            children: [
              // ── Header ────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: textColor),
                    ),
                    Expanded(
                      child: Text(
                        'Profile',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),

              Expanded(
                child: RefreshIndicator(
                  onRefresh: _fetchProfile,
                  color: accentColor,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    const SizedBox(height: 24),

                    // ── User Information ────────────────────────
                    Center(
                      child: Column(
                        children: [
                          const CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.transparent,
                            child: Icon(
                              Icons.account_circle,
                              size: 100,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _name.isEmpty ? '...' : _name,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _email.isEmpty ? '...' : _email,
                            style: TextStyle(color: subtleColor, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _referralCode.isEmpty ? '' : _referralCode,
                            style: TextStyle(
                              color: subtleColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Summary Section ─────────────────────────
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: isDark
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                      ),
                      child: Row(
                        children: [
                          _buildSummaryCard(
                            label: 'Deposits',
                            amount: 'Ksh. 0',
                            cardBg: innerCardBg,
                            accentColor: accentColor,
                            textColor: textColor,
                            subtleColor: subtleColor,
                            isDark: isDark,
                          ),
                          const SizedBox(width: 16),
                          _buildSummaryCard(
                            label: 'Withdrawals',
                            amount: 'Ksh. 0',
                            cardBg: innerCardBg,
                            accentColor: accentColor,
                            textColor: textColor,
                            subtleColor: subtleColor,
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Settings Menu ──────────────────────────
                    _buildMenuItem(
                      icon: Icons.phone_android_rounded,
                      title: 'Payment Providers',
                      subtitle: 'Add, modify, remove',
                      cardBg: cardBg,
                      accentColor: accentColor,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      isDark: isDark,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PaymentProvidersPage(),
                          ),
                        );
                      },
                    ),
                    _buildMenuItem(
                      icon: Icons.account_balance_wallet_rounded,
                      title: 'MT5 Account',
                      subtitle: 'MTR*****',
                      cardBg: cardBg,
                      accentColor: accentColor,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      isDark: isDark,
                    ),
                    _buildMenuItem(
                      icon: Icons.person_add_alt_1_rounded,
                      title: 'Default Accounts',
                      subtitle: 'MT5, Deposits, Withdrawals',
                      cardBg: cardBg,
                      accentColor: accentColor,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      isDark: isDark,
                    ),
                    _buildMenuItem(
                      icon: Icons.shield_outlined,
                      title: 'Change Password',
                      subtitle: '*******',
                      cardBg: cardBg,
                      accentColor: accentColor,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      isDark: isDark,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChangePasswordFlowPage(email: _email),
                          ),
                        );
                      },
                    ),
                    _buildMenuItem(
                      icon: Icons.fingerprint_rounded,
                      title: 'Biometric Login',
                      subtitle: _biometricEnabled ? 'Enabled' : 'Disabled',
                      cardBg: cardBg,
                      accentColor: accentColor,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      isDark: isDark,
                      onTap: _toggleBiometric,
                    ),
                    _buildMenuItem(
                      icon: Icons.monetization_on_rounded,
                      title: 'Earnings',
                      subtitle: 'Ksh. ${_formatWithCommas(_referralEarnings)}',
                      cardBg: cardBg,
                      accentColor: accentColor,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      isDark: isDark,
                      showArrow: false,
                    ),
                    _buildMenuItem(
                      icon: Icons.monetization_on_rounded,
                      title: 'Referral Earnings',
                      subtitle: 'View earnings and referral stats',
                      cardBg: cardBg,
                      accentColor: accentColor,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      isDark: isDark,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ReferralEarningsPage(),
                          ),
                        );
                      },
                    ),

                    _buildMenuItem(
                      icon: Icons.help_rounded,
                      title: 'Help & feedback',
                      subtitle: 'Help center, contact us',
                      cardBg: cardBg,
                      accentColor: accentColor,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      isDark: isDark,
                    ),
                    _buildMenuItem(
                      icon: Icons.settings_outlined,
                      title: 'Other Settings',
                      subtitle: 'Theme, notifications',
                      cardBg: cardBg,
                      accentColor: accentColor,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      isDark: isDark,
                    ),
                    _buildMenuItem(
                      icon: Icons.logout_rounded,
                      title: 'Sign Out',
                      cardBg: cardBg,
                      accentColor: accentColor,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      isDark: isDark,
                      showArrow: false,
                      onTap: _signOut,
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String label,
    required String amount,
    required Color cardBg,
    required Color accentColor,
    required Color textColor,
    required Color subtleColor,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 8),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.3),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Text(
                'KES',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              amount,
              style: TextStyle(
                color: textColor,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: subtleColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required Color cardBg,
    required Color accentColor,
    required Color textColor,
    required Color subtleColor,
    required bool isDark,
    VoidCallback? onTap,
    bool showArrow = true,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: accentColor, size: 24),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: textColor,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: subtitle != null
            ? Text(subtitle, style: TextStyle(color: subtleColor, fontSize: 13))
            : null,
        trailing: showArrow
            ? Icon(Icons.chevron_right, color: accentColor, size: 20)
            : null,
      ),
    ),
  );
}
}
