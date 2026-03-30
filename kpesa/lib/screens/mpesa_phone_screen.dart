import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/signup_data.dart';
import '../services/api_service.dart';
import 'otp_screen.dart';

class MpesaPhoneScreen extends StatefulWidget {
  final SignupData signupData;

  const MpesaPhoneScreen({super.key, required this.signupData});

  @override
  State<MpesaPhoneScreen> createState() => _MpesaPhoneScreenState();
}

class _MpesaPhoneScreenState extends State<MpesaPhoneScreen> {
  static const _accent = Color.fromARGB(255, 55, 194, 21);

  // ── Selection state ──────────────────────────────────────────────────────────
  bool _mpesaSelected = false;
  bool _airtelSelected = false;
  bool _bankSelected = false;
  bool _isSending = false;

  // ── Field controllers ────────────────────────────────────────────────────────
  final _mpesaController = TextEditingController();
  final _airtelController = TextEditingController();
  final _accountNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  String? _selectedBank;

  // ── Kenyan banks ─────────────────────────────────────────────────────────────
  static const List<Map<String, String>> _kenyanBanks = [
    {'name': 'KCB Bank', 'asset': 'assets/payment_logos/banks/kcb.png'},
    {'name': 'Equity Bank', 'asset': 'assets/payment_logos/banks/equity.png'},
    {
      'name': 'Co-operative Bank',
      'asset': 'assets/payment_logos/banks/cooperative.png',
    },
    {'name': 'ABSA Bank Kenya', 'asset': 'assets/payment_logos/banks/absa.png'},
    {
      'name': 'Standard Chartered',
      'asset': 'assets/payment_logos/banks/stanchart.png',
    },
    {
      'name': 'Diamond Trust Bank',
      'asset': 'assets/payment_logos/banks/dtb.png',
    },
    {'name': 'I&M Bank', 'asset': 'assets/payment_logos/banks/imbank.png'},
    {'name': 'Family Bank', 'asset': 'assets/payment_logos/banks/family.png'},
    {'name': 'Stanbic Bank', 'asset': 'assets/payment_logos/banks/stanbic.png'},
    {'name': 'NCBA Bank', 'asset': 'assets/payment_logos/banks/ncba.png'},
    {
      'name': 'Ecobank Kenya',
      'asset': 'assets/payment_logos/banks/ecobank.png',
    },
    {'name': 'Sidian Bank', 'asset': 'assets/payment_logos/banks/sidian.png'},
    {'name': 'Prime Bank', 'asset': 'assets/payment_logos/banks/prime.png'},
    {
      'name': 'Gulf African Bank',
      'asset': 'assets/payment_logos/banks/gulf_african.png',
    },
    {
      'name': 'First Community Bank',
      'asset': 'assets/payment_logos/banks/first_community.png',
    },
    {'name': 'Faulu Bank', 'asset': 'assets/payment_logos/banks/faulu.png'},
    {'name': 'UBA Kenya', 'asset': 'assets/payment_logos/banks/uba.png'},
    {
      'name': 'National Bank',
      'asset': 'assets/payment_logos/banks/national.png',
    },
    {'name': 'GT Bank Kenya', 'asset': 'assets/payment_logos/banks/gtbank.png'},
    {
      'name': 'Bank of Baroda',
      'asset': 'assets/payment_logos/banks/baroda.png',
    },
    {'name': 'Citibank Kenya', 'asset': 'assets/payment_logos/banks/citi.png'},
    {'name': 'ABC Bank', 'asset': 'assets/payment_logos/banks/abc.png'},
    {
      'name': 'Consolidated Bank',
      'asset': 'assets/payment_logos/banks/consolidated.png',
    },
    {'name': 'HFC Kenya', 'asset': 'assets/payment_logos/banks/hfc.png'},
  ];

  @override
  void initState() {
    super.initState();
    _mpesaController.addListener(_rebuild);
    _airtelController.addListener(_rebuild);
    _accountNameController.addListener(_rebuild);
    _accountNumberController.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _mpesaController.dispose();
    _airtelController.dispose();
    _accountNameController.dispose();
    _accountNumberController.dispose();
    super.dispose();
  }

  // ── Validation ───────────────────────────────────────────────────────────────

  bool get _canProceed {
    if (!_mpesaSelected && !_airtelSelected && !_bankSelected) return false;
    if (_mpesaSelected && _mpesaController.text.trim().length != 10) {
      return false;
    }
    if (_airtelSelected && _airtelController.text.trim().length != 10) {
      return false;
    }
    if (_bankSelected) {
      if (_selectedBank == null) return false;
      if (_accountNameController.text.trim().isEmpty) return false;
      if (_accountNumberController.text.trim().isEmpty) return false;
    }
    return true;
  }

  // ── Proceed + OTP logic ───────────────────────────────────────────────────────

