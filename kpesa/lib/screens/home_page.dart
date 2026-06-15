import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import 'deposit_page.dart';
import 'withdraw_page.dart';
import 'profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late AnimationController _animationController;
  Timer? _refreshTimer;

  String _userName = '';
  String _derivBalance = '—';
  List<Map<String, dynamic>> _mt5Accounts = [];
  List<Map<String, dynamic>> _transactions = [];
  bool _loadingTx = true;

  num? _toNum(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    return num.tryParse(value.toString().replaceAll(',', '').trim());
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
    _fetchData();

    // Poll balances every 30 seconds for live updates
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshBalances(),
    );
  }

  Future<void> _fetchData() async {
    final results = await Future.wait([
      ApiService.getProfile(),
      ApiService.getBalances(),
      ApiService.getTransactions(),
    ]);

    if (!mounted) return;

    final profile = results[0] as Map<String, dynamic>?;
    final balances = results[1] as Map<String, dynamic>?;
    final txList = results[2] as List<dynamic>;

    String resolvedName = '';
    if (profile != null) {
      // Priority: deriv_name (Deriv linked) → display_name (set via popup)
      // full_name from registration is intentionally ignored.
      final derivName = profile['deriv_name'] as String?;
      final displayName = profile['display_name'] as String?;
      resolvedName =
          (derivName?.isNotEmpty == true ? derivName : displayName) ?? '';
    }

    setState(() {
      _userName = resolvedName;
      _applyBalances(balances);
      _transactions = txList
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _loadingTx = false;
    });

    // No name found — prompt the user to set one
    if (resolvedName.isEmpty && mounted) {
      _showNamePrompt();
    }
  }

  /// Refresh only balances (called by timer and after deposit/withdraw)
  Future<void> _refreshBalances() async {
    final balances = await ApiService.getBalances();
    if (!mounted) return;
    setState(() => _applyBalances(balances));
  }

  /// Refresh balances AND transactions (after returning from deposit/withdraw)
  Future<void> _refreshAll() async {
    final results = await Future.wait([
      ApiService.getBalances(),
      ApiService.getTransactions(),
    ]);
    if (!mounted) return;
    setState(() {
      _applyBalances(results[0] as Map<String, dynamic>?);
      _transactions = (results[1] as List<dynamic>)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    });
  }

  void _applyBalances(Map<String, dynamic>? balances) {
    if (balances == null) return;
    final deriv = balances['deriv'] as Map<String, dynamic>?;
    final mt5List = balances['mt5Accounts'] as List<dynamic>?;
    final derivAmt = _toNum(deriv?['balance']);
    _derivBalance = derivAmt != null
        ? '${derivAmt.toStringAsFixed(2)} ${deriv?['currency'] ?? 'USD'}'
        : '0.00 USD';
    _mt5Accounts =
        mt5List
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];
  }

  void _showNamePrompt() {
    final controller = TextEditingController();
    bool isSaving = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
          final text = isDark ? Colors.white : Colors.black87;
          final subtle = isDark ? Colors.white60 : Colors.black45;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
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
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: subtle.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: _accentColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.waving_hand_rounded,
                      color: _accentColor,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'What should we call you?',
                    style: TextStyle(
                      color: text,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "This is how we'll greet you on the home screen.",
                    style: TextStyle(color: subtle, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  TextField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    style: TextStyle(color: text, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'e.g. John Doe',
                      hintStyle: TextStyle(color: subtle),
                      prefixIcon: Icon(
                        Icons.person_outline,
                        color: _accentColor,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.04),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: _accentColor, width: 1.5),
                      ),
                    ),
                    onChanged: (_) => setSheetState(() {}),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: (controller.text.trim().isEmpty || isSaving)
                          ? null
                          : () async {
                              setSheetState(() => isSaving = true);
                              final name = controller.text.trim();
                              final err = await ApiService.updateDisplayName(
                                name,
                              );
                              if (!ctx.mounted) return;
                              Navigator.of(ctx).pop();
                              if (err == null && mounted) {
                                setState(
                                  () => _userName = name.split(' ').first,
                                );
                              }
                            },
                      child: isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Save',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  Color get _accentColor => const Color.fromARGB(255, 55, 194, 21);

  // ── Navigation helpers (refresh data on return) ─────────────────────────────

  Future<void> _openProfile() async {
    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const ProfilePage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          final curve = Curves.easeOutQuart;
          final tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
    if (mounted) _refreshAll();
  }

  Future<void> _openDeposit() async {
    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const DepositPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          final curve = Curves.easeOutBack;
          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: animation.drive(tween),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
    // Refresh balances + transactions when returning
    if (mounted) _refreshAll();
  }

  Future<void> _openWithdraw() async {
    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const WithdrawPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          final curve = Curves.easeOutBack;
          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: animation.drive(tween),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
    if (mounted) _refreshAll();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtleColor = isDark ? Colors.white70 : Colors.black54;
    final cardBgColor = isDark
        ? const Color.fromARGB(255, 40, 40, 40)
        : const Color.fromARGB(255, 245, 245, 245);

    return Scaffold(
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -350) {
            _openProfile();
          }
        },
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(textColor),
                  const SizedBox(height: 32),
                  _buildBalanceCard(isDark),
                  const SizedBox(height: 24),
                  _buildActionButtons(isDark),
                  const SizedBox(height: 32),
                  _buildTransactionsSection(
                    cardBgColor,
                    textColor,
                    subtleColor,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Color textColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome Back,',
              style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              _userName.isEmpty ? '...' : _userName,
              style: TextStyle(
                color: textColor,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        GestureDetector(
          onTap: _openProfile,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 100, 100, 100),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.account_circle_outlined,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceCard(bool isDark) {
    return Column(
      children: [
        // ── Deriv Balance Card ────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_accentColor, _accentColor.withValues(alpha: 0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: _accentColor.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Deriv Balance',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Live',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _derivBalance,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1,
                ),
              ),
              // ── MT5 Live Accounts ─────────────────────────────────────────────
              if (_mt5Accounts.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(color: Colors.white24, height: 1),
                const SizedBox(height: 12),
                const Text(
                  'MT5 Live Accounts',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                ..._mt5Accounts.map((acct) {
                  final login = acct['login']?.toString() ?? '—';
                  final bal = _toNum(acct['balance']) ?? 0;
                  final cur = acct['currency'] as String? ?? 'USD';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          login,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                        Text(
                          '${bal.toStringAsFixed(2)} $cur',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Binance Balance Card (with deep link button) ──────────────────────
        InkWell(
          onTap: () async {
            try {
              final uri = Uri.parse('bnc://app.binance.com/mp/app');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not open Binance app')),
              );
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2B2B2B) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black12,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3BA2F).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/binance.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Binance Balance',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap to open Binance app',
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: isDark ? Colors.white38 : Colors.black38,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentColor,
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            onPressed: _openDeposit,
            child: const Text(
              'Deposit',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              side: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            onPressed: _openWithdraw,
            child: Text(
              'Withdraw',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionsSection(
    Color cardBgColor,
    Color textColor,
    Color subtleColor,
  ) {
    return Container(
      height: 400, // Fixed height for transactions section
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transactions',
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loadingTx
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _transactions.isEmpty
                ? _buildEmptyTransactions(subtleColor)
                : _buildTransactionList(textColor, subtleColor),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTransactions(Color subtleColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedMoneyWidget(animationController: _animationController),
          const SizedBox(height: 32),
          Text(
            'No Transactions',
            style: TextStyle(
              color: subtleColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionList(Color textColor, Color subtleColor) {
    return ListView.separated(
      itemCount: _transactions.length,
      separatorBuilder: (_, _) =>
          Divider(color: subtleColor.withValues(alpha: 0.15), height: 1),
      itemBuilder: (context, index) {
        final tx = _transactions[index];
        final type = tx['type'] as String? ?? '';
        final status = tx['status'] as String? ?? '';
        final amountUsd = _toNum(tx['amount_usd']);
        final amountKes = _toNum(tx['amount_kes']);
        final createdAt = tx['created_at'] as String?;
        final dest = tx['destination_type'] as String? ?? '';
        final isDeposit = type == 'deposit';

        // Format time
        String timeStr = '';
        if (createdAt != null) {
          try {
            final dt = DateTime.parse(createdAt).toLocal();
            timeStr = DateFormat('MMM d, h:mm a').format(dt);
          } catch (_) {}
        }

        // Status color
        Color statusColor;
        switch (status) {
          case 'completed':
            statusColor = _accentColor;
          case 'failed':
            statusColor = Colors.red;
          default:
            statusColor = Colors.orange;
        }

        return InkWell(
          onTap: () => _showTransactionDetails(tx),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (isDeposit ? _accentColor : Colors.orange).withValues(
                      alpha: 0.12,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isDeposit
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    color: isDeposit ? _accentColor : Colors.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isDeposit
                            ? 'Deposit to ${dest.isNotEmpty ? dest : 'Deriv'}'
                            : 'Withdrawal to M-Pesa',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        timeStr,
                        style: TextStyle(color: subtleColor, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // Amount + status
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      amountUsd != null
                          ? '\$${amountUsd.toStringAsFixed(2)}'
                          : 'KES ${amountKes?.toStringAsFixed(0) ?? '—'}',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTransactionDetails(Map<String, dynamic> initialTx) {
    Map<String, dynamic> tx = Map<String, dynamic>.from(initialTx);
    bool isSyncing = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
            final textColor = isDark ? Colors.white : Colors.black87;
            final subtle = isDark ? Colors.white60 : Colors.black45;

            final type = tx['type'] as String? ?? '';
            final status = tx['status'] as String? ?? '';
            final amountUsd = _toNum(tx['amount_usd']);
            final amountKes = _toNum(tx['amount_kes']);
            final rate = _toNum(tx['exchange_rate']);
            final createdAt = tx['created_at'] as String?;
            final dest = tx['destination_type'] as String? ?? '';
            final failureReason = tx['failure_reason'] as String? ?? '';
            final mpesaPhone = tx['mpesa_phone'] as String? ?? '';
            final mpesaTxnId = tx['mpesa_transaction_id'] as String? ?? '';
            final isDeposit = type == 'deposit';

            // Format time
            String timeStr = '';
            if (createdAt != null) {
              try {
                final dt = DateTime.parse(createdAt).toLocal();
                timeStr = DateFormat('MMMM d, yyyy h:mm a').format(dt);
              } catch (_) {}
            }

            // Status design
            Color statusColor;
            IconData statusIcon;
            String statusText = status.toUpperCase();
            switch (status) {
              case 'completed':
                statusColor = _accentColor;
                statusIcon = Icons.check_circle_rounded;
                break;
              case 'failed':
                statusColor = Colors.red;
                statusIcon = Icons.error_rounded;
                break;
              case 'cancelled':
                statusColor = Colors.redAccent;
                statusIcon = Icons.cancel_rounded;
                break;
              default:
                statusColor = Colors.orange;
                statusIcon = Icons.pending_rounded;
                statusText = 'PENDING';
                break;
            }

            final isPendingOrProcessing = ['pending', 'processing'].contains(status);

            Future<void> checkStatus() async {
              if (isSyncing) return;
              setSheetState(() {
                isSyncing = true;
              });
              try {
                final result = await ApiService.getDepositStatus(tx['id']);
                if (result != null) {
                  setSheetState(() {
                    tx = result;
                  });
                  _fetchData();
                }
              } catch (_) {}
              if (ctx.mounted && mounted) {
                setSheetState(() {
                  isSyncing = false;
                });
              }
            }

            Future<void> retrySTKPush() async {
              Navigator.pop(ctx); // Close details sheet first

              final navigator = Navigator.of(context);
              final scaffoldMessenger = ScaffoldMessenger.of(context);

              // Show a loading dialog
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (BuildContext context) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                },
              );

              try {
                final res = await ApiService.initiateDeposit(
                  amountKes: amountKes?.toDouble() ?? 0.0,
                  destinationType: dest,
                  mpesaPhone: mpesaPhone,
                );

                if (!mounted) return;
                navigator.pop(); // Dismiss loading dialog

                if (res != null) {
                  final msg = res['message'] ?? 'STK Push initiated successfully.';
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text(msg),
                      backgroundColor: _accentColor,
                    ),
                  );
                  _fetchData(); // Reload transactions
                } else {
                  if (mounted) {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Failed to Retry'),
                        content: const Text('Could not re-initiate STK Push. Please try again manually.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  }
                }
              } catch (e) {
                if (mounted) {
                  navigator.pop(); // Dismiss loading dialog
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Error'),
                      content: Text('An error occurred: $e'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: subtle.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Transaction Details',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isPendingOrProcessing)
                          IconButton(
                            icon: isSyncing 
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh),
                            onPressed: checkStatus,
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Amount Display
                    Center(
                      child: Column(
                        children: [
                          Text(
                            amountUsd != null
                                ? '\$${amountUsd.toStringAsFixed(2)}'
                                : 'KES ${amountKes?.toStringAsFixed(0) ?? '—'}',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (amountUsd != null && amountKes != null)
                            Text(
                              'KES ${amountKes.toStringAsFixed(0)}',
                              style: TextStyle(
                                color: subtle,
                                fontSize: 16,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Status Badge
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, color: statusColor, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              statusText,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Metadata table
                    _buildDetailRow('Transaction Type', isDeposit ? 'Deposit' : 'Withdrawal', textColor, subtle),
                    const Divider(height: 24),
                    _buildDetailRow('Date', timeStr, textColor, subtle),
                    const Divider(height: 24),
                    if (isDeposit)
                      _buildDetailRow('Destination', dest.toUpperCase(), textColor, subtle),
                    if (isDeposit)
                      const Divider(height: 24),
                    if (rate != null)
                      _buildDetailRow('Exchange Rate', '1 USD = ${rate.toStringAsFixed(2)} KES', textColor, subtle),
                    if (rate != null)
                      const Divider(height: 24),
                    if (mpesaPhone.isNotEmpty)
                      _buildDetailRow('M-Pesa Number', mpesaPhone, textColor, subtle),
                    if (mpesaPhone.isNotEmpty)
                      const Divider(height: 24),
                    if (mpesaTxnId.isNotEmpty)
                      _buildDetailRow('Receipt Number', mpesaTxnId, textColor, subtle),
                    if (mpesaTxnId.isNotEmpty)
                      const Divider(height: 24),

                    // Error Section (if failed or cancelled)
                    if ((status == 'failed' || status == 'cancelled') && failureReason.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Reason for Failure',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    failureReason,
                                    style: TextStyle(
                                      color: textColor.withValues(alpha: 0.8),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Action buttons
                    if (isPendingOrProcessing) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: checkStatus,
                          icon: isSyncing 
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.refresh, color: Colors.white),
                          label: Text(
                            isSyncing ? 'Checking...' : 'Check Status',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accentColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ] else if ((status == 'failed' || status == 'cancelled') && isDeposit && mpesaPhone.isNotEmpty) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: retrySTKPush,
                          icon: const Icon(Icons.replay_rounded, color: Colors.white),
                          label: const Text(
                            'Retry STK Push',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accentColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, Color textColor, Color subtle) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: subtle,
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class AnimatedMoneyWidget extends StatelessWidget {
  final AnimationController animationController;

  const AnimatedMoneyWidget({required this.animationController, super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Falling coin 1
          AnimatedBuilder(
            animation: animationController,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(
                  -50 + (50 * (animationController.value * 2 % 1)),
                  -100 + (200 * animationController.value),
                ),
                child: Opacity(
                  opacity: 1 - (animationController.value * 0.3),
                  child: Transform.rotate(
                    angle: animationController.value * 12.56,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [
                            Color.fromARGB(255, 255, 200, 50),
                            Color.fromARGB(255, 255, 150, 0),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color.fromARGB(
                              255,
                              255,
                              150,
                              0,
                            ).withValues(alpha: 0.5),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          '\$',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // Falling coin 2
          AnimatedBuilder(
            animation: animationController,
            builder: (context, child) {
              final offsetValue = (animationController.value - 0.33) % 1;
              return Transform.translate(
                offset: Offset(
                  50 + (50 * (offsetValue * 2 % 1)),
                  -100 + (200 * offsetValue),
                ),
                child: Opacity(
                  opacity: 1 - (offsetValue * 0.3),
                  child: Transform.rotate(
                    angle: offsetValue * 12.56,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [
                            Color.fromARGB(255, 255, 200, 50),
                            Color.fromARGB(255, 255, 150, 0),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color.fromARGB(
                              255,
                              255,
                              150,
                              0,
                            ).withValues(alpha: 0.5),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          '\$',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // Falling coin 3
          AnimatedBuilder(
            animation: animationController,
            builder: (context, child) {
              final offsetValue = (animationController.value - 0.66) % 1;
              return Transform.translate(
                offset: Offset(
                  0 + (50 * (offsetValue * 2 % 1)),
                  -100 + (200 * offsetValue),
                ),
                child: Opacity(
                  opacity: 1 - (offsetValue * 0.3),
                  child: Transform.rotate(
                    angle: offsetValue * 12.56,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [
                            Color.fromARGB(255, 255, 200, 50),
                            Color.fromARGB(255, 255, 150, 0),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color.fromARGB(
                              255,
                              255,
                              150,
                              0,
                            ).withValues(alpha: 0.5),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          '\$',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // Sparkles/stars
          AnimatedBuilder(
            animation: animationController,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(
                  -60 * (2 * (animationController.value % 0.5) - 1),
                  -80 + (160 * animationController.value),
                ),
                child: Opacity(
                  opacity: 1 - (animationController.value * 0.5),
                  child: const Text('\u2728', style: TextStyle(fontSize: 24)),
                ),
              );
            },
          ),
          // Central money bag icon
          Icon(
            Icons.card_giftcard,
            size: 80,
            color: const Color.fromARGB(
              255,
              76,
              175,
              80,
            ).withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }
}
