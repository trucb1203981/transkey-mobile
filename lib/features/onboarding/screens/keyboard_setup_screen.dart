import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/theme/app_theme.dart';

class KeyboardSetupScreen extends StatefulWidget {
  final bool showSkip;

  const KeyboardSetupScreen({super.key, this.showSkip = true});

  static const _setupDoneKey = 'keyboard_setup_done';

  static Future<bool> hasCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    if (Platform.isIOS) {
      return prefs.getBool(_setupDoneKey) ?? false;
    }
    return true; // Android doesn't need keyboard setup
  }

  static Future<void> markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_setupDoneKey, true);
  }

  static Future<void> openKeyboardSettings() async {
    if (Platform.isIOS) {
      const url = 'App-prefs:root=General&path=Keyboard/KEYBOARDS';
      try {
        await MethodChannel('transkey/appgroup')
            .invokeMethod('openKeyboardSettings');
      } catch (_) {
        try {
          await MethodChannel('transkey/deeplink')
              .invokeMethod('open', {'url': url});
        } catch (_) {}
      }
    } else if (Platform.isAndroid) {
      try {
        await const MethodChannel('transkey/bubble')
            .invokeMethod('requestPermission');
      } catch (_) {}
    }
  }

  @override
  State<KeyboardSetupScreen> createState() => _KeyboardSetupScreenState();
}

class _KeyboardSetupScreenState extends State<KeyboardSetupScreen> {
  int _currentStep = 0;
  final _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < 2) {
      setState(() => _currentStep++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      KeyboardSetupScreen.markDone();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Keyboard'),
        leading: widget.showSkip
            ? TextButton(
                onPressed: () {
                  KeyboardSetupScreen.markDone();
                  Navigator.of(context).pop();
                },
                child: const Text('Skip'),
              )
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _StepPage(
                  step: 1,
                  icon: Icons.keyboard_outlined,
                  title: Platform.isIOS
                      ? 'Add TransKey Keyboard'
                      : 'Enable Floating Bubble',
                  description: Platform.isIOS
                      ? 'Go to Settings and add TransKey as a custom keyboard so you can translate directly while typing.'
                      : 'Allow TransKey to display over other apps so the floating bubble can appear when you need it.',
                  illustration: _buildIllustration(1, isDark),
                ),
                _StepPage(
                  step: 2,
                  icon: Icons.verified_user_outlined,
                  title: 'Allow Full Access',
                  description: Platform.isIOS
                      ? 'Tap TransKey in the keyboard list and enable "Allow Full Access". This is needed to connect to the internet for translations.'
                      : 'The overlay permission lets TransKey show a floating bubble on top of other apps for quick translations.',
                  illustration: _buildIllustration(2, isDark),
                ),
                _StepPage(
                  step: 3,
                  icon: Icons.check_circle_outline,
                  title: 'You\'re All Set!',
                  description: Platform.isIOS
                      ? 'When typing in any app, long-press the globe key 🌐 to switch to TransKey. Tap "Reply" to translate your message instantly.'
                      : 'Select text in any app and share it to TransKey, or use the floating bubble for quick translations.',
                  illustration: _buildIllustration(3, isDark),
                ),
              ],
            ),
          ),

          // Step indicators
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _currentStep ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _currentStep
                        ? AppColors.primary
                        : AppColors.primary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_currentStep < 2) ...[
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        KeyboardSetupScreen.openKeyboardSettings();
                      },
                      icon: const Icon(Icons.settings_outlined),
                      label: Text(
                        Platform.isIOS ? 'Open Settings' : 'Open Permissions',
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _nextStep,
                    style: _currentStep < 2
                        ? ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: AppColors.primary,
                            elevation: 0,
                            side: const BorderSide(color: AppColors.primary),
                          )
                        : null,
                    child: Text(
                      _currentStep < 2 ? 'Next' : 'Done',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIllustration(int step, bool isDark) {
    final bgColor = isDark ? const Color(0xFF2A2A3E) : const Color(0xFFF5F3FF);
    final cardColor = isDark ? const Color(0xFF1E1E30) : Colors.white;

    if (step == 1 && Platform.isIOS) {
      // Settings > Keyboard > Add Keyboard
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _mockSettingRow(Icons.settings, 'Settings', cardColor),
            const SizedBox(height: 4),
            _mockSettingRow(Icons.keyboard, 'General', cardColor),
            const SizedBox(height: 4),
            _mockSettingRow(Icons.keyboard_outlined, 'Keyboard', cardColor),
            const SizedBox(height: 4),
            _mockSettingRow(Icons.add, 'Keyboards', cardColor),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.add_circle, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Add TransKey',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (step == 2 && Platform.isIOS) {
      // Allow Full Access toggle
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.translate, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'TransKey',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Container(
                    width: 48,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: EdgeInsets.only(right: 2),
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Allow Full Access',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Step 3: Success / ready
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.primary,
            size: 64,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  Platform.isIOS ? 'Long press 🌐 → TransKey' : 'Share text → TransKey',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mockSettingRow(IconData icon, String label, Color bgColor) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
        ],
      ),
    );
  }
}

class _StepPage extends StatelessWidget {
  final int step;
  final IconData icon;
  final String title;
  final String description;
  final Widget illustration;

  const _StepPage({
    required this.step,
    required this.icon,
    required this.title,
    required this.description,
    required this.illustration,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.lg),
          // Step badge
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$step',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Illustration
          illustration,
          const SizedBox(height: AppSpacing.xl),

          // Title
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),

          // Description
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
