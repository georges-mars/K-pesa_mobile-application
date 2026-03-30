import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

class WithdrawPage extends StatefulWidget {
  const WithdrawPage({super.key});

  @override
  State<WithdrawPage> createState() => _WithdrawPageState();
}

class _WithdrawPageState extends State<WithdrawPage> {
  // 0 = Deriv, 1 = MT5, 2 = Binance
  int _selectedTab = 0;
  String _amountStr = '0';
  bool _isKesInput = false;
  bool _isWithdrawDialogVisible = true;
  bool _showLimitError = false;
  bool _isInitiating = false;

  // Payment methods
  List<Map<String, dynamic>> _paymentMethods = [];
  bool _loadingMethods = true;
  String? _selectedMethodId;

  @override
  void initState() {
    super.initState();
    _fetchPaymentMethods();
  }

  Future<void> _fetchPaymentMethods() async {
    final methods = await ApiService.getPaymentMethods();
    if (!mounted) return;
    setState(() {
      _paymentMethods = methods;
      _loadingMethods = false;
      if (methods.isNotEmpty) {
        final def = methods.firstWhere(
          (m) => m['is_default'] == true,
          orElse: () => methods.first,
        );
        _selectedMethodId = def['id'] as String?;
      }
    });
  }

  Future<void> _initiateWithdrawal() async {
    if (_selectedMethodId == null || _isInitiating) return;
    final method = _paymentMethods.firstWhere(
      (m) => m['id'] == _selectedMethodId,
      orElse: () => <String, dynamic>{},
    );
    final type = method['type'] as String? ?? '';
    if (type == 'bank') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bank withdrawals are coming soon.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final phone = method['phone_number'] as String? ?? '';
    if (phone.isEmpty) return;

    setState(() => _isInitiating = true);
    final sourceType = ['deriv', 'mt5', 'binance'][_selectedTab];
    final result = await ApiService.initiateWithdrawal(
      amountUsd: _usdAmount,
      sourceType: sourceType,
      mpesaPhone: phone,
    );
    if (!mounted) return;
    setState(() => _isInitiating = false);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not initiate withdrawal. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Withdrawal initiated. KES will be sent to $phone shortly.',
        ),
        backgroundColor: _accent,
        duration: const Duration(seconds: 8),
      ),
    );
  }

  static const _accent = Color.fromARGB(255, 55, 194, 21);
  static const double _exchangeRate = 124.08;

  double get _usdAmount {
    final parsed = double.tryParse(_amountStr) ?? 0;
    return _isKesInput ? (parsed / _exchangeRate) : parsed;
  }

  double get _kesAmount {
    final parsed = double.tryParse(_amountStr) ?? 0;
    return _isKesInput ? parsed : (parsed * _exchangeRate);
  }

  String get _displayAmount {
    if (_amountStr.isEmpty) return '0';
    return _amountStr;
  }

  void _onDigit(String digit) {
    setState(() {
      String newStr = _amountStr;
      if (digit == '.') {
        if (!_amountStr.contains('.')) {
          newStr += '.';
        }
      } else {
        if (_amountStr == '0') {
          newStr = digit;
        } else if (_amountStr.length < 12) {
          newStr += digit;
        }
      }

      final parsed = double.tryParse(newStr) ?? 0;
      final kesVal = _isKesInput ? parsed : (parsed * _exchangeRate);

      if (kesVal <= 250000) {
        _amountStr = newStr;
        _showLimitError = (kesVal >= 250000);
      } else {
        _showLimitError = true;
      }
    });
  }

  void _onBackspace() {
    setState(() {
      if (_amountStr.length > 1) {
        _amountStr = _amountStr.substring(0, _amountStr.length - 1);
      } else {
        _amountStr = '0';
      }
      final parsed = double.tryParse(_amountStr) ?? 0;
      final kesVal = _isKesInput ? parsed : (parsed * _exchangeRate);
      if (kesVal < 250000) {
        _showLimitError = false;
      }
    });
  }

  // ── Overlay: payment method selection ─────────────────────────────────────

  Widget _buildWithdrawAccountChoiceOverlay(
    bool isDark,
    Color textColor,
    Color cardBg,
    Color subtleColor,
  ) {
    final hasMobileMoney = _paymentMethods.any(
      (m) => m['type'] == 'mpesa' || m['type'] == 'airtel',
    );
    final hasBank = _paymentMethods.any((m) => m['type'] == 'bank');
    final canLinkMore = !hasMobileMoney || !hasBank;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Choose Account',
          style: TextStyle(
            color: textColor,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Select where you want to receive your withdrawal.',
          textAlign: TextAlign.center,
          style: TextStyle(color: subtleColor, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 20),

        if (_loadingMethods)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: CircularProgressIndicator(color: _accent),
          )
        else if (_paymentMethods.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No payment methods linked.\nTap below to add one.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subtleColor, fontSize: 14),
            ),
          )
        else
          ..._paymentMethods.map(
            (m) => _buildMethodTile(m, isDark, textColor, subtleColor),
          ),

        if (canLinkMore && !_loadingMethods) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _showLinkNewMethodSheet(
              hasMobileMoney: hasMobileMoney,
              hasBank: hasBank,
              isDark: isDark,
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDark ? Colors.white24 : Colors.black26,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline, color: _accent, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Link something new',
                    style: TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 24),

        TextButton(
          onPressed: (_selectedMethodId != null && !_loadingMethods)
              ? () {
                  setState(() => _isWithdrawDialogVisible = false);
                  _initiateWithdrawal();
                }
              : null,
          child: Text(
            'Proceed',
            style: TextStyle(
              color: (_selectedMethodId != null && !_loadingMethods)
                  ? _accent
                  : Colors.white38,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel Withdrawal',
            style: TextStyle(
              color: _accent,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMethodTile(
    Map<String, dynamic> method,
    bool isDark,
    Color textColor,
    Color subtleColor,
  ) {
    final type = method['type'] as String? ?? '';
    final id = method['id'] as String? ?? '';
    final isSelected = _selectedMethodId == id;

    String typeLabel;
    String detail;
    Color labelColor;

    switch (type) {
      case 'mpesa':
        typeLabel = 'M-PESA';
        detail = method['phone_number'] as String? ?? '';
        labelColor = Colors.green.shade700;
        break;
      case 'airtel':
        typeLabel = 'Airtel';
        detail = method['phone_number'] as String? ?? '';
        labelColor = Colors.red.shade700;
        break;
      case 'bank':
        typeLabel = method['bank_name'] as String? ?? 'Bank';
        detail = method['account_name'] as String? ?? '';
        labelColor = Colors.blue.shade700;
        break;
      default:
        typeLabel = type;
        detail = '';
        labelColor = Colors.grey;
    }

    return GestureDetector(
      onTap: () => setState(() => _selectedMethodId = id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          border: Border.all(
            color: isSelected
                ? _accent
                : (isDark ? Colors.white10 : Colors.black12),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: labelColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                typeLabel,
                style: TextStyle(
                  color: labelColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    typeLabel,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      style: TextStyle(color: subtleColor, fontSize: 12),
                    ),
                ],
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? _accent : Colors.transparent,
                border: Border.all(
                  color: isSelected ? _accent : Colors.grey,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  void _showLinkNewMethodSheet({
    required bool hasMobileMoney,
    required bool hasBank,
    required bool isDark,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _LinkNewMethodSheet(
        hasMobileMoney: hasMobileMoney,
        hasBank: hasBank,
        isDark: isDark,
        onLinked: () {
          Navigator.pop(context); // close the bottom sheet
          _fetchPaymentMethods(); // refresh the list
        },
      ),
    );
  }

  // ── Existing dialogs (unchanged) ──────────────────────────────────────────

  void _showMT5LinkDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim1, anim2, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDark ? Colors.white : Colors.black87;
        final cardBg = isDark
            ? const Color(0xFF232323)
            : const Color.fromARGB(255, 240, 240, 240);

        return FadeTransition(
          opacity: anim1,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(
                  CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
                ),
            child: Dialog(
              backgroundColor: cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 24.0,
                      bottom: 16.0,
                      left: 16.0,
                      right: 16.0,
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Notice',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Please select the MT5 account that you wish to link to your M-PESA account',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 15,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    color: isDark ? Colors.white10 : Colors.black12,
                    thickness: 1,
                    height: 1,
                  ),
                  IntrinsicHeight(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              setState(() => _selectedTab = 1);
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.only(
                                  bottomLeft: Radius.circular(16),
                                ),
                              ),
                            ),
                            child: const Text(
                              'Select',
                              style: TextStyle(
                                color: _accent,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        VerticalDivider(
                          color: isDark ? Colors.white10 : Colors.black12,
                          thickness: 1,
                          width: 1,
                        ),
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              setState(() => _selectedTab = 0);
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.only(
                                  bottomRight: Radius.circular(16),
                                ),
                              ),
                            ),
                            child: const Text(
                              'Not Now',
                              style: TextStyle(
                                color: _accent,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showBinanceActionDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim1, anim2, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDark ? Colors.white : Colors.black87;
        final cardBg = isDark
            ? const Color(0xFF232323)
            : const Color.fromARGB(255, 240, 240, 240);

        return FadeTransition(
          opacity: anim1,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(
                  CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
                ),
            child: Dialog(
              backgroundColor: cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 24.0,
                      bottom: 16.0,
                      left: 16.0,
                      right: 16.0,
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Binance',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Please select an action to proceed with your Binance account.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 15,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    color: isDark ? Colors.white10 : Colors.black12,
                    thickness: 1,
                    height: 1,
                  ),
                  IntrinsicHeight(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () async {
                              Navigator.pop(context);
                              setState(() => _selectedTab = 2);
                              try {
                                await launchUrl(
                                  Uri.parse('bnc://app.binance.com/mp/app'),
                                  mode: LaunchMode.externalApplication,
                                );
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Could not open Binance app.',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.only(
                                  bottomLeft: Radius.circular(16),
                                ),
                              ),
                            ),
                            child: const Text(
                              'View Balance',
                              style: TextStyle(
                                color: _accent,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        VerticalDivider(
                          color: isDark ? Colors.white10 : Colors.black12,
                          thickness: 1,
                          width: 1,
                        ),
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              setState(() => _selectedTab = 2);
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.only(
                                  bottomRight: Radius.circular(16),
                                ),
                              ),
                            ),
                            child: const Text(
                              'Withdraw',
                              style: TextStyle(
                                color: _accent,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showInsufficientBalanceDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim1, anim2, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDark ? Colors.white : Colors.black87;
        final cardBg = isDark
            ? const Color(0xFF232323)
            : const Color.fromARGB(255, 240, 240, 240);
        final dividerColor = isDark ? Colors.white10 : Colors.black12;

        return FadeTransition(
          opacity: anim1,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(
                  CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
                ),
            child: Dialog(
              backgroundColor: cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.error_outline_rounded,
                            color: _accent,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Error',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Insufficient balance. Please refresh your account or try switching to a different source (MT5 or Deriv).',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.8),
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: dividerColor),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          ),
                        ),
                      ),
                      child: const Text(
                        'Try again',
                        style: TextStyle(
                          color: _accent,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtleColor = isDark ? Colors.white70 : Colors.black54;
    final cardBg = isDark
        ? const Color.fromARGB(255, 30, 30, 30)
        : const Color.fromARGB(255, 240, 240, 240);
    final keyBg = isDark
        ? const Color.fromARGB(255, 50, 50, 50)
        : const Color.fromARGB(255, 220, 220, 220);

    final usdVal = _usdAmount;
    final kesVal = _kesAmount;
    final isLimitReached = _showLimitError || kesVal >= 250000;
    final canWithdraw =
        (_selectedTab == 2 ? usdVal >= 10 : usdVal >= 5) && kesVal <= 250000;

    final scaffold = Scaffold(
      backgroundColor: isDark ? const Color(0xFF131313) : Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.close, size: 28, color: textColor),
                  ),
                  Text(
                    'Withdraw',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 28),
                ],
              ),

              const SizedBox(height: 24),

              Center(
                child: Text(
                  'From',
                  style: TextStyle(color: subtleColor, fontSize: 14),
                ),
              ),
              const SizedBox(height: 16),

              _buildSegmentedToggle(isDark, cardBg, textColor),

              const SizedBox(height: 24),

              // ── Amount display ───────────────────────────────
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                          begin: 0,
                          end: _isKesInput ? usdVal : kesVal,
                        ),
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        builder: (context, value, child) {
                          return Text(
                            _isKesInput
                                ? value.toStringAsFixed(2)
                                : value.toStringAsFixed(0),
                            style: TextStyle(
                              color: textColor,
                              fontSize: 48,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -1,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          _isKesInput ? 'USD' : 'KES',
                          style: TextStyle(
                            color: subtleColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6.0),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setState(() {
                              _isKesInput = !_isKesInput;
                              _amountStr = '0';
                            });
                          },
                          child: Icon(
                            Icons.import_export_rounded,
                            color: subtleColor,
                            size: 28,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '1 USD = ${_exchangeRate.toStringAsFixed(5)} KES',
                    style: TextStyle(color: subtleColor, fontSize: 14),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isKesInput ? 'KES' : 'USD',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _displayAmount,
                    style: TextStyle(
                      color: subtleColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              Divider(
                color: isDark ? Colors.white24 : Colors.black26,
                thickness: 1,
              ),
              const SizedBox(height: 12),

              Text(
                isLimitReached
                    ? 'Maximum withdrawal amount is 250,000\nKES'
                    : (_selectedTab == 2
                          ? 'Minimum withdraw amount is 10 USD'
                          : 'Available balance is 0.00 USD'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isLimitReached ? Colors.redAccent : textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),

              const Spacer(),

              _buildNumberPad(keyBg, textColor),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canWithdraw
                        ? _accent
                        : const Color(0xFF232323),
                    foregroundColor: canWithdraw
                        ? Colors.white
                        : (isDark ? Colors.white38 : Colors.black38),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  onPressed: canWithdraw
                      ? () {
                          if (_selectedTab == 0 || _selectedTab == 1) {
                            _showInsufficientBalanceDialog();
                          } else {
                            final destination = [
                              'Deriv',
                              'MT5',
                              'Binance',
                            ][_selectedTab];
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Withdrawing \$${usdVal.toStringAsFixed(2)} USD from $destination',
                                ),
                              ),
                            );
                          }
                        }
                      : null,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Spacer(),
                      Text(
                        'Withdraw',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Spacer(),
                      Icon(Icons.chevron_right, size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );

    return PopScope(
      canPop: !_isWithdrawDialogVisible,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isWithdrawDialogVisible) {
          setState(() => _isWithdrawDialogVisible = false);
        }
      },
      child: Stack(
        children: [
          scaffold,
          if (_isWithdrawDialogVisible) ...[
            FadeTransition(
              opacity: ModalRoute.of(context)!.animation!,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(color: Colors.black54),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Material(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 24,
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: _buildWithdrawAccountChoiceOverlay(
                      isDark,
                      textColor,
                      cardBg,
                      subtleColor,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Segmented toggle ──────────────────────────────────────────────────────

  Widget _buildSegmentedToggle(bool isDark, Color cardBg, Color textColor) {
    final labels = ['Deriv', 'MT5', 'Binance'];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF202020),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(labels.length, (i) {
          final isActive = _selectedTab == i;
          return GestureDetector(
            onTap: () {
              if (i == 1 && _selectedTab != 1) {
                _showMT5LinkDialog();
              } else if (i == 2 && _selectedTab != 2) {
                _showBinanceActionDialog();
              } else {
                setState(() => _selectedTab = i);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: isActive ? _accent : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  color: isActive
                      ? Colors.white
                      : (isDark ? Colors.white60 : Colors.black54),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Number pad ────────────────────────────────────────────────────────────

  Widget _buildNumberPad(Color keyBg, Color textColor) {
    const double spacing = 12.0;
    const double keyHeight = 54.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _padRow(
          ['1', '2', '3'],
          const Color(0xFF282828),
          textColor,
          keyHeight,
          spacing,
        ),
        const SizedBox(height: spacing),
        _padRow(
          ['4', '5', '6'],
          const Color(0xFF282828),
          textColor,
          keyHeight,
          spacing,
        ),
        const SizedBox(height: spacing),
        _padRow(
          ['7', '8', '9'],
          const Color(0xFF282828),
          textColor,
          keyHeight,
          spacing,
        ),
        const SizedBox(height: spacing),
        _padRow(
          _isKesInput ? ['0', '⌫'] : ['.', '0', '⌫'],
          const Color(0xFF282828),
          textColor,
          keyHeight,
          spacing,
        ),
      ],
    );
  }

  Widget _padRow(
    List<String> keys,
    Color keyBg,
    Color textColor,
    double keyHeight,
    double spacing,
  ) {
    final List<Widget> children = [];

    for (int i = 0; i < keys.length; i++) {
      final key = keys[i];
      final bool isExpandableCase = keys.length == 2 && key == '0';

      final child = Expanded(
        flex: isExpandableCase ? 2 : 1,
        child: Material(
          color: keyBg,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              if (key == '⌫') {
                _onBackspace();
              } else {
                _onDigit(key);
              }
            },
            child: SizedBox(
              height: keyHeight,
              child: Center(
                child: key == '⌫'
                    ? Icon(Icons.backspace_outlined, color: textColor, size: 20)
                    : Text(
                        key,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ),
          ),
        ),
      );

      children.add(child);
      if (i < keys.length - 1) {
        children.add(SizedBox(width: spacing));
      }
    }

    return Row(children: children);
  }
}

// ── Link New Payment Method Bottom Sheet ──────────────────────────────────────

class _LinkNewMethodSheet extends StatefulWidget {
  final bool hasMobileMoney;
  final bool hasBank;
  final bool isDark;
  final VoidCallback onLinked;

  const _LinkNewMethodSheet({
    required this.hasMobileMoney,
    required this.hasBank,
    required this.isDark,
    required this.onLinked,
  });

  @override
  State<_LinkNewMethodSheet> createState() => _LinkNewMethodSheetState();
}

class _LinkNewMethodSheetState extends State<_LinkNewMethodSheet> {
  // 'choose' | 'mobile_form' | 'otp_verify' | 'bank_form'
  String _step = 'choose';
  String _selectedType = '';

  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  final _accountNameCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  static const _accent = Color.fromARGB(255, 55, 194, 21);

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

  // ── Step: choose type ────────────────────────────────────────────────────

  Widget _buildChooseStep() {
    final options = <Map<String, dynamic>>[];
    if (!widget.hasMobileMoney) {
      options.add({
        'type': 'mpesa',
        'label': 'M-PESA',
        'icon': Icons.phone_android,
        'color': Colors.green.shade700,
      });
      options.add({
        'type': 'airtel',
        'label': 'Airtel Money',
        'icon': Icons.phone_android,
        'color': Colors.red.shade700,
      });
    }
    if (!widget.hasBank) {
      options.add({
        'type': 'bank',
        'label': 'Bank Account',
        'icon': Icons.account_balance,
        'color': Colors.blue.shade700,
      });
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sheetHeader('Link New Account'),
        if (options.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'All available payment types are already linked.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _subtleColor, fontSize: 14),
              ),
            ),
          )
        else
          ...options.map((opt) {
            final color = opt['color'] as Color;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedType = opt['type'] as String;
                  _error = null;
                  _step = _selectedType == 'bank' ? 'bank_form' : 'mobile_form';
                });
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: _fieldBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        opt['icon'] as IconData,
                        color: color,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      opt['label'] as String,
                      style: TextStyle(
                        color: _textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.chevron_right, color: _subtleColor, size: 20),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  // ── Step: mobile phone input ─────────────────────────────────────────────

  Widget _buildMobileFormStep() {
    final label = _selectedType == 'mpesa' ? 'M-PESA' : 'Airtel Money';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sheetHeader(
          'Link $label',
          onBack: () => setState(() => _step = 'choose'),
        ),
        Text(
          'Enter the phone number to link. An OTP will be sent to verify you own it.',
          style: TextStyle(color: _subtleColor, fontSize: 13),
        ),
        const SizedBox(height: 16),
        _styledField(
          controller: _phoneCtrl,
          hint: '07XXXXXXXXXX',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              elevation: 0,
            ),
            onPressed: _loading ? null : _onMobileNext,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Send OTP',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
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
    return digits; // already E.164 or unexpected format
  }

  Future<void> _onMobileNext() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty || phone.length < 10) {
      setState(
        () =>
            _error = 'Please enter a valid 10-digit number (e.g. 0712345678).',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    // Both M-Pesa and Airtel require OTP to verify phone ownership
    final sent = await ApiService.sendOtp(
      destination: _toE164(phone),
      type: 'sms',
      purpose: 'withdrawal',
    );
    if (!mounted) return;
    if (sent) {
      setState(() {
        _loading = false;
        _step = 'otp_verify';
      });
    } else {
      setState(() {
        _loading = false;
        _error = 'Could not send OTP. Check the number and try again.';
      });
    }
  }

  // ── Step: OTP verification (M-Pesa only) ────────────────────────────────

  Widget _buildOtpVerifyStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sheetHeader(
          'Verify Number',
          onBack: () => setState(() => _step = 'mobile_form'),
        ),
        Text(
          'Enter the OTP sent to ${_phoneCtrl.text.trim()}.',
          style: TextStyle(color: _subtleColor, fontSize: 13),
        ),
        const SizedBox(height: 16),
        _styledField(
          controller: _otpCtrl,
          hint: '6-digit code',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              elevation: 0,
            ),
            onPressed: _loading ? null : _onOtpVerify,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Verify & Link',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _loading ? null : _resendOtp,
            child: Text(
              'Resend OTP',
              style: TextStyle(color: _subtleColor, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onOtpVerify() async {
    final otp = _otpCtrl.text.trim();
    if (otp.isEmpty) {
      setState(() => _error = 'Please enter the OTP.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

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

    // OTP verified — now save the mobile money account
    final err = await ApiService.addPaymentMethod(
      type: _selectedType,
      phoneNumber: _toE164(_phoneCtrl.text.trim()),
    );
    if (!mounted) return;
    if (err == null) {
      widget.onLinked();
    } else {
      setState(() {
        _loading = false;
        _error = err;
      });
    }
  }

  Future<void> _resendOtp() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final sent = await ApiService.sendOtp(
      destination: _toE164(_phoneCtrl.text.trim()),
      type: 'sms',
      purpose: 'withdrawal',
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = sent ? null : 'Could not resend OTP. Try again.';
    });
    if (sent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP resent.'), backgroundColor: _accent),
      );
    }
  }

  // ── Step: bank account form ──────────────────────────────────────────────

  Widget _buildBankFormStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sheetHeader(
          'Link Bank Account',
          onBack: () => setState(() => _step = 'choose'),
        ),
        _styledField(
          controller: _bankNameCtrl,
          hint: 'Bank name (e.g. Equity)',
        ),
        const SizedBox(height: 12),
        _styledField(controller: _accountNameCtrl, hint: 'Account holder name'),
        const SizedBox(height: 12),
        _styledField(
          controller: _accountNumberCtrl,
          hint: 'Account number',
          keyboardType: TextInputType.number,
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              elevation: 0,
            ),
            onPressed: _loading ? null : _onBankSave,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Save Bank Account',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _onBankSave() async {
    final bankName = _bankNameCtrl.text.trim();
    final accountName = _accountNameCtrl.text.trim();
    final accountNumber = _accountNumberCtrl.text.trim();

    if (bankName.isEmpty || accountName.isEmpty || accountNumber.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    final err = await ApiService.addPaymentMethod(
      type: 'bank',
      bankName: bankName,
      accountName: accountName,
      accountNumber: accountNumber,
    );
    if (!mounted) return;
    if (err == null) {
      widget.onLinked();
    } else {
      setState(() {
        _loading = false;
        _error = err;
      });
    }
  }

  // ── Shared helpers ───────────────────────────────────────────────────────

  Widget _sheetHeader(String title, {VoidCallback? onBack}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          if (onBack != null) ...[
            GestureDetector(
              onTap: onBack,
              child: Icon(
                Icons.arrow_back_ios_new,
                size: 18,
                color: _textColor,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            title,
            style: TextStyle(
              color: _textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _styledField({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(
          key: ValueKey(_step),
          child: switch (_step) {
            'mobile_form' => _buildMobileFormStep(),
            'otp_verify' => _buildOtpVerifyStep(),
            'bank_form' => _buildBankFormStep(),
            _ => _buildChooseStep(),
          },
        ),
      ),
    );
  }
}
