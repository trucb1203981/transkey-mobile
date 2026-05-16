import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/theme/app_theme.dart';

class KeyboardSetupScreen extends StatefulWidget {
  final bool showSkip;

  const KeyboardSetupScreen({super.key, this.showSkip = true});

  static const _setupDoneKey = 'keyboard_setup_done';

  static Future<bool> hasCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_setupDoneKey) ?? false;
  }

  static Future<void> markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_setupDoneKey, true);
  }

  static Future<void> openKeyboardSettings() async {
    if (Platform.isIOS) {
      const url = 'App-prefs:root=General&path=Keyboard/KEYBOARDS';
      try {
        await const MethodChannel('transkey/appgroup')
            .invokeMethod('openKeyboardSettings');
      } catch (_) {
        try {
          await const MethodChannel('transkey/deeplink')
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

  static Future<bool> hasBubblePermission() async {
    if (!Platform.isAndroid) return true;
    try {
      return await const MethodChannel('transkey/bubble')
          .invokeMethod<bool>('checkPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  State<KeyboardSetupScreen> createState() => _KeyboardSetupScreenState();
}

class _KeyboardSetupScreenState extends State<KeyboardSetupScreen>
    with WidgetsBindingObserver {
  int _currentStep = 0;
  bool _waitingForPermission = false;
  final _pageController = PageController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  // Called when app returns from Android overlay permission screen
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForPermission && Platform.isAndroid) {
      _waitingForPermission = false;
      _checkAndStartBubble();
    }
  }

  Future<void> _checkAndStartBubble() async {
    try {
      final hasPermission = await const MethodChannel('transkey/bubble')
          .invokeMethod<bool>('checkPermission') ?? false;
      if (hasPermission && mounted) {
        // Start the bubble service so it's visible immediately
        await const MethodChannel('transkey/bubble').invokeMethod('startBubble');
        // Auto-advance to next step
        if (_currentStep < 2) _nextStep();
      }
    } catch (_) {}
  }

  void _nextStep() {
    if (_currentStep < 4) {
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
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.setupTitle),
        leading: widget.showSkip
            ? TextButton(
                onPressed: () {
                  KeyboardSetupScreen.markDone();
                  Navigator.of(context).pop();
                },
                child: Text(l.skip),
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
                      ? l.setupStep1TitleIOS
                      : l.setupStep1TitleAndroid,
                  description: Platform.isIOS
                      ? l.setupStep1DescIOS
                      : l.setupStep1DescAndroid,
                  illustration: _buildIllustration(1, isDark),
                ),
                _StepPage(
                  step: 2,
                  icon: Icons.verified_user_outlined,
                  title: l.setupStep2Title,
                  description: Platform.isIOS
                      ? l.setupStep2DescIOS
                      : l.setupStep2DescAndroid,
                  illustration: _buildIllustration(2, isDark),
                ),
                _StepPage(
                  step: 3,
                  icon: Icons.check_circle_outline,
                  title: l.setupStep3Title,
                  description: Platform.isIOS
                      ? l.setupStep3DescIOS
                      : l.setupStep3DescAndroid,
                  illustration: _buildIllustration(3, isDark),
                ),
                _StepPage(
                  step: 4,
                  icon: Icons.translate_outlined,
                  title: l.setupStep4Title,
                  description: Platform.isIOS
                      ? l.setupStep4DescIOS
                      : l.setupStep4DescAndroid,
                  illustration: _buildIllustration(4, isDark),
                ),
                _StepPage(
                  step: 5,
                  icon: Icons.auto_awesome_outlined,
                  title: l.setupStep5Title,
                  description: l.setupStep5Desc,
                  illustration: _buildIllustration(5, isDark),
                ),
              ],
            ),
          ),

          // Step indicators
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
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
                      onPressed: () async {
                        if (Platform.isAndroid) {
                          setState(() => _waitingForPermission = true);
                        }
                        await KeyboardSetupScreen.openKeyboardSettings();
                        // iOS: advance directly after opening settings
                        if (Platform.isIOS && mounted) _nextStep();
                      },
                      icon: const Icon(Icons.settings_outlined),
                      label: Text(
                        Platform.isIOS ? l.setupOpenSettings : l.setupOpenPermissions,
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
                      _currentStep < 4 ? l.next : l.done,
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
              child: const Row(
                children: [
                  Icon(Icons.add_circle, color: AppColors.primary, size: 20),
                  SizedBox(width: 8),
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

    if (step == 4) {
      // Share/Process text from any app
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mock text with selection highlight
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Konnichiwa, how are you?',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      'Konnichiwa',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Context menu mockup
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.translate, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'TransKey',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Arrow pointing to result
            const Icon(Icons.arrow_downward, size: 16, color: Colors.grey),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary, width: 1.5),
              ),
              child: const Text(
                'こんにちは',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (step == 5) {
      // Smart features grid
      final features = [
        (Icons.translate, 'Translate', false),
        (Icons.reply, 'Reply', false),
        (Icons.summarize_outlined, 'Summarize', true),
        (Icons.lightbulb_outline, 'Explain', true),
        (Icons.auto_fix_high, 'Refine', true),
      ];

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: features.map((f) {
            final (icon, label, locked) = f;
            return Container(
              width: 88,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: locked ? 0.2 : 0.5),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      Icon(
                        icon,
                        size: 24,
                        color: locked
                            ? AppColors.textSecondary
                            : AppColors.primary,
                      ),
                      if (locked)
                        const Icon(Icons.lock, size: 10, color: AppColors.textSecondary),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: locked ? AppColors.textSecondary : AppColors.primary,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
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
