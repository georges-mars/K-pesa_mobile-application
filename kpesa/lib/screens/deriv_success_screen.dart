import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/signup_data.dart';
import 'mpesa_phone_screen.dart';

class DerivSuccessScreen extends StatefulWidget {
  final SignupData signupData;

  const DerivSuccessScreen({super.key, required this.signupData});

  @override
  State<DerivSuccessScreen> createState() => _DerivSuccessScreenState();
}

class _DerivSuccessScreenState extends State<DerivSuccessScreen> {
  static const _accent = Color.fromARGB(255, 55, 194, 21);

  String _name = '';
  String _email = '';
  String _account = '';
  bool _loading = true;
  String? _error;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _account = widget.signupData.derivAccount ?? '';
    _fetchDerivUserInfo();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  Future<void> _fetchDerivUserInfo() async {
    final token = widget.signupData.derivAccessToken;
    if (token == null || token.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No access token available';
      });
      return;
    }

    try {
      // Connect to Deriv WebSocket API
      _channel = WebSocketChannel.connect(
        Uri.parse('wss://ws.binaryws.com/websockets/v3?app_id=130232'),
      );

      // Listen for responses
      _subscription = _channel!.stream.listen(
        (message) {
          final data = jsonDecode(message as String) as Map<String, dynamic>;

          if (data.containsKey('authorize')) {
            final auth = data['authorize'] as Map<String, dynamic>?;
            if (auth != null) {
              // Display full name on screen (all names for confirmation)
              final fullName = (auth['fullname'] ?? '').toString();

              // But save only first + last name to database
              final nameParts = fullName
                  .split(' ')
                  .where((s) => s.isNotEmpty)
                  .toList();
              final savedName = nameParts.length >= 2
                  ? '${nameParts.first} ${nameParts.last}'
                  : fullName;

              setState(() {
                _name = fullName; // Show ALL names on screen
                _email = (auth['email'] ?? '').toString();
                _account = (auth['loginid'] ?? _account).toString();
                _loading = false;
              });
            }
          } else if (data.containsKey('error')) {
            final error = data['error'] as Map<String, dynamic>?;
            setState(() {
              _loading = false;
              _error = error?['message']?.toString() ?? 'Unknown error';
            });
          }

          // Close connection after getting the response
          _channel?.sink.close();
        },
        onError: (error) {
          setState(() {
            _loading = false;
            _error = 'Connection error: $error';
          });
        },
        onDone: () {
          if (_loading && mounted) {
            setState(() {
              _loading = false;
            });
          }
        },
      );

      // Send authorize request
      _channel!.sink.add(jsonEncode({'authorize': token}));
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to connect: $e';
      });
    }
  }

  SignupData get _updatedSignupData {
    // Save only first + last name to database
    final nameParts = _name.split(' ').where((s) => s.isNotEmpty).toList();
    final savedName = nameParts.length >= 2
        ? '${nameParts.first} ${nameParts.last}'
        : _name;

    return SignupData(
      derivEmail: _email.isNotEmpty ? _email : widget.signupData.derivEmail,
      derivName: savedName, // Save first + last only
      derivAccount: _account.isNotEmpty
          ? _account
          : widget.signupData.derivAccount,
      derivAccessToken: widget.signupData.derivAccessToken,
      derivRefreshToken: widget.signupData.derivRefreshToken,
      derivTokenExpiresAt: widget.signupData.derivTokenExpiresAt,
      binanceId: widget.signupData.binanceId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtleColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),
                Text(
                  'Welcome!',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // ── Checkmark illustration ────────────────────────────────────
                Center(
                  child: SizedBox(
                    width: 160,
                    height: 160,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Decorative dots
                        ..._buildDots(),
                        // Green rounded box with checkmark
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: _accent,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 36),
                Text(
                  'You have successfully signed in to Deriv.\nPlease confirm that this is your account.',
                  style: TextStyle(
                    color: subtleColor,
                    fontSize: 15,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // ── User details ──────────────────────────────────────────────
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(color: _accent),
                    ),
                  )
                else if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  )
                else ...[
                  _DetailTile(
                    label: 'Name',
                    value: _name.isNotEmpty ? _name : 'Not available',
                    textColor: textColor,
                    subtleColor: subtleColor,
                  ),
                  const SizedBox(height: 10),
                  _DetailTile(
                    label: 'Account ID',
                    value: _account,
                    textColor: textColor,
                    subtleColor: subtleColor,
                  ),
                ],

                const SizedBox(height: 40),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: _loading
                      ? null
                      : () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => MpesaPhoneScreen(
                                signupData: _updatedSignupData,
                              ),
                            ),
                          );
                        },
                  child: const Text(
                    'Yes, this is my account!',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Not my account',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDots() {
    const positions = [
      Offset(-68, -30),
      Offset(68, -30),
      Offset(-60, 40),
      Offset(60, 40),
      Offset(0, -72),
      Offset(0, 72),
    ];
    const sizes = [10.0, 8.0, 12.0, 8.0, 10.0, 8.0];
    const opacities = [0.5, 0.3, 0.6, 0.3, 0.4, 0.3];

    return List.generate(positions.length, (i) {
      return Positioned(
        left: 80 + positions[i].dx - sizes[i] / 2,
        top: 80 + positions[i].dy - sizes[i] / 2,
        child: Container(
          width: sizes[i],
          height: sizes[i],
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: opacities[i]),
            shape: BoxShape.circle,
          ),
        ),
      );
    });
  }
}

class _DetailTile extends StatelessWidget {
  final String label;
  final String value;
  final Color textColor;
  final Color subtleColor;

  const _DetailTile({
    required this.label,
    required this.value,
    required this.textColor,
    required this.subtleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text('$label  ', style: TextStyle(color: subtleColor, fontSize: 14)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: textColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