  /// Builds a SignupData that merges the parent's data with whatever the user
  /// filled in on this screen.
  SignupData _buildUpdatedSignupData() {
    return SignupData(
      binanceId: widget.signupData.binanceId,
      derivEmail: widget.signupData.derivEmail,
      derivName: widget.signupData.derivName,
      derivAccount: widget.signupData.derivAccount,
      derivAccessToken: widget.signupData.derivAccessToken,
      derivRefreshToken: widget.signupData.derivRefreshToken,
      derivTokenExpiresAt: widget.signupData.derivTokenExpiresAt,
      mpesaPhone: _mpesaSelected ? _mpesaController.text.trim() : null,
      airtelPhone: _airtelSelected ? _airtelController.text.trim() : null,
      bankName: _bankSelected ? _selectedBank : null,
      bankAccountName: _bankSelected
          ? _accountNameController.text.trim()
          : null,
      bankAccountNumber: _bankSelected
          ? _accountNumberController.text.trim()
          : null,
    );
  }

  Future<void> _onProceed() async {
    if (_isSending) return;

    final data = _buildUpdatedSignupData();
    final phone = data.primaryPhone;

    if (phone != null) {
      // ── Phone path: send OTP via backend ────────────────────────────────────
      setState(() => _isSending = true);
      final sent = await ApiService.sendOtp(
        destination: phone,
        type: 'sms',
        purpose: 'signup',
      );
      if (!mounted) return;
      setState(() => _isSending = false);

      if (!sent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not send OTP. Check your number and try again.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              OtpScreen(destination: phone, isEmail: false, signupData: data),
        ),
      );
    } else {
      // ── No phone: ask for email then send OTP (TODO: email API) ────────────
      _showEmailDialog(data);
    }
  }

  void _showEmailDialog(SignupData data) {
    final emailCtrl = TextEditingController();
    // Closure variables persist across StatefulBuilder rebuilds.
    bool isSending = false;
    bool showConfirm = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.email_rounded,
                  color: _accent,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                showConfirm ? 'Confirm email address' : 'Enter your email',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // ── Step 1: input ────────────────────────────────────────────────
              if (!showConfirm) ...[
                const Text(
                  'No phone number was linked. '
                  "We'll send your verification OTP to your email instead.",
                  style: TextStyle(fontSize: 13, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'you@example.com',
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: _accent,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _accent, width: 1.5),
                    ),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),

                // ── Step 2: confirm ──────────────────────────────────────────────
              ] else ...[
                const Text(
                  "We'll send your OTP to:",
                  style: TextStyle(fontSize: 13, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _accent.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    emailCtrl.text.trim(),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _accent,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: isSending
                      ? null
                      : () => setDialogState(() => showConfirm = false),
                  icon: const Icon(Icons.edit_rounded, size: 14),
                  label: const Text('Wrong email? Tap to edit'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],

              const SizedBox(height: 4),
            ],
          ),
          actions: !showConfirm
              ? [
                  // Step 1 actions
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: emailCtrl.text.trim().isEmpty
                        ? null
                        : () => setDialogState(() => showConfirm = true),
                    child: const Text('Next'),
                  ),
                ]
              : [
                  // Step 2 actions
                  TextButton(
                    onPressed: isSending ? null : () => Navigator.of(ctx).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: isSending
                        ? null
                        : () async {
                            setDialogState(() => isSending = true);
                            final email = emailCtrl.text.trim();
                            final sent = await ApiService.sendOtp(
                              destination: email,
                              type: 'email',
                              purpose: 'signup',
                            );
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            if (mounted) {
                              if (!sent) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Could not send OTP to $email. Try again.',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => OtpScreen(
                                    destination: email,
                                    isEmail: true,
                                    signupData: data,
                                  ),
                                ),
                              );
                            }
                          },
                    child: isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Confirm & Send OTP'),
                  ),
                ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required TextInputType keyboardType,
    List<TextInputFormatter>? formatters,
    required Color surfaceColor,
    required Color subtleColor,
    required Color textColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: subtleColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: formatters,
            style: TextStyle(color: textColor, fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: subtleColor.withValues(alpha: 0.6)),
              prefixIcon: Icon(icon, color: _accent, size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtleColor = isDark ? Colors.white70 : Colors.black54;
    final surfaceColor = isDark ? Colors.grey[850]! : const Color(0xFFF5F5F5);
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final dropdownBg = isDark ? Colors.grey[850]! : Colors.white;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),

                // ── Title ───────────────────────────────────────────────────────
                Text(
                  'Payment Methods',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Select at least one method to link to your account.',
                  style: TextStyle(
                    color: subtleColor,
                    fontSize: 14,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // ── M-Pesa card ─────────────────────────────────────────────────
                _PaymentCard(
                  selected: _mpesaSelected,
                  onTap: () => setState(() => _mpesaSelected = !_mpesaSelected),
                  cardColor: cardColor,
                  accent: _accent,
                  header: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        height: 36,
                        child: Image.asset(
                          'assets/payment_logos/mpesa.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.phone_android_rounded,
                            size: 28,
                            color: Color(0xFF4CAF50),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'M-Pesa',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  expandedContent: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _buildTextField(
                      controller: _mpesaController,
                      label: 'M-Pesa Phone Number',
                      hint: '07XXXXXXXX',
                      icon: Icons.phone_android_rounded,
                      keyboardType: TextInputType.phone,
                      formatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      surfaceColor: surfaceColor,
                      subtleColor: subtleColor,
                      textColor: textColor,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ── Airtel Money card ───────────────────────────────────────────
                _PaymentCard(
                  selected: _airtelSelected,
                  onTap: () =>
                      setState(() => _airtelSelected = !_airtelSelected),
                  cardColor: cardColor,
                  accent: _accent,
                  header: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        height: 36,
                        child: Image.asset(
                          'assets/payment_logos/airtel.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.phone_android_rounded,
                            size: 28,
                            color: Color(0xFFE53935),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Airtel Money',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  expandedContent: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _buildTextField(
                      controller: _airtelController,
                      label: 'Airtel Money Phone Number',
                      hint: '07XXXXXXXX',
                      icon: Icons.phone_android_rounded,
                      keyboardType: TextInputType.phone,
                      formatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      surfaceColor: surfaceColor,
                      subtleColor: subtleColor,
                      textColor: textColor,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ── Bank card ───────────────────────────────────────────────────
                _PaymentCard(
                  selected: _bankSelected,
                  onTap: () => setState(() {
                    _bankSelected = !_bankSelected;
                    if (!_bankSelected) {
                      _selectedBank = null;
                      _accountNameController.clear();
                      _accountNumberController.clear();
                    }
                  }),
                  cardColor: cardColor,
                  accent: _accent,
                  header: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.account_balance_rounded,
                          color: _accent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Bank',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  expandedContent: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),

                      // Bank dropdown
                      Text(
                        'Select Bank',
                        style: TextStyle(
                          color: subtleColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.withValues(alpha: 0.3),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedBank,
                            isExpanded: true,
                            dropdownColor: dropdownBg,
                            borderRadius: BorderRadius.circular(12),
                            hint: Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.account_balance_rounded,
                                    color: _accent,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Select your bank',
                                    style: TextStyle(
                                      color: subtleColor.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Each item shows favicon + name
                            items: _kenyanBanks.map((bank) {
                              return DropdownMenuItem<String>(
                                value: bank['name'],
                                child: Row(
                                  children: [
                                    const SizedBox(width: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.asset(
                                        bank['asset']!,
                                        width: 26,
                                        height: 26,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, _, _) => const Icon(
                                          Icons.account_balance,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      bank['name']!,
                                      style: TextStyle(color: textColor),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            // Collapsed selected state: bank logo + name
                            selectedItemBuilder: (ctx) => _kenyanBanks.map((
                              bank,
                            ) {
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: Image.asset(
                                          bank['asset']!,
                                          width: 24,
                                          height: 24,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, _, _) => const Icon(
                                            Icons.account_balance_rounded,
                                            color: _accent,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        bank['name']!,
                                        style: TextStyle(color: textColor),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) =>
                                setState(() => _selectedBank = val),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _accountNameController,
                        label: 'Account Name',
                        hint: 'e.g. John Doe',
                        icon: Icons.person_rounded,
                        keyboardType: TextInputType.name,
                        surfaceColor: surfaceColor,
                        subtleColor: subtleColor,
                        textColor: textColor,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _accountNumberController,
                        label: 'Account Number',
                        hint: 'Enter account number',
                        icon: Icons.tag_rounded,
                        keyboardType: TextInputType.number,
                        formatters: [FilteringTextInputFormatter.digitsOnly],
                        surfaceColor: surfaceColor,
                        subtleColor: subtleColor,
                        textColor: textColor,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // ── Proceed button ──────────────────────────────────────────────
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: (_canProceed && !_isSending) ? _onProceed : null,
                  child: _isSending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Proceed',
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
        ),
      ),
    );
  }
}

// ── Toggleable payment selection card ─────────────────────────────────────────

class _PaymentCard extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Color cardColor;
  final Color accent;
  final Widget header;
  final Widget expandedContent;

  const _PaymentCard({
    required this.selected,
    required this.onTap,
    required this.cardColor,
    required this.accent,
    required this.header,
    required this.expandedContent,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? accent : Colors.grey.withValues(alpha: 0.25),
          width: selected ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header row (always visible, tappable) ─────────────────────────
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(child: header),
                  // Animated checkbox
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: selected ? accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected
                            ? accent
                            : Colors.grey.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 16,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded content (animated open/close) ────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: selected
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Divider(
                        color: Colors.grey.withValues(alpha: 0.2),
                        height: 1,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: expandedContent,
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
