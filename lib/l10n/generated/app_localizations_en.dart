// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get translate => 'Translate';

  @override
  String get summarize => 'Summarize';

  @override
  String get explain => 'Explain';

  @override
  String get refine => 'Refine';

  @override
  String get reply => 'Reply';

  @override
  String get history => 'History';

  @override
  String get glossary => 'Glossary';

  @override
  String get settings => 'Settings';

  @override
  String get suggestions => 'Suggestions';

  @override
  String get copy => 'Copy';

  @override
  String get save => 'Save';

  @override
  String get copied => 'Copied';

  @override
  String get hintEnterText => 'Enter text to translate...';

  @override
  String detectedLang(String lang) {
    return 'Detected: $lang';
  }

  @override
  String get autoDetect => 'Auto Detect';

  @override
  String get sourceLang => 'Source';

  @override
  String get targetLang => 'Target';

  @override
  String get swapLanguages => 'Swap languages';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get sectionLanguage => 'Language';

  @override
  String get sectionTranslation => 'Translation';

  @override
  String get sectionAdvanced => 'Advanced';

  @override
  String get sectionOther => 'Other';

  @override
  String get targetLanguage => 'Target language';

  @override
  String get sourceLanguage => 'Source language';

  @override
  String get appLanguage => 'App language';

  @override
  String get saveHistory => 'Save history';

  @override
  String get romanization => 'Romanization';

  @override
  String get replySuggestions => 'Reply suggestions';

  @override
  String get toneOverride => 'Translation tone';

  @override
  String get replyToneOverride => 'Reply tone';

  @override
  String get replyLanguage => 'Reply language';

  @override
  String get replyLanguageFromConversation => 'From conversation';

  @override
  String get autoCloseResult => 'Auto-close result';

  @override
  String get autoCloseSeconds => 'Auto-close (seconds)';

  @override
  String get autoCloseUnit => 'seconds';

  @override
  String get autoCloseDisabled => 'Off';

  @override
  String get toneAuto => 'Auto';

  @override
  String get toneBusiness => 'Business';

  @override
  String get toneCasual => 'Casual';

  @override
  String get toneFormal => 'Formal';

  @override
  String get tonePolite => 'Polite';

  @override
  String get toneTechnical => 'Technical';

  @override
  String get toneNeutral => 'Neutral';

  @override
  String get toneReplySameAsTranslate => 'Same as translate';

  @override
  String get popupTo => 'To:';

  @override
  String get tabTranslate => 'Translate';

  @override
  String get tabReply => 'Reply';

  @override
  String get tabSummarize => 'Summarize';

  @override
  String get tabExplain => 'Explain';

  @override
  String get tabRefine => 'Refine';

  @override
  String get keyboardSetup => 'Keyboard Setup';

  @override
  String get bubbleSetup => 'Bubble Setup';

  @override
  String get floatingBubble => 'Floating Bubble';

  @override
  String get bubbleActive => 'Active';

  @override
  String get bubbleInactive => 'Inactive';

  @override
  String get sendFeedback => 'Send feedback';

  @override
  String get termsOfService => 'Terms of Service';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get version => 'Version';

  @override
  String get upgrade => 'Upgrade';

  @override
  String get upgradeToPro => 'Upgrade to Pro';

  @override
  String get logOut => 'Log out';

  @override
  String get changePassword => 'Change password';

  @override
  String get manageDevices => 'Manage devices';

  @override
  String get manageSubscription => 'Manage subscription';

  @override
  String get currentPassword => 'Current password';

  @override
  String get newPassword => 'New password';

  @override
  String get confirmPassword => 'Confirm new password';

  @override
  String get passwordTooShort => 'Password must be at least 8 characters';

  @override
  String get passwordMismatch => 'Passwords do not match';

  @override
  String get changePasswordSuccess => 'Password updated';

  @override
  String get changePasswordFailed => 'Failed to update password';

  @override
  String get devicesTitle => 'Registered devices';

  @override
  String get devicesEmpty => 'No devices registered yet.';

  @override
  String get devicesProLimit => 'Pro plan allows up to 2 devices.';

  @override
  String get deviceCurrentThis => 'This device';

  @override
  String deviceLastUsed(String date) {
    return 'Last used: $date';
  }

  @override
  String get removeDevice => 'Remove';

  @override
  String get removeDeviceConfirm =>
      'Remove this device? It will need to log in again.';

  @override
  String get removeDeviceFailed => 'Could not remove device';

  @override
  String get subscriptionTitle => 'Subscription';

  @override
  String get subscriptionStatus => 'Status';

  @override
  String get subscriptionRenewsAt => 'Renews';

  @override
  String get subscriptionEndsAt => 'Ends';

  @override
  String get subscriptionTrialEndsAt => 'Trial ends';

  @override
  String get subscriptionInactive => 'No active subscription';

  @override
  String get subscriptionCancel => 'Cancel subscription';

  @override
  String get subscriptionCancelConfirm =>
      'Cancel your Pro subscription? You\'ll keep Pro until the current period ends.';

  @override
  String get subscriptionCancelled =>
      'Subscription will end on the renewal date.';

  @override
  String get subscriptionCancelFailed => 'Could not cancel subscription';

  @override
  String get cancel => 'Cancel';

  @override
  String get ok => 'OK';

  @override
  String get confirm => 'Confirm';

  @override
  String get voicePickerTitle => 'Voice';

  @override
  String get voiceDefault => 'Default';

  @override
  String get speedPickerTitle => 'Speech speed';

  @override
  String get speedNormal => 'Normal';

  @override
  String get accessibilityPasteBack => 'Paste reply into other apps';

  @override
  String get accessibilityPasteBackDesc =>
      'Enable TransKey in Accessibility settings to let \"Paste\" write reply into the focused input of any app.';

  @override
  String get accessibilityEnabled => 'Enabled';

  @override
  String get accessibilityDisabled => 'Not enabled — tap to open settings';

  @override
  String get feedbackTitle => 'Send feedback';

  @override
  String get feedbackHint => 'Tell us what you think...';

  @override
  String get feedbackSend => 'Send';

  @override
  String get feedbackThanks => 'Thank you for your feedback!';

  @override
  String get feedbackFailed => 'Failed to send feedback';

  @override
  String get selectLanguage => 'Select Language';

  @override
  String get searchLanguages => 'Search languages...';

  @override
  String get login => 'Login';

  @override
  String get signUp => 'Sign Up';

  @override
  String get logIn => 'Log In';

  @override
  String get createAccount => 'Create Account';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get orDivider => 'or';

  @override
  String get emailHint => 'Email';

  @override
  String get passwordHint => 'Password';

  @override
  String get nameHint => 'Your name';

  @override
  String get proRequired => 'Pro plan required';

  @override
  String get noTextToTranslate => 'Enter some text first';

  @override
  String get errorGeneric => 'Something went wrong';

  @override
  String get planFree => 'Free';

  @override
  String get planPro => 'Pro';

  @override
  String get planMobile => 'Mobile';

  @override
  String get planTrial => 'Trial';

  @override
  String usageRequests(int used, int limit) {
    return '$used/$limit requests';
  }

  @override
  String usageCharacters(int used, int limit) {
    return '$used/$limit chars';
  }
}
