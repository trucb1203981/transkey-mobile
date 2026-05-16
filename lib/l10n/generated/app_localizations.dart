import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_vi.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('ja'),
    Locale('ko'),
    Locale('vi'),
    Locale('zh')
  ];

  /// No description provided for @translate.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get translate;

  /// No description provided for @summarize.
  ///
  /// In en, this message translates to:
  /// **'Summarize'**
  String get summarize;

  /// No description provided for @explain.
  ///
  /// In en, this message translates to:
  /// **'Explain'**
  String get explain;

  /// No description provided for @refine.
  ///
  /// In en, this message translates to:
  /// **'Refine'**
  String get refine;

  /// No description provided for @reply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get reply;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @glossary.
  ///
  /// In en, this message translates to:
  /// **'Glossary'**
  String get glossary;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @suggestions.
  ///
  /// In en, this message translates to:
  /// **'Suggestions'**
  String get suggestions;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @addAction.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addAction;

  /// No description provided for @saveAction.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveAction;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @hintEnterText.
  ///
  /// In en, this message translates to:
  /// **'Enter text to translate...'**
  String get hintEnterText;

  /// No description provided for @detectedLang.
  ///
  /// In en, this message translates to:
  /// **'Detected: {lang}'**
  String detectedLang(String lang);

  /// No description provided for @autoDetect.
  ///
  /// In en, this message translates to:
  /// **'Auto Detect'**
  String get autoDetect;

  /// No description provided for @sourceLang.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get sourceLang;

  /// No description provided for @targetLang.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get targetLang;

  /// No description provided for @swapLanguages.
  ///
  /// In en, this message translates to:
  /// **'Swap languages'**
  String get swapLanguages;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @sectionLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get sectionLanguage;

  /// No description provided for @sectionTranslation.
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get sectionTranslation;

  /// No description provided for @sectionAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get sectionAdvanced;

  /// No description provided for @sectionOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get sectionOther;

  /// No description provided for @sectionSpeech.
  ///
  /// In en, this message translates to:
  /// **'Read aloud'**
  String get sectionSpeech;

  /// No description provided for @targetLanguage.
  ///
  /// In en, this message translates to:
  /// **'Target language'**
  String get targetLanguage;

  /// No description provided for @sourceLanguage.
  ///
  /// In en, this message translates to:
  /// **'Source language'**
  String get sourceLanguage;

  /// No description provided for @appLanguage.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get appLanguage;

  /// No description provided for @saveHistory.
  ///
  /// In en, this message translates to:
  /// **'Save history'**
  String get saveHistory;

  /// No description provided for @romanization.
  ///
  /// In en, this message translates to:
  /// **'Romanization'**
  String get romanization;

  /// No description provided for @replySuggestions.
  ///
  /// In en, this message translates to:
  /// **'Reply suggestions'**
  String get replySuggestions;

  /// No description provided for @toneOverride.
  ///
  /// In en, this message translates to:
  /// **'Translation tone'**
  String get toneOverride;

  /// No description provided for @replyToneOverride.
  ///
  /// In en, this message translates to:
  /// **'Reply tone'**
  String get replyToneOverride;

  /// No description provided for @replyLanguage.
  ///
  /// In en, this message translates to:
  /// **'Reply language'**
  String get replyLanguage;

  /// No description provided for @replyLanguageFromConversation.
  ///
  /// In en, this message translates to:
  /// **'From conversation'**
  String get replyLanguageFromConversation;

  /// No description provided for @autoCloseResult.
  ///
  /// In en, this message translates to:
  /// **'Auto-close result'**
  String get autoCloseResult;

  /// No description provided for @autoCloseSeconds.
  ///
  /// In en, this message translates to:
  /// **'Auto-close (seconds)'**
  String get autoCloseSeconds;

  /// No description provided for @autoCloseUnit.
  ///
  /// In en, this message translates to:
  /// **'seconds'**
  String get autoCloseUnit;

  /// No description provided for @autoCloseDisabled.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get autoCloseDisabled;

  /// No description provided for @toneAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get toneAuto;

  /// No description provided for @toneBusiness.
  ///
  /// In en, this message translates to:
  /// **'Business'**
  String get toneBusiness;

  /// No description provided for @toneCasual.
  ///
  /// In en, this message translates to:
  /// **'Casual'**
  String get toneCasual;

  /// No description provided for @toneFormal.
  ///
  /// In en, this message translates to:
  /// **'Formal'**
  String get toneFormal;

  /// No description provided for @tonePolite.
  ///
  /// In en, this message translates to:
  /// **'Polite'**
  String get tonePolite;

  /// No description provided for @toneTechnical.
  ///
  /// In en, this message translates to:
  /// **'Technical'**
  String get toneTechnical;

  /// No description provided for @toneNeutral.
  ///
  /// In en, this message translates to:
  /// **'Neutral'**
  String get toneNeutral;

  /// No description provided for @toneReplySameAsTranslate.
  ///
  /// In en, this message translates to:
  /// **'Same as translate'**
  String get toneReplySameAsTranslate;

  /// No description provided for @popupTo.
  ///
  /// In en, this message translates to:
  /// **'To:'**
  String get popupTo;

  /// No description provided for @tabTranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get tabTranslate;

  /// No description provided for @tabReply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get tabReply;

  /// No description provided for @tabSummarize.
  ///
  /// In en, this message translates to:
  /// **'Summarize'**
  String get tabSummarize;

  /// No description provided for @tabExplain.
  ///
  /// In en, this message translates to:
  /// **'Explain'**
  String get tabExplain;

  /// No description provided for @tabRefine.
  ///
  /// In en, this message translates to:
  /// **'Refine'**
  String get tabRefine;

  /// No description provided for @keyboardSetup.
  ///
  /// In en, this message translates to:
  /// **'Keyboard Setup'**
  String get keyboardSetup;

  /// No description provided for @bubbleSetup.
  ///
  /// In en, this message translates to:
  /// **'Bubble Setup'**
  String get bubbleSetup;

  /// No description provided for @floatingBubble.
  ///
  /// In en, this message translates to:
  /// **'Floating Bubble'**
  String get floatingBubble;

  /// No description provided for @bubbleActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get bubbleActive;

  /// No description provided for @bubbleInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get bubbleInactive;

  /// No description provided for @sendFeedback.
  ///
  /// In en, this message translates to:
  /// **'Send feedback'**
  String get sendFeedback;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfService;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @upgrade.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get upgrade;

  /// No description provided for @upgradeToPro.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Pro'**
  String get upgradeToPro;

  /// No description provided for @logOut.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logOut;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePassword;

  /// No description provided for @manageDevices.
  ///
  /// In en, this message translates to:
  /// **'Manage devices'**
  String get manageDevices;

  /// No description provided for @manageSubscription.
  ///
  /// In en, this message translates to:
  /// **'Manage subscription'**
  String get manageSubscription;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get currentPassword;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPassword;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get confirmPassword;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get passwordTooShort;

  /// No description provided for @passwordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordMismatch;

  /// No description provided for @changePasswordSuccess.
  ///
  /// In en, this message translates to:
  /// **'Password updated'**
  String get changePasswordSuccess;

  /// No description provided for @changePasswordFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update password'**
  String get changePasswordFailed;

  /// No description provided for @devicesTitle.
  ///
  /// In en, this message translates to:
  /// **'Registered devices'**
  String get devicesTitle;

  /// No description provided for @devicesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No devices registered yet.'**
  String get devicesEmpty;

  /// No description provided for @devicesProLimit.
  ///
  /// In en, this message translates to:
  /// **'Pro plan allows up to 2 devices.'**
  String get devicesProLimit;

  /// No description provided for @deviceCurrentThis.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get deviceCurrentThis;

  /// No description provided for @deviceLastUsed.
  ///
  /// In en, this message translates to:
  /// **'Last used: {date}'**
  String deviceLastUsed(String date);

  /// No description provided for @removeDevice.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeDevice;

  /// No description provided for @removeDeviceConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove this device? It will need to log in again.'**
  String get removeDeviceConfirm;

  /// No description provided for @removeDeviceFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not remove device'**
  String get removeDeviceFailed;

  /// No description provided for @subscriptionTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get subscriptionTitle;

  /// No description provided for @subscriptionStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get subscriptionStatus;

  /// No description provided for @subscriptionRenewsAt.
  ///
  /// In en, this message translates to:
  /// **'Renews'**
  String get subscriptionRenewsAt;

  /// No description provided for @subscriptionEndsAt.
  ///
  /// In en, this message translates to:
  /// **'Ends'**
  String get subscriptionEndsAt;

  /// No description provided for @subscriptionTrialEndsAt.
  ///
  /// In en, this message translates to:
  /// **'Trial ends'**
  String get subscriptionTrialEndsAt;

  /// No description provided for @subscriptionInactive.
  ///
  /// In en, this message translates to:
  /// **'No active subscription'**
  String get subscriptionInactive;

  /// No description provided for @subscriptionAdminGranted.
  ///
  /// In en, this message translates to:
  /// **'Your plan was activated by support, not through self-serve billing. Contact us to change or cancel it.'**
  String get subscriptionAdminGranted;

  /// No description provided for @subscriptionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel subscription'**
  String get subscriptionCancel;

  /// No description provided for @subscriptionCancelConfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel your Pro subscription? You\'ll keep Pro until the current period ends.'**
  String get subscriptionCancelConfirm;

  /// No description provided for @subscriptionCancelled.
  ///
  /// In en, this message translates to:
  /// **'Subscription will end on the renewal date.'**
  String get subscriptionCancelled;

  /// No description provided for @subscriptionCancelFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not cancel subscription'**
  String get subscriptionCancelFailed;

  /// No description provided for @voicePickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get voicePickerTitle;

  /// No description provided for @voiceDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get voiceDefault;

  /// No description provided for @speedPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Speech speed'**
  String get speedPickerTitle;

  /// No description provided for @speedNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get speedNormal;

  /// No description provided for @accessibilityPasteBack.
  ///
  /// In en, this message translates to:
  /// **'Paste reply into other apps'**
  String get accessibilityPasteBack;

  /// No description provided for @accessibilityPasteBackDesc.
  ///
  /// In en, this message translates to:
  /// **'Enable TransKey in Accessibility settings to let \"Paste\" write reply into the focused input of any app.'**
  String get accessibilityPasteBackDesc;

  /// No description provided for @accessibilityEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get accessibilityEnabled;

  /// No description provided for @accessibilityDisabled.
  ///
  /// In en, this message translates to:
  /// **'Not enabled — tap to open settings'**
  String get accessibilityDisabled;

  /// No description provided for @feedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Send feedback'**
  String get feedbackTitle;

  /// No description provided for @feedbackHint.
  ///
  /// In en, this message translates to:
  /// **'Tell us what you think...'**
  String get feedbackHint;

  /// No description provided for @feedbackSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get feedbackSend;

  /// No description provided for @feedbackThanks.
  ///
  /// In en, this message translates to:
  /// **'Thank you for your feedback!'**
  String get feedbackThanks;

  /// No description provided for @feedbackFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to send feedback'**
  String get feedbackFailed;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguage;

  /// No description provided for @searchLanguages.
  ///
  /// In en, this message translates to:
  /// **'Search languages...'**
  String get searchLanguages;

  /// No description provided for @recent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recent;

  /// No description provided for @allLanguages.
  ///
  /// In en, this message translates to:
  /// **'All languages'**
  String get allLanguages;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signUp;

  /// No description provided for @logIn.
  ///
  /// In en, this message translates to:
  /// **'Log In'**
  String get logIn;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get createAccount;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @orDivider.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get orDivider;

  /// No description provided for @emailHint.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailHint;

  /// No description provided for @passwordHint.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordHint;

  /// No description provided for @nameHint.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get nameHint;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get nameRequired;

  /// No description provided for @emailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get emailRequired;

  /// No description provided for @emailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get emailInvalid;

  /// No description provided for @passwordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get passwordRequired;

  /// No description provided for @passwordMinSix.
  ///
  /// In en, this message translates to:
  /// **'At least 6 characters'**
  String get passwordMinSix;

  /// No description provided for @proDeviceLimitError.
  ///
  /// In en, this message translates to:
  /// **'Pro account already registered on max devices'**
  String get proDeviceLimitError;

  /// No description provided for @deviceLimitError.
  ///
  /// In en, this message translates to:
  /// **'Too many accounts on this device'**
  String get deviceLimitError;

  /// No description provided for @googleSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in failed: {error}'**
  String googleSignInFailed(String error);

  /// No description provided for @googleNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in not configured (missing serverClientId)'**
  String get googleNotConfigured;

  /// No description provided for @googleSignInNoIdToken.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in returned no idToken — check serverClientId'**
  String get googleSignInNoIdToken;

  /// No description provided for @proRequired.
  ///
  /// In en, this message translates to:
  /// **'Pro plan required'**
  String get proRequired;

  /// No description provided for @noTextToTranslate.
  ///
  /// In en, this message translates to:
  /// **'Enter some text first'**
  String get noTextToTranslate;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorGeneric;

  /// No description provided for @planFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get planFree;

  /// No description provided for @planPro.
  ///
  /// In en, this message translates to:
  /// **'Pro'**
  String get planPro;

  /// No description provided for @planMobile.
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get planMobile;

  /// No description provided for @planTrial.
  ///
  /// In en, this message translates to:
  /// **'Trial'**
  String get planTrial;

  /// No description provided for @usageRequests.
  ///
  /// In en, this message translates to:
  /// **'{used}/{limit} requests'**
  String usageRequests(int used, int limit);

  /// No description provided for @usageCharacters.
  ///
  /// In en, this message translates to:
  /// **'{used}/{limit} chars'**
  String usageCharacters(int used, int limit);

  /// No description provided for @trialEndsInDays.
  ///
  /// In en, this message translates to:
  /// **'Trial ends in {days} {days, plural, one{day} other{days}}'**
  String trialEndsInDays(int days);

  /// No description provided for @trialEndsToday.
  ///
  /// In en, this message translates to:
  /// **'Trial ends today'**
  String get trialEndsToday;

  /// No description provided for @trialEndsTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Trial ends tomorrow'**
  String get trialEndsTomorrow;

  /// No description provided for @trialUpgradeNow.
  ///
  /// In en, this message translates to:
  /// **'Upgrade now'**
  String get trialUpgradeNow;

  /// No description provided for @trialAlreadyUsed.
  ///
  /// In en, this message translates to:
  /// **'You\'ve already used your free trial'**
  String get trialAlreadyUsed;

  /// No description provided for @subscriptionExpiredBanner.
  ///
  /// In en, this message translates to:
  /// **'Your subscription has expired'**
  String get subscriptionExpiredBanner;

  /// No description provided for @subscriptionExpiredRenew.
  ///
  /// In en, this message translates to:
  /// **'Renew'**
  String get subscriptionExpiredRenew;

  /// No description provided for @subscriptionEndsOn.
  ///
  /// In en, this message translates to:
  /// **'Ends {date}'**
  String subscriptionEndsOn(String date);

  /// No description provided for @planMobileSubscription.
  ///
  /// In en, this message translates to:
  /// **'Mobile subscription'**
  String get planMobileSubscription;

  /// No description provided for @planProSubscription.
  ///
  /// In en, this message translates to:
  /// **'Pro subscription'**
  String get planProSubscription;

  /// No description provided for @discountFirstMonth.
  ///
  /// In en, this message translates to:
  /// **'−50% first month'**
  String get discountFirstMonth;

  /// No description provided for @accountBannedTitle.
  ///
  /// In en, this message translates to:
  /// **'Account suspended'**
  String get accountBannedTitle;

  /// No description provided for @accountBannedBody.
  ///
  /// In en, this message translates to:
  /// **'Your TransKey account has been suspended. Please contact support if you believe this is a mistake.'**
  String get accountBannedBody;

  /// No description provided for @accountBannedContact.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get accountBannedContact;

  /// No description provided for @accountBannedLogout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get accountBannedLogout;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// No description provided for @historySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search history...'**
  String get historySearchHint;

  /// No description provided for @historyFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get historyFilterAll;

  /// No description provided for @historyFilterFavorites.
  ///
  /// In en, this message translates to:
  /// **'★ Favorites'**
  String get historyFilterFavorites;

  /// No description provided for @historyFilterLocked.
  ///
  /// In en, this message translates to:
  /// **'🔒 Locked'**
  String get historyFilterLocked;

  /// No description provided for @historyMenuClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get historyMenuClearAll;

  /// No description provided for @historyMenuKeepFavorites.
  ///
  /// In en, this message translates to:
  /// **'Keep favorites only'**
  String get historyMenuKeepFavorites;

  /// No description provided for @historyClearDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get historyClearDialogTitle;

  /// No description provided for @historyClearDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Delete all history? Locked entries will be kept.'**
  String get historyClearDialogBody;

  /// No description provided for @historyKeepFavDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Delete all non-favorite entries? Locked entries will be kept.'**
  String get historyKeepFavDialogBody;

  /// No description provided for @historyDetailSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get historyDetailSourceLabel;

  /// No description provided for @historyDetailTranslationLabel.
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get historyDetailTranslationLabel;

  /// No description provided for @historyDetailRomanizationLabel.
  ///
  /// In en, this message translates to:
  /// **'Romanization'**
  String get historyDetailRomanizationLabel;

  /// No description provided for @historyDetailFavoriteBadge.
  ///
  /// In en, this message translates to:
  /// **'★ Favorite'**
  String get historyDetailFavoriteBadge;

  /// No description provided for @historyDetailLockedBadge.
  ///
  /// In en, this message translates to:
  /// **'🔒 Locked'**
  String get historyDetailLockedBadge;

  /// No description provided for @historyDetailCopyTranslation.
  ///
  /// In en, this message translates to:
  /// **'Copy\ntranslation'**
  String get historyDetailCopyTranslation;

  /// No description provided for @historyDetailCopySource.
  ///
  /// In en, this message translates to:
  /// **'Copy\nsource'**
  String get historyDetailCopySource;

  /// No description provided for @historyDetailUnfavorite.
  ///
  /// In en, this message translates to:
  /// **'Unfavorite'**
  String get historyDetailUnfavorite;

  /// No description provided for @historyDetailFavoriteAction.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get historyDetailFavoriteAction;

  /// No description provided for @historyDetailUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get historyDetailUnlock;

  /// No description provided for @historyDetailLockAction.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get historyDetailLockAction;

  /// No description provided for @historyDetailTtsLabel.
  ///
  /// In en, this message translates to:
  /// **'TTS'**
  String get historyDetailTtsLabel;

  /// No description provided for @glossaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Glossary ({count}/{max})'**
  String glossaryTitle(int count, int max);

  /// No description provided for @glossarySync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get glossarySync;

  /// No description provided for @glossaryDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete entry'**
  String get glossaryDeleteTitle;

  /// No description provided for @glossaryDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{source}\"?'**
  String glossaryDeleteBody(String source);

  /// No description provided for @glossaryLimitReached.
  ///
  /// In en, this message translates to:
  /// **'Glossary limit reached ({max})'**
  String glossaryLimitReached(int max);

  /// No description provided for @glossarySourceTargetRequired.
  ///
  /// In en, this message translates to:
  /// **'Source and target are required'**
  String get glossarySourceTargetRequired;

  /// No description provided for @glossarySyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to sync glossary'**
  String get glossarySyncFailed;

  /// No description provided for @glossaryEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit entry'**
  String get glossaryEditTitle;

  /// No description provided for @glossaryAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add entry'**
  String get glossaryAddTitle;

  /// No description provided for @glossarySourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get glossarySourceLabel;

  /// No description provided for @glossarySourceHint.
  ///
  /// In en, this message translates to:
  /// **'Word or phrase'**
  String get glossarySourceHint;

  /// No description provided for @glossaryTargetLabel.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get glossaryTargetLabel;

  /// No description provided for @glossaryTargetHint.
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get glossaryTargetHint;

  /// No description provided for @upgradeScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Upgrade TransKey'**
  String get upgradeScreenTitle;

  /// No description provided for @upgradeChooseYourPlan.
  ///
  /// In en, this message translates to:
  /// **'Choose your plan'**
  String get upgradeChooseYourPlan;

  /// No description provided for @upgradeUnlockFullPower.
  ///
  /// In en, this message translates to:
  /// **'Unlock the full power of TransKey'**
  String get upgradeUnlockFullPower;

  /// No description provided for @upgradeCurrentLabel.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get upgradeCurrentLabel;

  /// No description provided for @upgradePopularBadge.
  ///
  /// In en, this message translates to:
  /// **'Popular'**
  String get upgradePopularBadge;

  /// No description provided for @upgradeTryFreeDays.
  ///
  /// In en, this message translates to:
  /// **'Try free for 7 days'**
  String get upgradeTryFreeDays;

  /// No description provided for @upgradeTrialActivated.
  ///
  /// In en, this message translates to:
  /// **'Trial activated! {info}'**
  String upgradeTrialActivated(String info);

  /// No description provided for @upgradeTrialActivateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to activate trial'**
  String get upgradeTrialActivateFailed;

  /// No description provided for @upgradeCheckoutFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open checkout'**
  String get upgradeCheckoutFailed;

  /// No description provided for @upgradeMobileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'All features, mobile only'**
  String get upgradeMobileSubtitle;

  /// No description provided for @upgradeProSubtitle.
  ///
  /// In en, this message translates to:
  /// **'All features, all platforms'**
  String get upgradeProSubtitle;

  /// No description provided for @upgradeFreeFeat1.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get upgradeFreeFeat1;

  /// No description provided for @upgradeFreeFeat2.
  ///
  /// In en, this message translates to:
  /// **'20 req/day'**
  String get upgradeFreeFeat2;

  /// No description provided for @upgradeFreeFeat3.
  ///
  /// In en, this message translates to:
  /// **'2000 chars/day'**
  String get upgradeFreeFeat3;

  /// No description provided for @upgradeFreeFeat4.
  ///
  /// In en, this message translates to:
  /// **'Glossary'**
  String get upgradeFreeFeat4;

  /// No description provided for @upgradeMobileFeat1.
  ///
  /// In en, this message translates to:
  /// **'All features'**
  String get upgradeMobileFeat1;

  /// No description provided for @upgradeMobileFeat2.
  ///
  /// In en, this message translates to:
  /// **'iOS & Android'**
  String get upgradeMobileFeat2;

  /// No description provided for @upgradeMobileFeat3.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get upgradeMobileFeat3;

  /// No description provided for @upgradeProFeat1.
  ///
  /// In en, this message translates to:
  /// **'All features'**
  String get upgradeProFeat1;

  /// No description provided for @upgradeProFeat2.
  ///
  /// In en, this message translates to:
  /// **'All platforms'**
  String get upgradeProFeat2;

  /// No description provided for @upgradeProFeat3.
  ///
  /// In en, this message translates to:
  /// **'Desktop + Mobile'**
  String get upgradeProFeat3;

  /// No description provided for @upgradeFeatureColumn.
  ///
  /// In en, this message translates to:
  /// **'Feature'**
  String get upgradeFeatureColumn;

  /// No description provided for @upgradeMobilePrice.
  ///
  /// In en, this message translates to:
  /// **'📱 Mobile · \$3/mo'**
  String get upgradeMobilePrice;

  /// No description provided for @upgradeProPrice.
  ///
  /// In en, this message translates to:
  /// **'💻 Pro · \$6/mo'**
  String get upgradeProPrice;

  /// No description provided for @upgradeFooterHint.
  ///
  /// In en, this message translates to:
  /// **'📱 Mobile: best value if you only use your phone\n💻 Pro: works on both phone and desktop'**
  String get upgradeFooterHint;

  /// No description provided for @comparisonReplyTranslate.
  ///
  /// In en, this message translates to:
  /// **'Reply translate'**
  String get comparisonReplyTranslate;

  /// No description provided for @comparisonMobileApps.
  ///
  /// In en, this message translates to:
  /// **'📱 iOS & Android'**
  String get comparisonMobileApps;

  /// No description provided for @comparisonDesktop.
  ///
  /// In en, this message translates to:
  /// **'💻 Desktop'**
  String get comparisonDesktop;

  /// No description provided for @nudgeUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock {feature}'**
  String nudgeUnlock(String feature);

  /// No description provided for @nudgeMobileCopy.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Pro to use this feature\nacross all platforms.'**
  String get nudgeMobileCopy;

  /// No description provided for @nudgeChoosePlan.
  ///
  /// In en, this message translates to:
  /// **'Choose a plan that fits your needs.'**
  String get nudgeChoosePlan;

  /// No description provided for @nudgeMaybeLater.
  ///
  /// In en, this message translates to:
  /// **'Maybe later'**
  String get nudgeMaybeLater;

  /// No description provided for @nudgeMobileTitle.
  ///
  /// In en, this message translates to:
  /// **'📱 Mobile'**
  String get nudgeMobileTitle;

  /// No description provided for @nudgeProTitle.
  ///
  /// In en, this message translates to:
  /// **'💻 Pro'**
  String get nudgeProTitle;

  /// No description provided for @nudgeUpgradeToPro.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Pro'**
  String get nudgeUpgradeToPro;

  /// No description provided for @nudgeUpgradeToProSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use on all platforms — desktop + mobile'**
  String get nudgeUpgradeToProSubtitle;

  /// No description provided for @nudgePriceMobile.
  ///
  /// In en, this message translates to:
  /// **'\$3/month'**
  String get nudgePriceMobile;

  /// No description provided for @nudgePriceProMonthly.
  ///
  /// In en, this message translates to:
  /// **'\$6/month'**
  String get nudgePriceProMonthly;

  /// No description provided for @onboardWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to TransKey'**
  String get onboardWelcomeTitle;

  /// No description provided for @onboardWelcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Translate text in real-time across\n20+ languages instantly.'**
  String get onboardWelcomeSubtitle;

  /// No description provided for @onboardChooseTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose Your Language'**
  String get onboardChooseTitle;

  /// No description provided for @onboardChooseSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick your preferred target language.\nYou can change it anytime in settings.'**
  String get onboardChooseSubtitle;

  /// No description provided for @onboardStartedTitle.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get onboardStartedTitle;

  /// No description provided for @onboardStartedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in or create a free account\nto start translating now.'**
  String get onboardStartedSubtitle;

  /// No description provided for @onboardGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get onboardGetStarted;

  /// No description provided for @setupTitle.
  ///
  /// In en, this message translates to:
  /// **'Setup Keyboard'**
  String get setupTitle;

  /// No description provided for @setupOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get setupOpenSettings;

  /// No description provided for @setupOpenPermissions.
  ///
  /// In en, this message translates to:
  /// **'Open Permissions'**
  String get setupOpenPermissions;

  /// No description provided for @setupStep1TitleIOS.
  ///
  /// In en, this message translates to:
  /// **'Add TransKey Keyboard'**
  String get setupStep1TitleIOS;

  /// No description provided for @setupStep1TitleAndroid.
  ///
  /// In en, this message translates to:
  /// **'Enable Floating Bubble'**
  String get setupStep1TitleAndroid;

  /// No description provided for @setupStep1DescIOS.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings and add TransKey as a custom keyboard so you can translate directly while typing.'**
  String get setupStep1DescIOS;

  /// No description provided for @setupStep1DescAndroid.
  ///
  /// In en, this message translates to:
  /// **'Allow TransKey to display over other apps so the floating bubble can appear when you need it.'**
  String get setupStep1DescAndroid;

  /// No description provided for @setupStep2Title.
  ///
  /// In en, this message translates to:
  /// **'Allow Full Access'**
  String get setupStep2Title;

  /// No description provided for @setupStep2DescIOS.
  ///
  /// In en, this message translates to:
  /// **'Tap TransKey in the keyboard list and enable \"Allow Full Access\". This is needed to connect to the internet for translations.'**
  String get setupStep2DescIOS;

  /// No description provided for @setupStep2DescAndroid.
  ///
  /// In en, this message translates to:
  /// **'The overlay permission lets TransKey show a floating bubble on top of other apps for quick translations.'**
  String get setupStep2DescAndroid;

  /// No description provided for @setupStep3Title.
  ///
  /// In en, this message translates to:
  /// **'You\'re All Set!'**
  String get setupStep3Title;

  /// No description provided for @setupStep3DescIOS.
  ///
  /// In en, this message translates to:
  /// **'When typing in any app, long-press the globe key 🌐 to switch to TransKey. Tap \"Reply\" to translate your message instantly.'**
  String get setupStep3DescIOS;

  /// No description provided for @setupStep3DescAndroid.
  ///
  /// In en, this message translates to:
  /// **'Select text in any app and share it to TransKey, or use the floating bubble for quick translations.'**
  String get setupStep3DescAndroid;

  /// No description provided for @setupStep4Title.
  ///
  /// In en, this message translates to:
  /// **'Translate from Any App'**
  String get setupStep4Title;

  /// No description provided for @setupStep4DescIOS.
  ///
  /// In en, this message translates to:
  /// **'Select any text → tap \"Share\" → choose TransKey. Or copy text and open TransKey — it reads your clipboard automatically.'**
  String get setupStep4DescIOS;

  /// No description provided for @setupStep4DescAndroid.
  ///
  /// In en, this message translates to:
  /// **'Select text in any app → tap \"Share\" → choose TransKey. Or use the floating bubble after copying text.'**
  String get setupStep4DescAndroid;

  /// No description provided for @setupStep5Title.
  ///
  /// In en, this message translates to:
  /// **'Smart Features'**
  String get setupStep5Title;

  /// No description provided for @setupStep5Desc.
  ///
  /// In en, this message translates to:
  /// **'Translate, Reply, Summarize, Explain & Refine — all powered by AI. Pro features are marked with a lock icon.'**
  String get setupStep5Desc;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
        'de',
        'en',
        'es',
        'fr',
        'ja',
        'ko',
        'vi',
        'zh'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'vi':
      return AppLocalizationsVi();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
