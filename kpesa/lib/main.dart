import 'dart:async';

import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/login_page.dart';
import 'screens/sign_up_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Could not load .env file, using fallbacks: $e");
  }

  // Check if the app was cold-started via the Deriv OAuth callback deep link.
  final appLinks = AppLinks();
  Uri? initialDerivUri;
  try {
    final uri = await appLinks.getInitialLink();
    if (uri != null &&
        uri.scheme == 'kpesa' &&
        uri.host == 'deriv-callback') {
      initialDerivUri = uri;
    }
  } catch (_) {}

  runApp(MyApp(initialDerivUri: initialDerivUri));
}

class MyApp extends StatefulWidget {
  final Uri? initialDerivUri;

  const MyApp({super.key, this.initialDerivUri});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  void initState() {
    super.initState();
    // Listen for deep links that arrive while the app is already running.
    // This handles the case where Android did NOT kill the app and the
    // user is sitting on LoginPage (not SignUpPage) when the callback fires.
    _linkSub = _appLinks.uriLinkStream.listen(_onIncomingLink);
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  void _onIncomingLink(Uri uri) {
    if (uri.scheme == 'kpesa' && uri.host == 'deriv-callback') {
      // Push SignUpPage with the URI so it can process the OAuth callback.
      _navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => SignUpPage(initialDerivUri: uri),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget home;
    if (widget.initialDerivUri != null) {
      // Cold start via deep link — go straight to SignUpPage with the URI
      home = SignUpPage(initialDerivUri: widget.initialDerivUri);
    } else {
      home = LoginPage(onToggleTheme: _toggleTheme);
    }

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'K-Pesa',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 55, 194, 21),
        ),
        scaffoldBackgroundColor: Colors.white,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 55, 194, 21),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
      ),
      themeMode: _themeMode,
      home: home,
    );
  }
}
