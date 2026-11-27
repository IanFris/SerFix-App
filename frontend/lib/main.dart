import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_spacing.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/serfix_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'widgets/serfix_components.dart';

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
                    ? Scaffold(
                        body: SafeArea(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 380),
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.x6),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 72,
                                      height: 72,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            AppColors.primary,
                                            AppColors.secondary,
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          AppSpacing.radiusXl,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.ac_unit_outlined,
                                        size: AppSpacing.iconExtraLarge,
                                        color: AppColors.accent,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.x3),
                                    Text(
                                      'SerFix',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge,
                                    ),
                                    const SizedBox(height: AppSpacing.x1),
                                    Text(
                                      'Udara nyaman, servis terpercaya.',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                    const SizedBox(height: AppSpacing.x6),
                                    const SerfixSkeleton(width: 200),
                                    const SizedBox(height: AppSpacing.x4),
                                    const SerfixSkeleton(
                                      height: 112,
                                      radius: AppSpacing.radiusLg,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    : !settings.hasSeenOnboarding
                        ? OnboardingScreen(
                            onComplete: settings.completeOnboarding,
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
