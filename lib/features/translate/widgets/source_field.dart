import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';

/// Source-text input field with a top-right action cluster (voice mic +
/// clear button). The clear button subscribes to the controller via
/// `ListenableBuilder` so the surrounding tree doesn't rebuild on every
/// keystroke — only the icon's visibility flips.
///
/// Voice STT logic lives in the host screen (mic permission, picker
/// fallback when source is Auto, speech_to_text plugin lifecycle) — too
/// much cross-state to push into a leaf widget. Host supplies the
/// `isListening` flag + `onVoicePressed` callback.
class SourceField extends StatelessWidget {
  const SourceField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.maxChars,
    required this.hintText,
    required this.isListening,
    required this.voiceTooltip,
    required this.onVoicePressed,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int maxChars;
  final String hintText;
  /// Drives the mic icon (filled red while recording) + tooltip text.
  final bool isListening;
  /// Resolved text for the tooltip — host swaps between voiceTooltip /
  /// voiceListening per its current state.
  final String voiceTooltip;
  final VoidCallback onVoicePressed;
  /// Invoked when the user taps the clear-X. Host typically clears the
  /// controller AND nukes the result panel so the next translate doesn't
  /// flash stale output.
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topRight,
      children: [
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          maxLines: 6,
          maxLength: maxChars,
          decoration: InputDecoration(
            hintText: hintText,
            counterStyle: const TextStyle(fontSize: 11),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: voiceTooltip,
                icon: Icon(
                  isListening ? Icons.mic : Icons.mic_none,
                  size: 22,
                  color: isListening ? Colors.red : null,
                ),
                onPressed: onVoicePressed,
              ),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  if (controller.text.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: onClear,
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
