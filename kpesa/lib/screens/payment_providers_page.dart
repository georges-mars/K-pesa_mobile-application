import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';

class PaymentProvidersPage extends StatefulWidget {
  const PaymentProvidersPage({super.key});

  @override
  State<PaymentProvidersPage> createState() => _PaymentProvidersPageState();
}

class _PaymentProvidersPageState extends State<PaymentProvidersPage> {
  bool _loading = true;
  Map<String, dynamic>? _mpesa;
  Map<String, dynamic>? _airtel;
  Map<String, dynamic>? _bank;

  @override
  void initState() {
    super.initState();
    _fetchMethods();
  }

  Future<void> _fetchMethods() async {
    final methods = await ApiService.getPaymentMethods();
    if (!mounted) return;
    setState(() {
      _mpesa = methods.where((m) => m['type'] == 'mpesa').firstOrNull;
      _airtel = methods.where((m) => m['type'] == 'airtel').firstOrNull;
      _bank = methods.where((m) => m['type'] == 'bank').firstOrNull;
      _loading = false;
    });
  }

  void _openMobileSheet(String type, Map<String, dynamic>? existing) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PaymentMethodSheet(
        type: type,
        existingId: existing?['id'] as String?,
        isDark: isDark,
        onSaved: () {
          Navigator.pop(context);
          setState(() => _loading = true);
          _fetchMethods();
        },
      ),
    );
  }

  void _openBankSheet(Map<String, dynamic>? existing) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PaymentMethodSheet(
        type: 'bank',
        existingId: existing?['id'] as String?,
        isDark: isDark,
        onSaved: () {
          Navigator.pop(context);
          setState(() => _loading = true);
          _fetchMethods();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtleColor = isDark ? Colors.white70 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF131313) : const Color(0xFFF8F9FA);
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    const accentColor = Color.fromARGB(255, 55, 194, 21);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: textColor),
                  ),
                  Expanded(
                    child: Text(
                      'Payment Providers',
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

            if (_loading)
              const Expanded(
                  child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    const SizedBox(height: 24),

                    // ── Mobile Section ────────────────────────
                    _buildSectionHeader('Mobile', textColor),
                    const SizedBox(height: 16),
                    _buildProviderCard(
                      type: 'mpesa',
                      logoPath: 'assets/mpesa.png',
                      title: 'M-PESA',
                      subtitle: _mpesa != null
                          ? (_mpesa!['phone_number'] as String? ??
                              'M-PESA linked')
                          : 'Tap to link M-PESA',
                      isLinked: _mpesa != null,
                      existing: _mpesa,
                      cardBg: cardBg,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      accentColor: accentColor,
                    ),
                    const SizedBox(height: 12),
                    _buildProviderCard(
                      type: 'airtel',
                      logoPath: 'assets/airtel.png',
                      title: 'Airtel Money',
                      subtitle: _airtel != null
                          ? (_airtel!['phone_number'] as String? ??
                              'Airtel Money linked')
                          : 'Tap to link Airtel Money',
                      isLinked: _airtel != null,
                      existing: _airtel,
                      cardBg: cardBg,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      accentColor: accentColor,
                    ),
                    const SizedBox(height: 16),
                    _buildNote(
                      '* Tap a linked account to replace it with a new number — an OTP will be sent to verify ownership.',
                      subtleColor,
                    ),

                    const SizedBox(height: 40),

                    // ── Bank Section ──────────────────────────
                    _buildSectionHeader('Bank', textColor),
                    const SizedBox(height: 16),
                    _buildBankCard(
                      cardBg: cardBg,
                      textColor: textColor,
                      subtleColor: subtleColor,
                      accentColor: accentColor,
                    ),
                    const SizedBox(height: 16),
                    _buildNote(
                      '* Bank option is only available for withdrawals, not deposits.',
                      subtleColor,
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color textColor) {
    return Text(
      title,
      style: TextStyle(
        color: textColor,
        fontSize: 22,
        fontWeight: FontWeight.bold,
        fontFamily: 'Comic Sans MS',
      ),
    );
  }

  Widget _buildProviderCard({
    required String type,
    required String logoPath,
    required String title,
    required String subtitle,
    required bool isLinked,
    required Map<String, dynamic>? existing,
    required Color cardBg,
    required Color textColor,
    required Color subtleColor,
    required Color accentColor,
  }) {
    return GestureDetector(
      onTap: () => _openMobileSheet(type, existing),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(24),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 12,
          ),
          leading: Image.asset(
            logoPath,
            height: 40,
            width: 80,
            fit: BoxFit.contain,
            errorBuilder: (ctx, err, stack) =>
                Icon(Icons.account_balance_wallet,
                    color: accentColor, size: 32),
          ),
          title: Text(
            title,
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              color: isLinked ? accentColor : subtleColor,
              fontSize: 14,
            ),
          ),
          trailing: Icon(
            isLinked ? Icons.edit_outlined : Icons.add_circle_outline,
            color: accentColor.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }

  Widget _buildBankCard({
    required Color cardBg,
    required Color textColor,
    required Color subtleColor,
    required Color accentColor,
  }) {
    final hasBank = _bank != null;
    final bankTitle = hasBank
        ? (_bank!['bank_name'] as String? ?? 'Bank account')
        : 'Add New Bank';
    final bankSubtitle = hasBank
        ? (_bank!['account_name'] as String? ??
            _bank!['account_number'] as String? ??
            'Bank account linked')
        : 'Tap to add a bank account';

    return GestureDetector(
      onTap: () => _openBankSheet(_bank),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(24),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 12,
          ),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.account_balance_outlined,
              color: accentColor,
              size: 28,
            ),
          ),
          title: Text(
            bankTitle,
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            bankSubtitle,
            style: TextStyle(
              color: hasBank ? accentColor : subtleColor,
              fontSize: 14,
            ),
          ),
          trailing: Icon(
            hasBank ? Icons.edit_outlined : Icons.add_circle_outline,
            color: accentColor.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }

  Widget _buildNote(String text, Color subtleColor) {
    return Text(
      text,
      style: TextStyle(
        color: subtleColor.withValues(alpha: 0.8),
        fontSize: 13,
        height: 1.4,
      ),
    );
  }
}

// ── Payment Method Add / Replace Sheet ────────────────────────────────────────

class _PaymentMethodSheet extends StatefulWidget {
  final String type; // 'mpesa' | 'airtel' | 'bank'
  final String? existingId; // non-null = replace flow
  final bool isDark;
  final VoidCallback onSaved;

  const _PaymentMethodSheet({
    required this.type,
    required this.existingId,
    required this.isDark,
    required this.onSaved,
  });

  @override
  State<_PaymentMethodSheet> createState() => _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends State<_PaymentMethodSheet> {
  // 'phone' | 'otp' | 'bank_form'
  String _step = '';

  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  final _accountNameCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  static const _accent = Color.fromARGB(255, 55, 194, 21);

  @override
  void initState() {
    super.initState();
    _step = widget.type == 'bank' ? 'bank_form' : 'phone';
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _bankNameCtrl.dispose();
    _accountNameCtrl.dispose();
    _accountNumberCtrl.dispose();
    super.dispose();
  }

  Color get _textColor => widget.isDark ? Colors.white : Colors.black87;
  Color get _subtleColor => widget.isDark ? Colors.white70 : Colors.black54;
  Color get _fieldBg =>
      widget.isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5);

  String get _typeLabel => switch (widget.type) {
        'mpesa' => 'M-PESA',
        'airtel' => 'Airtel Money',
        _ => 'Bank Account',
      };

  // ── Step: phone input ───────────────────────────────────────────────────

  Widget _buildPhoneStep() {
    final isReplace = widget.existingId != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(isReplace ? 'Replace $_typeLabel' : 'Link $_typeLabel'),
        if (isReplace)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Your existing $_typeLabel number will be replaced.',
              style: TextStyle(color: Colors.orange.shade400, fontSize: 13),
            ),
          ),
        Text(
          'Enter the phone number. An OTP will be sent to verify you own it.',
          style: TextStyle(color: _subtleColor, fontSize: 13),
        ),
        const SizedBox(height: 16),
        _field(
          controller: _phoneCtrl,
          hint: '07XXXXXXXXXX',
          keyboard: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        _actionButton(
          label: 'Send OTP',
          onPressed: _onSendOtp,
        ),
      ],
    );
  }

  /// Converts 07XXXXXXXX (10 digits) → +2547XXXXXXXX for API calls.
  String _toE164(String phone) {
    final digits = phone.trim();
    if (digits.startsWith('0') && digits.length == 10) {
      return '+254${digits.substring(1)}';
    }
    return digits;
  }

  Future<void> _onSendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty || phone.length < 10) {
      setState(() => _error = 'Please enter a valid 10-digit number (e.g. 0712345678).');
      return;
    }
    setState(() { _loading = true; _error = null; });

    final sent = await ApiService.sendOtp(
      destination: _toE164(phone),
      type: 'sms',
      purpose: 'withdrawal',
    );
    if (!mounted) return;
    if (sent) {
      setState(() { _loading = false; _step = 'otp'; });
    } else {
      setState(() {
        _loading = false;
        _error = 'Could not send OTP. Check the number and try again.';
      });
    }
  }

  // ── Step: OTP verification ──────────────────────────────────────────────

  Widget _buildOtpStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('Verify Number',
            onBack: () => setState(() { _step = 'phone'; _error = null; })),
        Text(
          'Enter the OTP sent to ${_phoneCtrl.text.trim()}.',
          style: TextStyle(color: _subtleColor, fontSize: 13),
        ),
        const SizedBox(height: 16),
        _field(controller: _otpCtrl, hint: '6-digit code',
            keyboard: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ]),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        _actionButton(label: 'Verify & Save', onPressed: _onVerifyOtp),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _loading ? null : _resendOtp,
            child: Text('Resend OTP',
                style: TextStyle(color: _subtleColor, fontSize: 13)),
          ),
        ),
      ],
    );
  }

  Future<void> _onVerifyOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.isEmpty) {
      setState(() => _error = 'Please enter the OTP.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    final result = await ApiService.verifyOtp(
      destination: _toE164(_phoneCtrl.text.trim()),
      otp: otp,
      purpose: 'withdrawal',
    );
    if (!mounted) return;

    if (result.token == null) {
      setState(() {
        _loading = false;
        _error = result.errorMsg ?? 'OTP verification failed.';
      });
      return;
    }

    // Delete existing method if replacing
    if (widget.existingId != null) {
      final delErr = await ApiService.deletePaymentMethod(widget.existingId!);
      if (!mounted) return;
      if (delErr != null) {
        setState(() { _loading = false; _error = delErr; });
        return;
      }
    }

    // Save new method
    final err = await ApiService.addPaymentMethod(
      type: widget.type,
      phoneNumber: _toE164(_phoneCtrl.text.trim()),
    );
    if (!mounted) return;
    if (err == null) {
      widget.onSaved();
    } else {
      setState(() { _loading = false; _error = err; });
    }
  }

  Future<void> _resendOtp() async {
    setState(() { _loading = true; _error = null; });
    final sent = await ApiService.sendOtp(
      destination: _toE164(_phoneCtrl.text.trim()),
      type: 'sms',
      purpose: 'withdrawal',
    );
    if (!mounted) return;
    setState(() { _loading = false; });
    if (sent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('OTP resent.'), backgroundColor: _accent),
      );
    } else {
      setState(() => _error = 'Could not resend OTP. Try again.');
    }
  }

  // ── Step: bank form ─────────────────────────────────────────────────────

  Widget _buildBankStep() {
    final isReplace = widget.existingId != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(isReplace ? 'Replace Bank Account' : 'Add Bank Account'),
        if (isReplace)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Your existing bank account will be replaced.',
              style: TextStyle(color: Colors.orange.shade400, fontSize: 13),
            ),
          ),
        _field(controller: _bankNameCtrl, hint: 'Bank name (e.g. Equity)'),
        const SizedBox(height: 12),
        _field(controller: _accountNameCtrl, hint: 'Account holder name'),
        const SizedBox(height: 12),
        _field(
          controller: _accountNumberCtrl,
          hint: 'Account number',
          keyboard: TextInputType.number,
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        _actionButton(label: 'Save Bank Account', onPressed: _onSaveBank),
      ],
    );
  }

  Future<void> _onSaveBank() async {
    final bankName = _bankNameCtrl.text.trim();
    final accountName = _accountNameCtrl.text.trim();
    final accountNumber = _accountNumberCtrl.text.trim();

    if (bankName.isEmpty || accountName.isEmpty || accountNumber.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    if (widget.existingId != null) {
      final delErr = await ApiService.deletePaymentMethod(widget.existingId!);
      if (!mounted) return;
      if (delErr != null) {
        setState(() { _loading = false; _error = delErr; });
        return;
      }
    }

    final err = await ApiService.addPaymentMethod(
      type: 'bank',
      bankName: bankName,
      accountName: accountName,
      accountNumber: accountNumber,
    );
    if (!mounted) return;
    if (err == null) {
      widget.onSaved();
    } else {
      setState(() { _loading = false; _error = err; });
    }
  }

  // ── Shared helpers ───────────────────────────────────────────────────────

  Widget _header(String title, {VoidCallback? onBack}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          if (onBack != null) ...[
            GestureDetector(
              onTap: onBack,
              child: Icon(Icons.arrow_back_ios_new,
                  size: 18, color: _textColor),
            ),
            const SizedBox(width: 10),
          ],
          Text(title,
              style: TextStyle(
                  color: _textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboard = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      inputFormatters: inputFormatters,
      style: TextStyle(color: _textColor, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _subtleColor, fontSize: 14),
        filled: true,
        fillColor: _fieldBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _actionButton(
      {required String label, required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
        ),
        onPressed: _loading ? null : onPressed,
        child: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(
          key: ValueKey(_step),
          child: switch (_step) {
            'otp' => _buildOtpStep(),
            'bank_form' => _buildBankStep(),
            _ => _buildPhoneStep(),
          },
        ),
      ),
    );
  }
}
