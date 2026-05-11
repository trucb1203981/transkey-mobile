import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'features/translate/widgets/result_bottom_sheet.dart';
import 'shared/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const ProviderScope(child: TransKeyApp()));
}

class TransKeyApp extends ConsumerStatefulWidget {
  const TransKeyApp({super.key});

  @override
  ConsumerState<TransKeyApp> createState() => _TransKeyAppState();
}

class _TransKeyAppState extends ConsumerState<TransKeyApp> {
  final _shareChannel = const MethodChannel('transkey/share');
  final _bubbleChannel = const MethodChannel('transkey/bubble');

  @override
  void initState() {
    super.initState();
    _setupMethodChannels();
  }

  void _setupMethodChannels() {
    // Share intent listener
    _shareChannel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedText') {
        final text = call.arguments as String?;
        if (text != null && text.isNotEmpty) {
          _openResultSheet(text);
        }
      }
    });

    // Bubble tap/dismiss listener
    _bubbleChannel.setMethodCallHandler((call) async {
      if (call.method == 'onTapped') {
        _openResultSheetFromBubble();
      }
    });
  }

  void _openResultSheet(String text) {
    // Wait for the router to be ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _routerKey.currentContext;
      if (context != null) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF16161A)
                  : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppSpacing.sheetRadius),
              ),
            ),
            child: ResultBottomSheet(
              sourceText: text,
              targetLang: 'en',
            ),
          ),
        );
      }
    });
  }

  void _openResultSheetFromBubble() {
    // TODO: Could read last clipboard or last translation
    debugPrint('[Bubble] Tapped — opening result sheet');
  }

  static final _routerKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      key: _routerKey,
      title: 'TransKey',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
