import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const _kDoneKey = 'onboarding_done';

  static Future<bool> isDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kDoneKey) ?? false;
  }

  static Future<void> markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDoneKey, true);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  static const _pages = <_OnboardingPageData>[
    _OnboardingPageData(
      icon: Icons.translate_rounded,
      title: 'Welcome to TransKey',
      subtitle: 'Translate text in real-time across\n20+ languages instantly.',
    ),
    _OnboardingPageData(
      icon: Icons.language_rounded,
      title: 'Choose Your Language',
      subtitle: 'Pick your preferred target language.\nYou can change it anytime in settings.',
    ),
    _OnboardingPageData(
      icon: Icons.rocket_launch_rounded,
      title: 'Get Started',
      subtitle: 'Sign in or create a free account\nto start translating now.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _finish() async {
    await OnboardingScreen.markDone();
    if (mounted) context.go('/auth/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _finish,
                child: Text(
                  'Skip',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondary
                        : AppColors.textSecondaryLight,
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            page.icon,
                            size: 56,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          page.title,
                          style: theme.textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          page.subtitle,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: isDark
                                ? AppColors.textSecondary
                                : AppColors.textSecondaryLight,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == i ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == i
                              ? AppColors.primary
                              : (isDark
                                  ? AppColors.border
                                  : AppColors.borderLight),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _goNext,
                      child: Text(
                        _currentPage == _pages.length - 1
                            ? 'Get Started'
                            : 'Next',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}
