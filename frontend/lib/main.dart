import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/serfix_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main_navigation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const SerfixApp());
}

class SerfixApp extends StatelessWidget {
  const SerfixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        ChangeNotifierProvider<SerfixProvider>(create: (_) => SerfixProvider()),
        ChangeNotifierProvider<SettingsProvider>(
            create: (_) => SettingsProvider()),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return Consumer<SettingsProvider>(
            builder: (context, settings, _) {
              return MaterialApp(
                title: 'SerFix',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: settings.themeMode,
                home: auth.isInitializing || !settings.isInitialized
                    ? const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      )
                    : auth.isAuthenticated
                        ? const MainNavigationScreen()
                        : const LoginScreen(),
              );
            },
          );
        },
      ),
    );
  }
}
