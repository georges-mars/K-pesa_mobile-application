import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class DepositPage extends StatefulWidget {
  const DepositPage({super.key});

  @override
  State<DepositPage> createState() => _DepositPageState();
}

class _DepositPageState extends State<DepositPage> {
  // 0 = Deriv, 1 = MT5, 2 = Binance
  int _selectedTab = 0;
  String _amountStr = '0';
  bool _isKesInput = true;
  bool _showLimitError = false;
  bool _isInitiating = false;
  bool _loadingMethods = true;
  List<Map<String, dynamic>> _paymentMethods = [];
  String? _selectedMethodId;
  double _minDepositUsd = 5;
  bool _hasDerivLinked = false;
  bool _hasBinanceLinked = false;
  bool _hasMt5Account = false;

  static const _accent = Color.fromARGB(255, 55, 194, 21);
  static const double _exchangeRate = 133.77375;

  @override
  void initState() {
    super.initState();
    _fetchPaymentMethods();
    _fetchAppConfig();
    _fetchLinkedDestinations();
  }

  String get _selectedDestinationType =>
      ['deriv', 'mt5', 'binance'][_selectedTab];

  String get _selectedDestinationLabel =>
      ['Deriv', 'MT5', 'Binance'][_selectedTab];

  bool _isDestinationEnabled(int index) {
    // If neither Deriv nor Binance is linked, allow attempt (may still succeed)
    final anyLinked = _hasDerivLinked || _hasBinanceLinked;
    if (!anyLinked) return true;
    
    if (index == 0) return _hasDerivLinked; // Deriv
    if (index == 1) return _hasDerivLinked; // MT5 depends on Deriv linkage
    return _hasBinanceLinked; // Binance
  }

  int _firstEnabledDestinationIndex() {
    for (var i = 0; i < 3; i++) {
      if (_isDestinationEnabled(i)) return i;
    }
    return 0;
  }

  Future<void> _fetchLinkedDestinations() async {
    final results = await Future.wait([
      ApiService.getProfile(),
      ApiService.getBalances(),
    ]);
    if (!mounted) return;
    final profile = results[0];
    final balances = results[1];
    if (profile == null && balances == null) return;

    final derivAccount = (profile?['deriv_account'] as String?)?.trim() ?? '';
    final derivEmail = (profile?['deriv_email'] as String?)?.trim() ?? '';
    final derivName = (profile?['deriv_name'] as String?)?.trim() ?? '';
    final binanceId = (profile?['binance_id'] as String?)?.trim() ?? '';
    final derivBalance = balances?['deriv'];
    final mt5Accounts = balances?['mt5Accounts'] as List<dynamic>? ?? const [];

    setState(() {
      _hasDerivLinked =
          derivAccount.isNotEmpty ||
          derivEmail.isNotEmpty ||
          derivName.isNotEmpty ||
          derivBalance != null;
      _hasBinanceLinked = binanceId.isNotEmpty;
      _hasMt5Account = mt5Accounts.isNotEmpty;
      if (!_isDestinationEnabled(_selectedTab)) {
        _selectedTab = _firstEnabledDestinationIndex();
      }
    });
  }

  Future<void> _fetchAppConfig() async {
    final balances = await ApiService.getBalances();
    if (!mounted || balances == null) return;
    final appConfig = balances['appConfig'] as Map<String, dynamic>?;
    final minDeposit = appConfig?['minDepositUsd'];
    final parsed = minDeposit is num
        ? minDeposit.toDouble()
        : double.tryParse(minDeposit?.toString() ?? '');
    if (parsed == null || parsed <= 0) return;
    setState(() => _minDepositUsd = parsed);
  }

