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
  String get delete => 'Delete';

  @override
  String get cancel => 'Cancel';

  @override
  String get ok => 'OK';

  @override
  String get confirm => 'Confirm';

  @override
  String get clear => 'Clear';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get required => 'Required';

  @override
  String get addAction => 'Add';

  @override
  String get saveAction => 'Save';

  @override
  String get next => 'Next';

  @override
  String get skip => 'Skip';

  @override
  String get done => 'Done';

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
  String get sectionSpeech => 'Read aloud';

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
  String get subscriptionAdminGranted =>
      'Your plan was activated by support, not through self-serve billing. Contact us to change or cancel it.';

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
  String get recent => 'Recent';

  @override
  String get allLanguages => 'All languages';

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
  String get nameRequired => 'Name is required';

  @override
  String get emailRequired => 'Email is required';

  @override
  String get emailInvalid => 'Enter a valid email';

  @override
  String get passwordRequired => 'Password is required';

  @override
  String get passwordMinSix => 'At least 6 characters';

  @override
  String get proDeviceLimitError =>
      'Pro account already registered on max devices';

  @override
  String get deviceLimitError => 'Too many accounts on this device';

  @override
  String googleSignInFailed(String error) {
    return 'Google sign-in failed: $error';
  }

  @override
  String get googleNotConfigured =>
      'Google sign-in not configured (missing serverClientId)';

  @override
  String get googleSignInNoIdToken =>
      'Google sign-in returned no idToken — check serverClientId';

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

  @override
  String trialEndsInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'days',
      one: 'day',
    );
    return 'Trial ends in $days $_temp0';
  }

  @override
  String get trialEndsToday => 'Trial ends today';

  @override
  String get trialEndsTomorrow => 'Trial ends tomorrow';

  @override
  String get trialUpgradeNow => 'Upgrade now';

  @override
  String get trialAlreadyUsed => 'You\'ve already used your free trial';

  @override
  String get subscriptionExpiredBanner => 'Your subscription has expired';

  @override
  String get subscriptionExpiredRenew => 'Renew';

  @override
  String subscriptionEndsOn(String date) {
    return 'Ends $date';
  }

  @override
  String get planMobileSubscription => 'Mobile subscription';

  @override
  String get planProSubscription => 'Pro subscription';

  @override
  String get discountFirstMonth => '−50% first month';

  @override
  String get accountBannedTitle => 'Account suspended';

  @override
  String get accountBannedBody =>
      'Your TransKey account has been suspended. Please contact support if you believe this is a mistake.';

  @override
  String get accountBannedContact => 'Contact support';

  @override
  String get accountBannedLogout => 'Log out';

  @override
  String get historyTitle => 'History';

  @override
  String get historySearchHint => 'Search history...';

  @override
  String get historyFilterAll => 'All';

  @override
  String get historyFilterFavorites => '★ Favorites';

  @override
  String get historyFilterLocked => '🔒 Locked';

  @override
  String get historyMenuClearAll => 'Clear all';

  @override
  String get historyMenuKeepFavorites => 'Keep favorites only';

  @override
  String get historyClearDialogTitle => 'Clear history';

  @override
  String get historyClearDialogBody =>
      'Delete all history? Locked entries will be kept.';

  @override
  String get historyKeepFavDialogBody =>
      'Delete all non-favorite entries? Locked entries will be kept.';

  @override
  String get historyDetailSourceLabel => 'Source';

  @override
  String get historyDetailTranslationLabel => 'Translation';

  @override
  String get historyDetailRomanizationLabel => 'Romanization';

  @override
  String get historyDetailFavoriteBadge => '★ Favorite';

  @override
  String get historyDetailLockedBadge => '🔒 Locked';

  @override
  String get historyDetailCopyTranslation => 'Copy\ntranslation';

  @override
  String get historyDetailCopySource => 'Copy\nsource';

  @override
  String get historyDetailUnfavorite => 'Unfavorite';

  @override
  String get historyDetailFavoriteAction => 'Favorite';

  @override
  String get historyDetailUnlock => 'Unlock';

  @override
  String get historyDetailLockAction => 'Lock';

  @override
  String get historyDetailTtsLabel => 'TTS';

  @override
  String glossaryTitle(int count, int max) {
    return 'Glossary ($count/$max)';
  }

  @override
  String get glossarySync => 'Sync';

  @override
  String get glossaryDeleteTitle => 'Delete entry';

  @override
  String glossaryDeleteBody(String source) {
    return 'Delete \"$source\"?';
  }

  @override
  String glossaryLimitReached(int max) {
    return 'Glossary limit reached ($max)';
  }

  @override
  String get glossarySourceTargetRequired => 'Source and target are required';

  @override
  String get glossarySyncFailed => 'Failed to sync glossary';

  @override
  String get glossaryEditTitle => 'Edit entry';

  @override
  String get glossaryAddTitle => 'Add entry';

  @override
  String get glossarySourceLabel => 'Source';

  @override
  String get glossarySourceHint => 'Word or phrase';

  @override
  String get glossaryTargetLabel => 'Target';

  @override
  String get glossaryTargetHint => 'Translation';

  @override
  String get upgradeScreenTitle => 'Upgrade TransKey';

  @override
  String get upgradeChooseYourPlan => 'Choose your plan';

  @override
  String get upgradeUnlockFullPower => 'Unlock the full power of TransKey';

  @override
  String get upgradeCurrentLabel => 'Current';

  @override
  String get upgradePopularBadge => 'Popular';

  @override
  String get upgradeTryFreeDays => 'Try free for 7 days';

  @override
  String upgradeTrialActivated(String info) {
    return 'Trial activated! $info';
  }

  @override
  String get upgradeTrialActivateFailed => 'Failed to activate trial';

  @override
  String get upgradeCheckoutFailed => 'Failed to open checkout';

  @override
  String get upgradeMobileSubtitle => 'All features, mobile only';

  @override
  String get upgradeProSubtitle => 'All features, all platforms';

  @override
  String get upgradeFreeFeat1 => 'Translate';

  @override
  String get upgradeFreeFeat2 => '20 req/day';

  @override
  String get upgradeFreeFeat3 => '2000 chars/day';

  @override
  String get upgradeFreeFeat4 => 'Glossary';

  @override
  String get upgradeMobileFeat1 => 'All features';

  @override
  String get upgradeMobileFeat2 => 'iOS & Android';

  @override
  String get upgradeMobileFeat3 => 'Unlimited';

  @override
  String get upgradeProFeat1 => 'All features';

  @override
  String get upgradeProFeat2 => 'All platforms';

  @override
  String get upgradeProFeat3 => 'Desktop + Mobile';

  @override
  String get upgradeFeatureColumn => 'Feature';

  @override
  String get upgradeMobilePrice => '📱 Mobile · \$3/mo';

  @override
  String get upgradeProPrice => '💻 Pro · \$6/mo';

  @override
  String get upgradeFooterHint =>
      '📱 Mobile: best value if you only use your phone\n💻 Pro: works on both phone and desktop';

  @override
  String get comparisonReplyTranslate => 'Reply translate';

  @override
  String get comparisonMobileApps => '📱 iOS & Android';

  @override
  String get comparisonDesktop => '💻 Desktop';

  @override
  String nudgeUnlock(String feature) {
    return 'Unlock $feature';
  }

  @override
  String get nudgeMobileCopy =>
      'Upgrade to Pro to use this feature\nacross all platforms.';

  @override
  String get nudgeChoosePlan => 'Choose a plan that fits your needs.';

  @override
  String get nudgeMaybeLater => 'Maybe later';

  @override
  String get nudgeMobileTitle => '📱 Mobile';

  @override
  String get nudgeProTitle => '💻 Pro';

  @override
  String get nudgeUpgradeToPro => 'Upgrade to Pro';

  @override
  String get nudgeUpgradeToProSubtitle =>
      'Use on all platforms — desktop + mobile';

  @override
  String get nudgePriceMobile => '\$3/month';

  @override
  String get nudgePriceProMonthly => '\$6/month';

  @override
  String get onboardWelcomeTitle => 'Welcome to TransKey';

  @override
  String get onboardWelcomeSubtitle =>
      'Translate text in real-time across\n20+ languages instantly.';

  @override
  String get onboardChooseTitle => 'Choose Your Language';

  @override
  String get onboardChooseSubtitle =>
      'Pick your preferred target language.\nYou can change it anytime in settings.';

  @override
  String get onboardStartedTitle => 'Get Started';

  @override
  String get onboardStartedSubtitle =>
      'Sign in or create a free account\nto start translating now.';

  @override
  String get onboardGetStarted => 'Get Started';

  @override
  String get setupTitle => 'Setup Keyboard';

  @override
  String get setupOpenSettings => 'Open Settings';

  @override
  String get setupOpenPermissions => 'Open Permissions';

  @override
  String get setupStep1TitleIOS => 'Add TransKey Keyboard';

  @override
  String get setupStep1TitleAndroid => 'Enable Floating Bubble';

  @override
  String get setupStep1DescIOS =>
      'Go to Settings and add TransKey as a custom keyboard so you can translate directly while typing.';

  @override
  String get setupStep1DescAndroid =>
      'Allow TransKey to display over other apps so the floating bubble can appear when you need it.';

  @override
  String get setupStep2Title => 'Allow Full Access';

  @override
  String get setupStep2DescIOS =>
      'Tap TransKey in the keyboard list and enable \"Allow Full Access\". This is needed to connect to the internet for translations.';

  @override
  String get setupStep2DescAndroid =>
      'The overlay permission lets TransKey show a floating bubble on top of other apps for quick translations.';

  @override
  String get setupStep3Title => 'You\'re All Set!';

  @override
  String get setupStep3DescIOS =>
      'When typing in any app, long-press the globe key 🌐 to switch to TransKey. Tap \"Reply\" to translate your message instantly.';

  @override
  String get setupStep3DescAndroid =>
      'Select text in any app and share it to TransKey, or use the floating bubble for quick translations.';

  @override
  String get setupStep4Title => 'Translate from Any App';

  @override
  String get setupStep4DescIOS =>
      'Select any text → tap \"Share\" → choose TransKey. Or copy text and open TransKey — it reads your clipboard automatically.';

  @override
  String get setupStep4DescAndroid =>
      'Select text in any app → tap \"Share\" → choose TransKey. Or use the floating bubble after copying text.';

  @override
  String get setupStep5Title => 'Smart Features';

  @override
  String get setupStep5Desc =>
      'Translate, Reply, Summarize, Explain & Refine — all powered by AI. Pro features are marked with a lock icon.';

  @override
  String get guideTitle => 'How to use';

  @override
  String get guideSubtitle => 'All the ways to capture text for each feature';

  @override
  String get guideIntroTitle =>
      'No special permissions needed to capture text.';

  @override
  String get guideIntroBody =>
      'Every feature reads text only after you do something on purpose — copy text, scan the screen, pick an area, use the system Share button, or tap TransKey from the text-selection menu. The Accessibility setting is only used so the Reply result can paste itself into the chat box you\'re typing in.';

  @override
  String get guideFeatureTranslate => 'Translate';

  @override
  String get guideFeatureTranslateSubtitle =>
      'Source language → target language';

  @override
  String get guideFeatureSummary => 'Summary';

  @override
  String get guideFeatureSummarySubtitle =>
      'Distil long content into a few bullets';

  @override
  String get guideFeatureRefine => 'Refine';

  @override
  String get guideFeatureRefineSubtitle =>
      'Improve grammar / clarity of your own draft';

  @override
  String get guideFeatureExplain => 'Explain';

  @override
  String get guideFeatureExplainSubtitle =>
      'Get a plain-language explanation of difficult text';

  @override
  String get guideFeatureReply => 'Reply';

  @override
  String get guideFeatureReplySubtitle =>
      'Generate a reply suggestion in the target language';

  @override
  String get guideInputCopyTitle => 'Copy text, then tap the bubble';

  @override
  String get guideInputCopyDesc =>
      'Copy any text in any app, then tap the floating bubble and pick the action.';

  @override
  String get guideInputOcrTitle => 'Scan the whole screen';

  @override
  String get guideInputOcrDesc =>
      'Tap the bubble → Scan screen. TransKey takes one screenshot and reads the text on it.';

  @override
  String get guideInputRegionTitle => 'Scan part of the screen';

  @override
  String get guideInputRegionDesc =>
      'Tap the bubble → Scan area. Drag a box around just the part you want translated.';

  @override
  String get guideInputShareTitle => 'From the Share button';

  @override
  String get guideInputShareDesc =>
      'Inside any app, select text → tap Share → choose TransKey.';

  @override
  String guideInputMenuTitle(String feature) {
    return 'From the text-selection menu → TransKey: $feature';
  }

  @override
  String guideInputMenuDesc(String feature) {
    return 'Select text in any app — the popup with Copy/Share appears. Tap ⋮ for more options, then pick TransKey: $feature.';
  }

  @override
  String get guideReplyA11yTitle =>
      'Accessibility — optional, only for auto-paste';

  @override
  String get guideReplyA11yBody =>
      'If Accessibility is turned on for TransKey, your reply is pasted straight into the chat input you\'re typing in. No extra step.\n\nIf you\'d rather not turn it on, the reply is copied for you — just long-press the chat input and tap Paste.';

  @override
  String get appPermissions => 'App permissions';

  @override
  String get permissionsAllSet => 'All set up — tap to review';

  @override
  String get permissionsNeedSetup => 'Tap to grant required permissions';

  @override
  String get setupTransKey => 'Set up TransKey';

  @override
  String get setupTransKeyBody =>
      'Grant the floating-bubble permission to get started. Accessibility is optional and only needed for one-tap Reply paste.';

  @override
  String get permFloatingBubble => 'Floating bubble';

  @override
  String get permFloatingBubbleBody =>
      'Show TransKey over other apps. Required for the bubble to appear.';

  @override
  String get permRestrictedSettings => 'Allow restricted settings';

  @override
  String get permRestrictedSettingsBody =>
      'Android 13+ blocks sideloaded apps from Accessibility by default. Tap ⋮ at the top-right → \"Allow restricted settings\".';

  @override
  String get permAccessibility => 'Accessibility (optional)';

  @override
  String get permAccessibilityBody =>
      'Lets TransKey paste Reply suggestions directly into the focused text field. Skip if you don\'t mind pasting yourself.';

  @override
  String get permEnabled => 'Enabled';

  @override
  String get permEnable => 'Enable';

  @override
  String get permDone => 'Done';

  @override
  String get permOpenAppDetails => 'Open app details';

  @override
  String get permSkipHint =>
      'Accessibility is optional. Without it, Reply suggestions land on your clipboard and you\'ll paste them yourself.';

  @override
  String get permSkipForNow => 'Skip for now';

  @override
  String get permFinishedCheck => 'I\'ve finished — check';

  @override
  String get voiceTooltip => 'Speak to type';

  @override
  String get voiceListening => 'Listening…';

  @override
  String get voicePermDenied => 'Microphone permission denied';

  @override
  String get voiceUnsupported => 'Voice input not available on this device';

  @override
  String get voicePickSourceLang =>
      'Pick a source language first — voice input can\'t auto-detect';

  @override
  String get paywallTitle => 'Daily limit reached';

  @override
  String get paywallBody =>
      'You\'ve used today\'s free quota of 20 requests / 2,000 characters. Watch a short ad to keep going, or upgrade for unlimited use. Your free quota resets at midnight.';

  @override
  String get paywallWatchAdCta => 'Watch ad to continue';

  @override
  String get paywallWatchAdSub =>
      'Earn extra requests and characters each ad. No limit on ads per day.';

  @override
  String get paywallUpgradeCta => 'Upgrade — unlimited, no ads';

  @override
  String get paywallUpgradeSub => 'From \$3/month. Cancel anytime.';

  @override
  String get paywallDismiss => 'Maybe later';

  @override
  String get paywallLoading => 'Loading…';

  @override
  String get paywallAdNotComplete =>
      'Ad wasn\'t completed — try again to earn the reward.';

  @override
  String get paywallCreditFailed =>
      'Couldn\'t credit reward. Try again in a moment.';

  @override
  String get quotaWatchAd => '+ Watch ad';

  @override
  String get quotaRewardGranted => 'Reward credited to today\'s quota';
}
