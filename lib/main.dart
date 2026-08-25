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

  ThemeData _theme() {
    const surface = Color(0xFF121212);
    const background = Color(0xFF090909);
    const card = Color(0xFF171717);
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: surface,
    ).copyWith(
      primary: accent,
      secondary: accent,
      surface: surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Tajawal',
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      cardTheme: CardThemeData(
        elevation: 0,
        color: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: .055),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: .07)),
        ),
      ),
      dividerColor: Colors.white.withValues(alpha: .08),
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
            theme: _theme(),
            darkTheme: _theme(),
            themeMode: ThemeMode.dark,
            home: const HomeShell(),
          );
        },
      );
}