  Future<void> _fetchPaymentMethods() async {
    final methods = await ApiService.getPaymentMethods();
    if (!mounted) return;

    final mobileMethods = methods.where((m) {
      final type = m['type'] as String?;
      final phone = (m['phone_number'] as String?)?.trim() ?? '';
      return (type == 'mpesa' || type == 'airtel') && phone.isNotEmpty;
    }).toList();

    String? selectedMethodId = _selectedMethodId;
    if (selectedMethodId == null ||
        mobileMethods.every((m) => m['id'] != selectedMethodId)) {
      if (mobileMethods.isNotEmpty) {
        final defaultMethod = mobileMethods.firstWhere(
          (m) => m['is_default'] == true,
          orElse: () => mobileMethods.first,
        );
        selectedMethodId = defaultMethod['id'] as String?;
      } else {
        selectedMethodId = null;
      }
    }

    setState(() {
      _paymentMethods = methods;
      _selectedMethodId = selectedMethodId;
      _loadingMethods = false;
    });
  }

  List<Map<String, dynamic>> get _mobileMethods {
    return _paymentMethods
        .where((m) {
          final type = m['type'] as String?;
          final phone = (m['phone_number'] as String?)?.trim() ?? '';
          return (type == 'mpesa' || type == 'airtel') && phone.isNotEmpty;
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> get _bankMethods {
    return _paymentMethods
        .where((m) => m['type'] == 'bank')
        .toList(growable: false);
  }

  Map<String, dynamic>? get _selectedMethod {
    final selectedMethodId = _selectedMethodId;
    if (selectedMethodId == null) return null;
    for (final method in _mobileMethods) {
      if (method['id'] == selectedMethodId) return method;
    }
    return null;
  }

  String? get _selectedMobilePhone {
    final selected = _selectedMethod;
    if (selected == null) return null;
    final phone = (selected['phone_number'] as String?)?.trim();
    if (phone == null || phone.isEmpty) return null;
    return phone;
  }

  Future<void> _initiateDeposit() async {
    if (_isInitiating) return;
    if (!_isDestinationEnabled(_selectedTab)) return;
    final selectedMethod = _selectedMethod;
    final selectedPhone = _selectedMobilePhone;
    if (selectedMethod == null || selectedPhone == null) return;

    setState(() => _isInitiating = true);
    final destinationType = _selectedDestinationType;
    final result = await ApiService.initiateDeposit(
      amountKes: _kesAmount,
      destinationType: destinationType,
      mpesaPhone: selectedPhone,
    );
    if (!mounted) return;
    setState(() => _isInitiating = false);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not initiate deposit. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _showProcessingSheet(
      result['transactionId'] as String? ?? '',
      _kesAmount,
      selectedPhone,
      destinationType,
    );
  }

  void _showProcessingSheet(String initialTransactionId, double amountKes, String mpesaPhone, String dest) {
    final pageNavigator = Navigator.of(context);
    String transactionId = initialTransactionId;
    Timer? timer;
    int elapsedSeconds = 0;
    String status = 'processing';
    String failureReason = '';
    bool isRetrying = false;

    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
            final textColor = isDark ? Colors.white : Colors.black87;
            final subtle = isDark ? Colors.white60 : Colors.black45;

            // Start polling if status is processing and timer hasn't been set
            if (timer == null && status == 'processing') {
              timer = Timer.periodic(const Duration(seconds: 1), (t) async {
                elapsedSeconds += 1;
                
                // Trigger UI update for elapsed timeout counter
                if (ctx.mounted) {
                  setSheetState(() {});
                }

                if (elapsedSeconds >= 25) {
                  t.cancel();
                  if (ctx.mounted) {
                    setSheetState(() {
                      status = 'timeout';
                      failureReason = 'Payment prompt expired. Please make sure your phone is unlocked and try again.';
                    });
                  }
                  return;
                }

                // Poll status every 3 seconds
                if (elapsedSeconds % 3 == 0) {
                  try {
                    final res = await ApiService.getDepositStatus(transactionId);
                    if (res != null && ctx.mounted) {
                      final newStatus = res['status'] as String? ?? 'processing';
                      final reason = res['failure_reason'] as String? ?? '';
                      if (newStatus == 'completed') {
                        t.cancel();
                        setSheetState(() {
                          status = 'completed';
                        });
                        
                        final sheetNavigator = Navigator.of(ctx);
                        Future.delayed(const Duration(seconds: 2), () {
                          if (ctx.mounted) {
                            sheetNavigator.pop(); // Close sheet
                            if (mounted) {
                              pageNavigator.pop(); // Close DepositPage and return to dashboard
                            }
                          }
                        });
                      } else if (newStatus == 'failed' || newStatus == 'cancelled') {
                        t.cancel();
                        setSheetState(() {
                          status = newStatus;
                          failureReason = reason.isNotEmpty 
                              ? reason 
                              : 'M-Pesa payment failed. Please try again.';
                        });
                      }
                    }
                  } catch (_) {}
                }
              });
            }

            Future<void> retrySTK() async {
              if (isRetrying) return;
              setSheetState(() {
                isRetrying = true;
                status = 'processing';
                failureReason = '';
                elapsedSeconds = 0;
              });

              try {
                final res = await ApiService.initiateDeposit(
                  amountKes: amountKes,
                  destinationType: dest,
                  mpesaPhone: mpesaPhone,
                );

                if (!ctx.mounted) return;

                if (res != null) {
                  final newTxId = res['transactionId'] as String? ?? '';
                  setSheetState(() {
                    transactionId = newTxId;
                    isRetrying = false;
                    timer = null; // Let next tick rebuild and recreate timer
                  });
                } else {
                  setSheetState(() {
                    status = 'failed';
                    failureReason = 'Could not re-initiate STK Push. Please check your connection.';
                    isRetrying = false;
                  });
                }
              } catch (e) {
                if (ctx.mounted) {
                  setSheetState(() {
                    status = 'failed';
                    failureReason = 'Error: $e';
                    isRetrying = false;
                  });
                }
              }
            }

            Widget modalContent;
            if (status == 'processing') {
              modalContent = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  const SizedBox(
                    width: 60,
                    height: 60,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Confirming Payment...',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'An M-Pesa prompt has been sent to $mpesaPhone.\nPlease check your phone, enter your PIN and wait here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: subtle,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'KES ${amountKes.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Timeout in ${25 - elapsedSeconds}s',
                    style: TextStyle(
                      color: subtle.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              );
            } else if (status == 'completed') {
              modalContent = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: _accent,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Deposit Successful!',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'KES ${amountKes.toStringAsFixed(0)} has been deposited successfully to ${dest.toUpperCase()}.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: subtle,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            } else {
              modalContent = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.error_rounded,
                      color: Colors.red,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    status == 'timeout' ? 'Prompt Expired' : 'Payment Failed',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      failureReason,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: subtle,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            timer?.cancel();
                            Navigator.pop(ctx);
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: subtle.withValues(alpha: 0.3)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(
                            'Close',
                            style: TextStyle(color: textColor),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isRetrying ? null : retrySTK,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                          ),
                          child: Text(
                            isRetrying ? 'Retrying...' : 'Retry Push',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }

            return Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: subtle.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  modalContent,
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      timer?.cancel();
    });
  }

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

      // Check if new value exceeds 250,000 KES
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

      // Reset error if we are now under the limit
      final parsed = double.tryParse(_amountStr) ?? 0;
      final kesVal = _isKesInput ? parsed : (parsed * _exchangeRate);
      if (kesVal < 250000) {
        _showLimitError = false;
      }
    });
  }

