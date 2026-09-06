import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bubble/bubble_manager.dart';

/// How far along one setup task is.
///
/// [unknown] exists because iOS gives an app no way to ask whether its own
/// keyboard is installed. It must never be presented to the user as a failure:
/// the difference between "you have not done this" and "we cannot see it from
/// here" is the difference between blaming the user and being honest.
enum SetupStep { missing, partial, done, unknown }

/// Live state of the two things the user has to turn on outside the app.
@immutable
class SetupStatus {
  const SetupStatus({
    this.button = SetupStep.missing,
    this.keyboard = SetupStep.missing,
  });

  /// The floating TransKey button: [missing] with no permission to show over
  /// other apps, [partial] once allowed but not currently running, [done] when
  /// it is on screen. Android only.
  final SetupStep button;

  /// The TransKey keyboard. Android: [missing] until it appears in the system
  /// keyboard list, [partial] once listed but some other keyboard is in use,
  /// [done] when it is the active one. iOS: [done] once the keyboard has
  /// actually run, [unknown] before that.
  final SetupStep keyboard;

  /// iOS has no floating button; its share extension needs no setup step.
  bool get showButtonTask => Platform.isAndroid;

  bool get allDone =>
      (!showButtonTask || button == SetupStep.done) && keyboard == SetupStep.done;

  /// Whether anything is still worth prompting about. [SetupStep.unknown] does
  /// not count: we will not nag a user about something we cannot verify.
  bool get hasWorkLeft =>
      (showButtonTask && button != SetupStep.done) ||
      keyboard == SetupStep.missing ||
      keyboard == SetupStep.partial;

  SetupStatus copyWith({SetupStep? button, SetupStep? keyboard}) => SetupStatus(
        button: button ?? this.button,
        keyboard: keyboard ?? this.keyboard,
      );

  @override
  bool operator ==(Object other) =>
      other is SetupStatus && other.button == button && other.keyboard == keyboard;

  @override
  int get hashCode => Object.hash(button, keyboard);
}

/// Single source of truth for "is TransKey actually set up".
///
/// Before this existed, three screens each kept their own copy of the answer,
/// none of them re-read it when the user came back from system settings, and
/// the setup wizard never asked at all - so it congratulated users who had done
/// nothing and stayed silent for users who had just succeeded. Every surface
/// now reads here, and [refresh] runs on every app resume.
class SetupStatusNotifier extends AsyncNotifier<SetupStatus> {
  static const _bubbleChannel = MethodChannel('transkey/bubble');
  static const _imeChannel = MethodChannel('transkey/ime');
  static const _appGroupChannel = MethodChannel('transkey/appgroup');

  @override
  Future<SetupStatus> build() => _read();

  /// Re-read everything from the platform. Cheap (four channel round trips)
  /// and safe to call on every resume.
  Future<void> refresh() async {
    final fresh = await _read();
    if (state.value != fresh) state = AsyncData(fresh);
  }

  Future<SetupStatus> _read() async {
    if (Platform.isAndroid) {
      return SetupStatus(
        button: await _readButton(),
        keyboard: await _readAndroidKeyboard(),
      );
    }
    return SetupStatus(button: SetupStep.unknown, keyboard: await _readIosKeyboard());
  }

  Future<SetupStep> _readButton() async {
    final granted = await _bubbleBool('checkPermission');
    if (!granted) return SetupStep.missing;
    // Keep BubbleManager's cached grant in step, so the home-screen toggle
    // stops showing an off button to a user who just granted the permission.
    await ref.read(bubbleManagerProvider.notifier).checkPermission();
    final running = await _bubbleBool('isRunning');
    return running ? SetupStep.done : SetupStep.partial;
  }

  Future<SetupStep> _readAndroidKeyboard() async {
    if (!await _imeBool('isEnabled')) return SetupStep.missing;
    return await _imeBool('isSelected') ? SetupStep.done : SetupStep.partial;
  }

  /// iOS: the keyboard extension stamps a heartbeat into the shared container
  /// every time it appears. Writing there is only possible with Full Access, so
  /// a heartbeat proves the keyboard is installed AND usable. No heartbeat
  /// proves nothing, hence [SetupStep.unknown].
  Future<SetupStep> _readIosKeyboard() async {
    try {
      final beat = await _appGroupChannel
          .invokeMapMethod<String, dynamic>('readKeyboardHeartbeat');
      final seenAt = beat?['seenAt'];
      if (seenAt is num && seenAt > 0) return SetupStep.done;
      return SetupStep.unknown;
    } on PlatformException {
      return SetupStep.unknown;
    } on MissingPluginException {
      return SetupStep.unknown;
    }
  }

  Future<bool> _bubbleBool(String method) => _boolCall(_bubbleChannel, method);
  Future<bool> _imeBool(String method) => _boolCall(_imeChannel, method);

  Future<bool> _boolCall(MethodChannel channel, String method) async {
    try {
      return await channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // The engine is pre-warmed before MainActivity attaches its handlers, so
      // an early call can land before the channel exists. Treat as "not set up"
      // and let the next refresh correct it.
      return false;
    }
  }
}

final setupStatusProvider =
    AsyncNotifierProvider<SetupStatusNotifier, SetupStatus>(SetupStatusNotifier.new);
