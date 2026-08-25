import 'package:flutter/material.dart';
import 'screens/home_shell.dart';
import 'services/app_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStore.instance.initialize();
  runApp(const SignApp());
}

class SignApp extends StatelessWidget {
  const SignApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF263238),
      brightness: Brightness.light,
      surface: const Color(0xFFF7F5F2),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sign',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF7F5F2),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white.withValues(alpha: .88),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: Colors.black.withValues(alpha: .05))),
        ),
      ),
      home: const HomeShell(),
    );
  }
}
