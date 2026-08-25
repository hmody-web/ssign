import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/home_shell.dart';
import 'services/app_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStore.instance.initialize();
  runApp(const BoomaApp());
}

class BoomaApp extends StatelessWidget {
  const BoomaApp({super.key});
  static const accent = Color(0xFF0C8EFE);

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Tajawal',
      colorScheme: scheme.copyWith(primary: accent, secondary: accent),
      scaffoldBackgroundColor: dark ? const Color(0xFF090909) : const Color(0xFFF5F7FA),
      canvasColor: dark ? const Color(0xFF090909) : const Color(0xFFF5F7FA),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? const Color(0xFF171717) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? Colors.white.withValues(alpha: .055) : Colors.black.withValues(alpha: .035),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: dark ? Colors.white.withValues(alpha: .07) : Colors.black.withValues(alpha: .07)),
        ),
      ),
      dividerColor: dark ? Colors.white.withValues(alpha: .08) : Colors.black.withValues(alpha: .08),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: AppStore.instance,
        builder: (context, _) {
          final store = AppStore.instance;
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Booma',
            locale: Locale(store.languageCode),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: _theme(Brightness.light),
            darkTheme: _theme(Brightness.dark),
            themeMode: store.theme == 'light' ? ThemeMode.light : ThemeMode.dark,
            home: const HomeShell(),
          );
        },
      );
}
