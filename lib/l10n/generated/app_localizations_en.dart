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
  String get helpImproveApp => 'Help improve the app';

  @override
  String get helpImproveAppHint =>
      'Share anonymous usage info so we can make TransKey better. No personal text or photos are sent.';

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
  String get keyboardSettingsTitle => 'Bubble & Keyboard';

  @override
  String get keyboardSettingsSectionStatus => 'Bubble & Permissions';

  @override
  String get keyboardSettingsSectionBehavior => 'Bubble Behavior';

  @override
  String get imeSectionTitle => 'Keyboard';

  @override
  String get imeKeyboardTitle => 'TransKey Keyboard';

  @override
  String get imeStatusActive => 'Active — typing through TransKey';

  @override
  String get imeStatusEnabledNotSelected =>
      'Enabled. Tap to switch the active keyboard to TransKey.';

  @override
  String get imeStatusNotEnabled =>
      'Not enabled. Tap to turn on in system Settings.';

  @override
  String get bubbleSetup => 'Bubble Setup';

  @override
  String get floatingBubble => 'Floating Bubble';

  @override
  String get bubbleActive => 'Active';

  @override
  String get bubbleInactive => 'Inactive';

  @override
  String get permissionsNeedSetup => 'Tap to grant required permissions';

  @override
  String get sendFeedback => 'Send feedback';

  @override
  String get termsOfService => 'Terms of Service';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get openSourceLicenses => 'Open source licenses';

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
  String get feedbackCatBug => 'Report a bug';

  @override
  String get feedbackCatFeature => 'Feature request';

  @override
  String get feedbackCatOther => 'Other';

  @override
  String get feedbackHintBug =>
      'What did you expect to happen, and what happened instead?';

  @override
  String get feedbackHintFeature => 'What would you like TransKey to do?';

  @override
  String get feedbackHintOther => 'Share your thoughts...';

  @override
  String get feedbackEmailLabel => 'Email (optional, for a reply)';

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
      'Google sign-in isn\'t available right now. Please try another way to sign in.';

  @override
  String get googleSignInNoIdToken =>
      'Google sign-in didn\'t complete. Please try again.';

  @override
  String get proRequired => 'Pro plan required';

  @override
  String get noTextToTranslate => 'Enter some text first';

  @override
  String get errorGeneric => 'Something went wrong';

  @override
  String get errorSessionExpired => 'Session expired — please sign in again';

  @override
  String get errorInvalidCredentials => 'Wrong email or password';

  @override
  String get errorEmailNotVerified =>
      'Please verify your email — check your inbox';

  @override
  String get errorEmailAlreadyExists => 'This email is already registered';

  @override
  String get errorWrongPassword => 'Current password is incorrect';

  @override
  String get errorFeatureRequiresPaid => 'This feature requires a paid plan';

  @override
  String get errorDeviceLimit =>
      'Device limit reached — remove a device or upgrade';

  @override
  String get errorMobilePlanDesktopBlocked =>
      'Mobile plan cannot be used on desktop';

  @override
  String get errorTextTooLong => 'Text too long (max 5000 characters)';

  @override
  String get errorQuotaExceeded =>
      'Daily quota reached — try again tomorrow or upgrade';

  @override
  String get errorRateLimit => 'Too many requests — wait a moment';

  @override
  String get errorMaintenance => 'Service is under maintenance';

  @override
  String get errorNetwork => 'No internet connection';

  @override
  String get glossaryErrSyncFailed =>
      'Couldn\'t sync glossary — check your connection';

  @override
  String glossaryErrLimitReached(int max) {
    return 'Glossary is full (max $max entries)';
  }

  @override
  String get glossaryErrSourceTargetRequired =>
      'Source and target are both required';

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
  String get glossaryNamesLabel => 'Glossary names — tap to insert';

  @override
  String get glossaryIsNameLabel => 'This is a person\'s name';

  @override
  String get glossaryIsNameHint =>
      'Helps voice input recognize the name and keeps it unchanged when translating.';

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
  String nudgePriceMobile(String price) {
    return '$price/month';
  }

  @override
  String nudgePriceProMonthly(String price) {
    return '$price/month';
  }

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
  String get setupTitleAndroid => 'Set up TransKey';

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
  String get setupStep2TitleAndroid => 'Bubble enabled';

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
      'The TransKey button is now on your screen. Copy any text, tap the button, pick an action - you\'ll see the result right there without leaving your app.';

  @override
  String get setupStep4Title => 'Translate from Any App';

  @override
  String get setupStep4DescIOS =>
      'Select any text → tap \"Share\" → choose TransKey. Or copy text and open TransKey — it reads your clipboard automatically.';

  @override
  String get setupStep4DescAndroid =>
      'Copy text in any app → tap the TransKey button → choose Translate, Reply, or another action → tap anywhere to close when done.';

  @override
  String get setupStep5Title => 'Smart Features';

  @override
  String get setupStep5Desc =>
      'Translate, Reply, Summarize, Explain & Refine. Pro features are marked with a lock icon.';

  @override
  String get guideTitle => 'How to use';

  @override
  String get guidePlanCompareTitle => 'Features by plan';

  @override
  String get guidePlanFreeLabel => 'Free';

  @override
  String get guidePlanPaidLabel => 'Paid';

  @override
  String get guidePlanFreeItems => 'Translate\nWord list';

  @override
  String get guidePlanPaidItems =>
      'Camera scan\nScreen scan\nSummary\nRefine\nExplain\nReply\nTone selection\nPhonetics';

  @override
  String get guideSectionFree => 'Free features';

  @override
  String get guideSectionPaid => 'Paid features';

  @override
  String get guideFreeBadge => 'Free';

  @override
  String get guidePaidBadge => 'Paid';

  @override
  String get guideInputPaidBadge => 'Paid';

  @override
  String get guideFeatureGlossary => 'Word list';

  @override
  String get guideFeatureGlossarySubtitle =>
      'Save custom word translations that TransKey always uses first';

  @override
  String get guideInputGlossaryTitle => 'From the Word list tab';

  @override
  String get guideInputGlossaryDesc =>
      'Open the Word list tab and add word pairs. TransKey will use your custom translations first when it sees those words.';

  @override
  String get guideFeatureCamera => 'Camera scan';

  @override
  String get guideFeatureCameraSubtitle =>
      'Photograph text to translate - signs, menus, books';

  @override
  String get guideInputCameraTitle => 'Tap the camera button';

  @override
  String get guideInputCameraDesc =>
      'Tap the camera icon at the top of the main screen. Point your phone at any text, take a photo, and see the translation appear on the image.';

  @override
  String get guideInputVoiceTitle => 'Speak to enter text';

  @override
  String get guideInputVoiceDesc =>
      'On the main screen, tap the microphone button and speak. Your words are converted to text and translated automatically.';

  @override
  String get guideSubtitle => 'All the ways to capture text for each feature';

  @override
  String get guideIntroTitle =>
      'No special permissions needed to capture text.';

  @override
  String get guideIntroBody =>
      'Every feature reads text only after you do something on purpose — copy text, scan the screen, pick an area, use the system Share button, or tap TransKey from the text-selection menu.';

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
  String get guideFeatureReplySubtitle => 'Get a reply suggestion to send back';

  @override
  String get guideInputCopyTitle => 'Copy text, then tap the button';

  @override
  String get guideInputCopyDesc =>
      'Copy any text in any app, then tap the TransKey button and pick what you want to do.';

  @override
  String get guideInputOcrTitle => 'Scan the whole screen';

  @override
  String get guideInputOcrDesc =>
      'Tap the button → Scan screen. TransKey captures a screenshot and reads the text.';

  @override
  String get guideInputRegionTitle => 'Scan part of the screen';

  @override
  String get guideInputRegionDesc =>
      'Tap the button → Scan area. Draw a box around the part you want translated.';

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
  String get voiceTooltip => 'Speak to type';

  @override
  String get voiceListening => 'Listening…';

  @override
  String get voiceNeedsLang => 'Set a specific source language to use voice';

  @override
  String get voicePermDenied => 'Microphone permission denied';

  @override
  String get voiceUnsupported => 'Voice input not available on this device';

  @override
  String get voicePickSourceLang =>
      'Voice needs a specific language. Pick a source language, then tap the mic again.';

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
  String paywallUpgradeSub(String price) {
    return 'From $price/month. Cancel anytime.';
  }

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

  @override
  String get historyEmpty => 'No translation history yet';

  @override
  String get glossaryEmpty => 'Glossary is empty';

  @override
  String get glossaryEmptyAddCta => 'Add entry';

  @override
  String get captureKeepaliveTitle => 'Quick re-scan window';

  @override
  String get captureKeepaliveHint => 'double-tap bubble = re-scan';

  @override
  String get captureKeepaliveExplain =>
      'After a screen scan, keep screen-capture permission ready so you can double-tap the bubble (or pick Lens again) without the system permission prompt. Longer windows save taps but keep the casting indicator visible and slightly warm the device.';

  @override
  String get bubbleIdleTitle => 'Bubble auto-stop';

  @override
  String get bubbleIdleExplain =>
      'Stop the floating bubble when you haven\'t used it for a while. Saves battery on long idle.';

  @override
  String get bubbleIdleOff => 'Never';

  @override
  String bubbleIdleMinutes(int count) {
    return '$count min';
  }

  @override
  String get captureKeepaliveOff => 'Off';

  @override
  String get captureKeepaliveOffHint =>
      'Each scan asks for permission again. Best for privacy / battery.';

  @override
  String get captureKeepaliveDefaultHint =>
      'Recommended — balances re-scan speed with battery.';

  @override
  String get captureKeepaliveShortHint =>
      'Less casting time, but more frequent permission prompts.';

  @override
  String get captureKeepaliveLongHint =>
      'Maximum re-scan speed. Casting indicator stays on longer.';

  @override
  String captureKeepaliveMinutes(int count) {
    return '$count min';
  }

  @override
  String get cameraTitle => 'Camera';

  @override
  String get cameraCapture => 'Capture';

  @override
  String get cameraRetake => 'Retake';

  @override
  String get cameraCopyAll => 'Copy all';

  @override
  String get cameraListView => 'List';

  @override
  String get cameraNoText => 'No text detected. Try again.';

  @override
  String get cameraTapShowTranslations => 'Tap to show translations';

  @override
  String get cameraLowQuality => 'Low quality';

  @override
  String get cameraConfidenceReliable => 'Reliable';

  @override
  String get cameraConfidenceCaution => 'Verify';

  @override
  String get cameraConfidenceUnreliable => 'Unreliable';

  @override
  String get cameraHoldSteady => 'Hold steady';

  @override
  String get cameraPausedTitle => 'Camera Paused';

  @override
  String get cameraPausedTapToResume => 'Tap to resume';

  @override
  String get cameraWaitFocus => 'Wait for focus, hold steady';

  @override
  String get cameraCopyTranslation => 'Copy translation';

  @override
  String get cameraCopyOriginal => 'Copy original';

  @override
  String get cameraRetryBlock => 'Translate again';

  @override
  String get cameraSaveBlock => 'Save to phrasebook';

  @override
  String get cameraSavingPhrasebook => 'Saving…';

  @override
  String get cameraBlockRetrying => 'Translating again…';

  @override
  String cameraBatchProgress(int current, int total) {
    return 'Translating $current of $total…';
  }

  @override
  String get cameraSaveNoteLabel => 'Add a note (optional)';

  @override
  String get cameraSaveNoteHint => 'e.g. near the hotel, very spicy';

  @override
  String get cameraSaveSkipNote => 'Skip';

  @override
  String get cameraCopyLineHeader => 'COPY LINE';

  @override
  String get cameraSignStoreName => 'Store name';

  @override
  String get cameraSignPhone => 'Phone number';

  @override
  String get cameraSignAddress => 'Address';

  @override
  String get cameraShare => 'Share';

  @override
  String get cameraShareSubject => 'Translated by TransKey';

  @override
  String get cameraShareFailed => 'Couldn\'t share. Try again.';

  @override
  String get cameraTranslating => 'Translating...';

  @override
  String get cameraTranslate => 'Translate';

  @override
  String get cameraPermission =>
      'Camera permission is required to use this feature.';

  @override
  String get cameraSettingsTitle => 'Camera settings';

  @override
  String get cameraSettingsReset => 'Reset';

  @override
  String get cameraSettingsConfidence => 'Hide unclear text';

  @override
  String get cameraSettingsConfidenceHint =>
      'Hide text the camera reads unclearly. Higher = stricter — cleaner results, but may skip faint text.';

  @override
  String get cameraOriginalLabel => 'Original';

  @override
  String get cameraSettingsHideLow => 'Hide low-quality blocks';

  @override
  String get cameraSettingsHideLowHint =>
      'Also hide blocks above the threshold but below the warning level. Turn on for clean documents.';

  @override
  String get cameraSettingsShowOriginal => 'Show original text';

  @override
  String get cameraSettingsShowOriginalHint =>
      'Always show the source text under each translation card.';

  @override
  String get cameraSettingsOpacity => 'Overlay opacity';

  @override
  String get cameraSettingsOpacityHint =>
      'Card background transparency. Lower = see more of the photo behind.';

  @override
  String get cameraSettingsFontScale => 'Font size';

  @override
  String get cameraSettingsFontScaleHint =>
      'Make translation text bigger. Text may spill outside the original bubble.';

  @override
  String get cameraSettingsPrimaryColor => 'Single overlay color';

  @override
  String get cameraSettingsPrimaryColorHint =>
      'Use one app color for all cards instead of matching each card to the photo.';

  @override
  String get cameraSceneAuto => 'Auto';

  @override
  String get cameraSceneDocument => 'Document';

  @override
  String get cameraSceneMenu => 'Menu';

  @override
  String get cameraSceneSign => 'Sign';

  @override
  String get cameraSceneScreenshot => 'Screenshot';

  @override
  String get cameraSceneManga => 'Comic';

  @override
  String get cameraSceneOther => 'Other';

  @override
  String get cameraScenePickerTitle => 'What do you want to capture?';

  @override
  String get cameraScenePickerHint =>
      'Pick a mode first for more accurate results. You can still switch from the chip bar below.';

  @override
  String get cameraSceneAutoDesc => 'Automatically picks the best mode';

  @override
  String get cameraSceneMangaDesc =>
      'Manga / manhwa / manhua / comic - one card per speech balloon';

  @override
  String get cameraSceneMenuDesc =>
      'Restaurant menu - skips prices when obvious';

  @override
  String get cameraSceneSignDesc => 'Storefronts, signboards, banners';

  @override
  String get cameraSceneDocumentDesc => 'Official documents, books, papers';

  @override
  String get cameraSceneScreenshotDesc => 'App or website screenshot';

  @override
  String get mangaNoDialogue => 'No dialogue found';

  @override
  String get splittingItems => 'Splitting items…';

  @override
  String cameraDetected(String scene) {
    return 'Detected: $scene';
  }

  @override
  String get cameraWhatIsThis => 'What is this?';

  @override
  String get cameraWhatIsThisHint => 'Tap any text in the preview to ask';

  @override
  String get cameraExplainTitle => 'What is this?';

  @override
  String get cameraEditTextTitle => 'Edit text';

  @override
  String get cameraReExplain => 'Re-explain';

  @override
  String get cameraExplainEmpty => 'No explanation available.';

  @override
  String get cameraExplainStaleBadge => 'Saved offline — may be outdated';

  @override
  String get cameraExplainError => 'Couldn\'t fetch explanation. Try again.';

  @override
  String get cameraResultExplainHint => 'Long-press a card to ask';

  @override
  String get cameraExplainDisclaimer =>
      'For reference only — actual meaning may differ';

  @override
  String get phrasebookTitle => 'Phrasebook';

  @override
  String get phrasebookEmpty =>
      'Your phrasebook is empty. Use the camera to identify text, then tap Save.';

  @override
  String get phrasebookSave => 'Save';

  @override
  String get phrasebookSaved => 'Saved';

  @override
  String get phrasebookSaveFailed => 'Couldn\'t save. Try again.';

  @override
  String get phrasebookTitleTooLong =>
      'Title too long (max 1000 characters). Shorten and try again.';

  @override
  String get phrasebookDelete => 'Delete';

  @override
  String get phrasebookDeleteConfirm => 'Remove this from your phrasebook?';

  @override
  String get phrasebookDeleted => 'Removed';

  @override
  String get phrasebookNote => 'Note';

  @override
  String get phrasebookNoteHint => 'e.g. ordered at ... — too spicy';

  @override
  String get phrasebookNoteSave => 'Save note';

  @override
  String get phrasebookCopy => 'Copy';

  @override
  String get phrasebookViewAll => 'View phrasebook';

  @override
  String get phrasebookCategoryAll => 'All';

  @override
  String get phrasebookCategoryMenu => 'Menu';

  @override
  String get phrasebookCategoryPlace => 'Place';

  @override
  String get phrasebookCategoryDocument => 'Document';

  @override
  String get phrasebookCategoryOther => 'Other';

  @override
  String get phrasebookCategoryChange => 'Change category';

  @override
  String get cameraTipsTitle => 'Camera tips';

  @override
  String get cameraTipsGotIt => 'Got it';

  @override
  String get cameraTip1Title => 'Pick the right mode';

  @override
  String get cameraTip1Body =>
      'Pick what you\'re scanning for the best result: a menu, a shop sign, a document — or Auto for anything.';

  @override
  String get cameraTip2Title => 'Choose your languages';

  @override
  String get cameraTip2Body =>
      'Set the language you\'re reading and the one to translate into (top-left). If a sign or text doesn\'t come out right, choose the reading language instead of leaving it on Auto.';

  @override
  String get cameraTip3Title => 'Ask \"What is this?\"';

  @override
  String get cameraTip3Body =>
      'Hold a result to learn what a dish or place is — and hear how to say it out loud.';

  @override
  String get cameraTip4Title => 'Drag to remove';

  @override
  String get cameraTip4Body =>
      'Drag a result card to the trash zone at the bottom to remove blocks you don\'t need.';

  @override
  String get cameraTip5Title => 'Scan a saved photo';

  @override
  String get cameraTip5Body =>
      'Tap the gallery icon next to the shutter to translate a photo already on your phone.';

  @override
  String get upgradePurchaseSuccess =>
      'Subscription activated. Enjoy your new plan!';

  @override
  String get upgradeRestoreSuccess =>
      'Purchases restored — your subscription is active.';

  @override
  String get upgradeRestoreNothing => 'No previous purchases found to restore.';

  @override
  String get upgradePickProPeriod => 'Choose your Pro plan';

  @override
  String get upgradePickMobilePeriod => 'Choose your Mobile plan';

  @override
  String get upgradeRestoreButton => 'Restore purchases';

  @override
  String get homeTagline => 'Translate · Summarize · Explain';

  @override
  String get historyEmptyTagline => 'Your translations will appear here';

  @override
  String get glossaryEmptyTagline =>
      'Save terms you use often for accurate names';

  @override
  String get quotaTodayUsage => 'Today\'s usage';

  @override
  String get quotaWallTitle => 'You\'ve used today\'s quota';

  @override
  String get quotaWallBody =>
      'Watch a short ad to get more translations now, or upgrade for unlimited use.';

  @override
  String get quotaWallWatchAdCta => 'Watch ad for more translations';

  @override
  String get quotaWallUpgradeCta => 'Upgrade for unlimited';

  @override
  String get quotaWallCloseCta => 'Maybe later';

  @override
  String get guideScreenshotTipTitle => 'Screenshot without the bubble';

  @override
  String get guideScreenshotTipBody =>
      'Tap the bubble to open the menu, then tap the camera icon in the bottom-right corner. The bubble hides for a few seconds so you can take a clean screenshot, then comes back on its own.';

  @override
  String get accountDeleteButton => 'Delete account';

  @override
  String get accountDeleteTitle => 'Delete account?';

  @override
  String get accountDeleteWarning =>
      'Your account and all data linked to it (history, phrasebook, devices) will be permanently deleted. This cannot be undone. If you have an active subscription, cancel it in the app store first.';

  @override
  String get accountDeleteConfirm => 'Delete permanently';

  @override
  String get accountDeleteFailed =>
      'Could not delete the account. Please try again.';

  @override
  String get continueWithApple => 'Continue with Apple';

  @override
  String get appleSignInFailed => 'Apple sign-in failed. Please try again.';

  @override
  String get pasteTranslate => 'Paste & translate';
}