  void _showDepositDialog() {
    final mobileMethods = _mobileMethods;
    final bankMethods = _bankMethods;

    String? selectedMethodId = _selectedMethodId;
    if (selectedMethodId != null &&
        mobileMethods.every((m) => m['id'] != selectedMethodId)) {
      selectedMethodId = null;
    }
    if (selectedMethodId == null && mobileMethods.isNotEmpty) {
      final defaultMethod = mobileMethods.firstWhere(
        (m) => m['is_default'] == true,
        orElse: () => mobileMethods.first,
      );
      selectedMethodId = defaultMethod['id'] as String?;
    }

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
        final subtleColor = isDark ? Colors.white70 : Colors.black54;

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
              child: StatefulBuilder(
                builder: (BuildContext context, StateSetter dialogSetState) {
                  final canProceed =
                      mobileMethods.isNotEmpty && selectedMethodId != null;

                  return Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
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
                        const SizedBox(height: 12),
                        Text(
                          'Select the registered number to use for this $_selectedDestinationLabel deposit.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),

                        if (_loadingMethods)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: CircularProgressIndicator(color: _accent),
                          )
                        else if (mobileMethods.isNotEmpty)
                          ...mobileMethods.map(
                            (method) => _buildDepositMethodTile(
                              method: method,
                              isDark: isDark,
                              textColor: textColor,
                              subtleColor: subtleColor,
                              isSelected: selectedMethodId == method['id'],
                              onTap: () {
                                dialogSetState(() {
                                  selectedMethodId = method['id'] as String?;
                                });
                              },
                            ),
                          )
                        else if (bankMethods.isNotEmpty) ...[
                          Text(
                            'No mobile money number found. Showing your registered bank account:',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: subtleColor, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          ...bankMethods.map(
                            (method) => _buildBankSummaryTile(
                              method: method,
                              isDark: isDark,
                              textColor: textColor,
                              subtleColor: subtleColor,
                            ),
                          ),
                        ] else
                          Text(
                            'No payment method found. Link M-Pesa, Airtel, or bank in Payment Providers.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: subtleColor, fontSize: 13),
                          ),

                        const SizedBox(height: 32),

                        // Proceed Button
                        TextButton(
                          onPressed: canProceed
                              ? () {
                                  setState(
                                    () => _selectedMethodId = selectedMethodId,
                                  );
                                  Navigator.pop(context);
                                  _initiateDeposit();
                                }
                              : null,
                          child: Text(
                            'Proceed',
                            style: TextStyle(
                              color: canProceed
                                  ? _accent
                                  : Colors.white38, // Dimmed as in screenshot
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Cancel Deposit Button
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'Cancel Deposit',
                            style: TextStyle(
                              color: _accent, // K-Pesa Green
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDepositMethodTile({
    required Map<String, dynamic> method,
    required bool isDark,
    required Color textColor,
    required Color subtleColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final type = method['type'] as String? ?? '';
    final phone = (method['phone_number'] as String?)?.trim() ?? '';

    final typeLabel = type == 'airtel' ? 'Airtel Money' : 'M-PESA';
    final badgeLabel = type == 'airtel' ? 'AIRTEL' : 'M-PESA';
    final badgeColor = type == 'airtel' ? Colors.red.shade700 : _accent;

    return GestureDetector(
      onTap: onTap,
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                badgeLabel,
                style: TextStyle(
                  color: badgeColor,
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
                  if (phone.isNotEmpty)
                    Text(
                      phone,
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
                  color: isSelected ? _accent : subtleColor,
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

  Widget _buildBankSummaryTile({
    required Map<String, dynamic> method,
    required bool isDark,
    required Color textColor,
    required Color subtleColor,
  }) {
    final bankName = (method['bank_name'] as String?)?.trim() ?? 'Bank';
    final accountName = (method['account_name'] as String?)?.trim() ?? '';
    final accountNumber = (method['account_number'] as String?)?.trim() ?? '';
    final details = [
      accountName,
      accountNumber,
    ].where((v) => v.isNotEmpty).join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'BANK',
              style: TextStyle(
                color: Colors.blue,
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
                  bankName,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (details.isNotEmpty)
                  Text(
                    details,
                    style: TextStyle(color: subtleColor, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
                          'Please select the MT5 account that you wish to link to your K-Pesa account',
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

                  // Divider line above buttons
                  Divider(
                    color: isDark ? Colors.white10 : Colors.black12,
                    thickness: 1,
                    height: 1,
                  ),

                  // Bottom Buttons Row
                  IntrinsicHeight(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              // TODO: Implement actual select linking
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
                                color: _accent, // K-Pesa Green
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
                              // Revert selection if user declines
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
                                color: _accent, // K-Pesa Green
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
    final canDeposit =
        _isDestinationEnabled(_selectedTab) &&
        usdVal >= _minDepositUsd &&
        kesVal <= 250000;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF131313) : Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
              // ── Header ────────────────────────────────────
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.close, size: 28, color: textColor),
                  ),
                  Text(
                    'Deposit',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 28), // For balance
                ],
              ),

              const SizedBox(height: 24), // Replaced 48 with 24 to fix overflow
              // ── "To" section ────────────────────────────────
              Center(
                child: Text(
                  'To',
                  style: TextStyle(color: subtleColor, fontSize: 14),
                ),
              ),
              const SizedBox(height: 16),

              // ── Segmented toggle ──────────────────────────
              _buildSegmentedToggle(isDark, cardBg, textColor),
              const SizedBox(height: 8),
              Text(
                'Only linked destinations are active.',
                style: TextStyle(color: subtleColor, fontSize: 12),
              ),

              const SizedBox(height: 24),

              // ── Amount display (Converted USD) ────────────
              Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
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
                ],
              ),

              const SizedBox(height: 24),

              // ── Input Amount (centered with divider) ─────────
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

              // ── Minimum/Maximum deposit note ───────────────────────
              Text(
                isLimitReached
                    ? 'Maximum deposit amount is 250,000\nKES'
                    : 'Minimum deposit amount is ${_minDepositUsd.toStringAsFixed(_minDepositUsd % 1 == 0 ? 0 : 2)} USD',
                style: TextStyle(
                  color: isLimitReached ? Colors.redAccent : textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),

              // ── Number pad ─────────────────────────────────
              _buildNumberPad(keyBg, textColor),

              const SizedBox(height: 24),

              // ── Deposit button ─────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canDeposit
                        ? _accent
                        : const Color(0xFF232323),
                    foregroundColor: canDeposit
                        ? Colors.white
                        : (isDark ? Colors.white38 : Colors.black38),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  onPressed: canDeposit
                      ? () {
                          _showDepositDialog();
                        }
                      : null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Spacer(),
                      Text(
                        'Deposit',
                        style: TextStyle(
                          color: canDeposit ? Colors.white : Colors.white24,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right,
                        color: canDeposit ? Colors.white : Colors.white24,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ));
          },
        ),
      ),
    );
  }

  // ── Segmented toggle widget ────────────────────────────────────────────────

  Widget _buildSegmentedToggle(bool isDark, Color cardBg, Color textColor) {
    final labels = ['Deriv', 'MT5', 'Binance'];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF202020),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: List.generate(labels.length, (i) {
          final isActive = _selectedTab == i;
          final isEnabled = _isDestinationEnabled(i);
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (!isEnabled) return;
                if (i == 1 && _selectedTab != 1) {
                  if (_hasMt5Account) {
                    setState(() => _selectedTab = i);
                  } else {
                    _showMT5LinkDialog();
                  }
                } else {
                  setState(() => _selectedTab = i);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isActive ? _accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isActive
                          ? Colors.white
                          : isEnabled
                          ? (isDark ? Colors.white60 : Colors.black54)
                          : (isDark ? Colors.white30 : Colors.black26),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Number pad widget ─────────────────────────────────────────────────────

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
            splashColor: _accent.withValues(alpha: 0.2),
            highlightColor: _accent.withValues(alpha: 0.1),
            child: Container(
              height: keyHeight,
              alignment: Alignment.center,
              child: key == '⌫'
                  ? Icon(Icons.backspace_outlined, color: textColor, size: 24)
                  : Text(
                      key,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
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
