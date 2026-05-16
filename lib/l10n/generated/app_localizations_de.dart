// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get translate => 'Übersetzen';

  @override
  String get summarize => 'Zusammenfassen';

  @override
  String get explain => 'Erklären';

  @override
  String get refine => 'Verfeinern';

  @override
  String get reply => 'Antworten';

  @override
  String get history => 'Verlauf';

  @override
  String get glossary => 'Glossar';

  @override
  String get settings => 'Einstellungen';

  @override
  String get suggestions => 'Vorschläge';

  @override
  String get copy => 'Kopieren';

  @override
  String get save => 'Speichern';

  @override
  String get copied => 'Kopiert';

  @override
  String get delete => 'Löschen';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get ok => 'OK';

  @override
  String get confirm => 'Bestätigen';

  @override
  String get clear => 'Löschen';

  @override
  String get dismiss => 'Verwerfen';

  @override
  String get required => 'Erforderlich';

  @override
  String get addAction => 'Hinzufügen';

  @override
  String get saveAction => 'Speichern';

  @override
  String get next => 'Weiter';

  @override
  String get skip => 'Überspringen';

  @override
  String get done => 'Fertig';

  @override
  String get hintEnterText => 'Text zum Übersetzen eingeben...';

  @override
  String detectedLang(String lang) {
    return 'Erkannt: $lang';
  }

  @override
  String get autoDetect => 'Automatisch erkennen';

  @override
  String get sourceLang => 'Quelle';

  @override
  String get targetLang => 'Ziel';

  @override
  String get swapLanguages => 'Sprachen tauschen';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get sectionLanguage => 'Sprache';

  @override
  String get sectionTranslation => 'Übersetzung';

  @override
  String get sectionAdvanced => 'Erweitert';

  @override
  String get sectionOther => 'Sonstiges';

  @override
  String get sectionSpeech => 'Vorlesen';

  @override
  String get targetLanguage => 'Zielsprache';

  @override
  String get sourceLanguage => 'Quellsprache';

  @override
  String get appLanguage => 'App-Sprache';

  @override
  String get saveHistory => 'Verlauf speichern';

  @override
  String get romanization => 'Romanisierung';

  @override
  String get replySuggestions => 'Antwortvorschläge';

  @override
  String get toneOverride => 'Übersetzungston';

  @override
  String get replyToneOverride => 'Antwortton';

  @override
  String get replyLanguage => 'Antwortsprache';

  @override
  String get replyLanguageFromConversation => 'Aus dem Gespräch';

  @override
  String get autoCloseResult => 'Automatisch schließen';

  @override
  String get autoCloseSeconds => 'Auto-Schließen (Sekunden)';

  @override
  String get autoCloseUnit => 'Sekunden';

  @override
  String get autoCloseDisabled => 'Aus';

  @override
  String get toneAuto => 'Auto';

  @override
  String get toneBusiness => 'Geschäftlich';

  @override
  String get toneCasual => 'Locker';

  @override
  String get toneFormal => 'Formell';

  @override
  String get tonePolite => 'Höflich';

  @override
  String get toneTechnical => 'Technisch';

  @override
  String get toneNeutral => 'Neutral';

  @override
  String get toneReplySameAsTranslate => 'Wie Übersetzung';

  @override
  String get popupTo => 'Nach:';

  @override
  String get tabTranslate => 'Übersetzen';

  @override
  String get tabReply => 'Antworten';

  @override
  String get tabSummarize => 'Zusammenfassen';

  @override
  String get tabExplain => 'Erklären';

  @override
  String get tabRefine => 'Verfeinern';

  @override
  String get keyboardSetup => 'Tastatur einrichten';

  @override
  String get bubbleSetup => 'Bubble einrichten';

  @override
  String get floatingBubble => 'Schwebende Bubble';

  @override
  String get bubbleActive => 'Aktiv';

  @override
  String get bubbleInactive => 'Inaktiv';

  @override
  String get sendFeedback => 'Feedback senden';

  @override
  String get termsOfService => 'Nutzungsbedingungen';

  @override
  String get privacyPolicy => 'Datenschutzerklärung';

  @override
  String get version => 'Version';

  @override
  String get upgrade => 'Upgrade';

  @override
  String get upgradeToPro => 'Auf Pro upgraden';

  @override
  String get logOut => 'Abmelden';

  @override
  String get changePassword => 'Passwort ändern';

  @override
  String get manageDevices => 'Geräte verwalten';

  @override
  String get manageSubscription => 'Abo verwalten';

  @override
  String get currentPassword => 'Aktuelles Passwort';

  @override
  String get newPassword => 'Neues Passwort';

  @override
  String get confirmPassword => 'Neues Passwort bestätigen';

  @override
  String get passwordTooShort => 'Das Passwort muss mindestens 8 Zeichen haben';

  @override
  String get passwordMismatch => 'Passwörter stimmen nicht überein';

  @override
  String get changePasswordSuccess => 'Passwort aktualisiert';

  @override
  String get changePasswordFailed => 'Fehler beim Aktualisieren des Passworts';

  @override
  String get devicesTitle => 'Registrierte Geräte';

  @override
  String get devicesEmpty => 'Noch keine Geräte registriert.';

  @override
  String get devicesProLimit => 'Der Pro-Tarif erlaubt bis zu 2 Geräte.';

  @override
  String get deviceCurrentThis => 'Dieses Gerät';

  @override
  String deviceLastUsed(String date) {
    return 'Zuletzt verwendet: $date';
  }

  @override
  String get removeDevice => 'Entfernen';

  @override
  String get removeDeviceConfirm =>
      'Dieses Gerät entfernen? Es muss sich erneut anmelden.';

  @override
  String get removeDeviceFailed => 'Gerät konnte nicht entfernt werden';

  @override
  String get subscriptionTitle => 'Abonnement';

  @override
  String get subscriptionStatus => 'Status';

  @override
  String get subscriptionRenewsAt => 'Verlängert';

  @override
  String get subscriptionEndsAt => 'Endet';

  @override
  String get subscriptionTrialEndsAt => 'Testversion endet';

  @override
  String get subscriptionInactive => 'Kein aktives Abonnement';

  @override
  String get subscriptionAdminGranted =>
      'Ihr Tarif wurde vom Support aktiviert, nicht über Self-Service-Abrechnung. Kontaktieren Sie uns für Änderung oder Kündigung.';

  @override
  String get subscriptionCancel => 'Abo kündigen';

  @override
  String get subscriptionCancelConfirm =>
      'Pro-Abo kündigen? Sie behalten Pro bis zum Ende des aktuellen Zeitraums.';

  @override
  String get subscriptionCancelled => 'Das Abo endet zum Verlängerungsdatum.';

  @override
  String get subscriptionCancelFailed => 'Abo konnte nicht gekündigt werden';

  @override
  String get voicePickerTitle => 'Stimme';

  @override
  String get voiceDefault => 'Standard';

  @override
  String get speedPickerTitle => 'Sprechgeschwindigkeit';

  @override
  String get speedNormal => 'Normal';

  @override
  String get accessibilityPasteBack => 'Antwort in andere Apps einfügen';

  @override
  String get accessibilityPasteBackDesc =>
      'Aktivieren Sie TransKey in den Bedienungshilfen, damit „Einfügen“ die Antwort in das aktive Eingabefeld jeder App schreibt.';

  @override
  String get accessibilityEnabled => 'Aktiviert';

  @override
  String get accessibilityDisabled =>
      'Nicht aktiviert — tippen, um Einstellungen zu öffnen';

  @override
  String get feedbackTitle => 'Feedback senden';

  @override
  String get feedbackHint => 'Sagen Sie uns Ihre Meinung...';

  @override
  String get feedbackSend => 'Senden';

  @override
  String get feedbackThanks => 'Danke für Ihr Feedback!';

  @override
  String get feedbackFailed => 'Feedback konnte nicht gesendet werden';

  @override
  String get selectLanguage => 'Sprache auswählen';

  @override
  String get searchLanguages => 'Sprachen suchen...';

  @override
  String get recent => 'Zuletzt';

  @override
  String get allLanguages => 'Alle Sprachen';

  @override
  String get login => 'Anmelden';

  @override
  String get signUp => 'Registrieren';

  @override
  String get logIn => 'Anmelden';

  @override
  String get createAccount => 'Konto erstellen';

  @override
  String get continueWithGoogle => 'Mit Google fortfahren';

  @override
  String get orDivider => 'oder';

  @override
  String get emailHint => 'E-Mail';

  @override
  String get passwordHint => 'Passwort';

  @override
  String get nameHint => 'Ihr Name';

  @override
  String get nameRequired => 'Name ist erforderlich';

  @override
  String get emailRequired => 'E-Mail ist erforderlich';

  @override
  String get emailInvalid => 'Gültige E-Mail eingeben';

  @override
  String get passwordRequired => 'Passwort ist erforderlich';

  @override
  String get passwordMinSix => 'Mindestens 6 Zeichen';

  @override
  String get proDeviceLimitError =>
      'Pro-Konto bereits auf maximaler Geräteanzahl registriert';

  @override
  String get deviceLimitError => 'Zu viele Konten auf diesem Gerät';

  @override
  String googleSignInFailed(String error) {
    return 'Google-Anmeldung fehlgeschlagen: $error';
  }

  @override
  String get googleNotConfigured =>
      'Google-Anmeldung nicht konfiguriert (serverClientId fehlt)';

  @override
  String get googleSignInNoIdToken =>
      'Google-Anmeldung lieferte keinen idToken — serverClientId prüfen';

  @override
  String get proRequired => 'Pro-Tarif erforderlich';

  @override
  String get noTextToTranslate => 'Zuerst Text eingeben';

  @override
  String get errorGeneric => 'Etwas ist schiefgelaufen';

  @override
  String get planFree => 'Kostenlos';

  @override
  String get planPro => 'Pro';

  @override
  String get planMobile => 'Mobile';

  @override
  String get planTrial => 'Testversion';

  @override
  String usageRequests(int used, int limit) {
    return '$used/$limit Anfragen';
  }

  @override
  String usageCharacters(int used, int limit) {
    return '$used/$limit Zeichen';
  }

  @override
  String trialEndsInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Tagen',
      one: 'Tag',
    );
    return 'Testversion endet in $days $_temp0';
  }

  @override
  String get trialEndsToday => 'Testversion endet heute';

  @override
  String get trialEndsTomorrow => 'Testversion endet morgen';

  @override
  String get trialUpgradeNow => 'Jetzt upgraden';

  @override
  String get trialAlreadyUsed =>
      'Sie haben Ihre kostenlose Testversion bereits genutzt';

  @override
  String get subscriptionExpiredBanner => 'Ihr Abonnement ist abgelaufen';

  @override
  String get subscriptionExpiredRenew => 'Verlängern';

  @override
  String subscriptionEndsOn(String date) {
    return 'Endet am $date';
  }

  @override
  String get planMobileSubscription => 'Mobile-Abonnement';

  @override
  String get planProSubscription => 'Pro-Abonnement';

  @override
  String get discountFirstMonth => '−50 % im ersten Monat';

  @override
  String get accountBannedTitle => 'Konto gesperrt';

  @override
  String get accountBannedBody =>
      'Ihr TransKey-Konto wurde gesperrt. Bitte kontaktieren Sie den Support, falls Sie glauben, dass dies ein Fehler ist.';

  @override
  String get accountBannedContact => 'Support kontaktieren';

  @override
  String get accountBannedLogout => 'Abmelden';

  @override
  String get historyTitle => 'Verlauf';

  @override
  String get historySearchHint => 'Verlauf durchsuchen...';

  @override
  String get historyFilterAll => 'Alle';

  @override
  String get historyFilterFavorites => '★ Favoriten';

  @override
  String get historyFilterLocked => '🔒 Gesperrt';

  @override
  String get historyMenuClearAll => 'Alle löschen';

  @override
  String get historyMenuKeepFavorites => 'Nur Favoriten behalten';

  @override
  String get historyClearDialogTitle => 'Verlauf löschen';

  @override
  String get historyClearDialogBody =>
      'Gesamten Verlauf löschen? Gesperrte Einträge bleiben erhalten.';

  @override
  String get historyKeepFavDialogBody =>
      'Alle Nicht-Favoriten löschen? Gesperrte Einträge bleiben erhalten.';

  @override
  String get historyDetailSourceLabel => 'Quelle';

  @override
  String get historyDetailTranslationLabel => 'Übersetzung';

  @override
  String get historyDetailRomanizationLabel => 'Romanisierung';

  @override
  String get historyDetailFavoriteBadge => '★ Favorit';

  @override
  String get historyDetailLockedBadge => '🔒 Gesperrt';

  @override
  String get historyDetailCopyTranslation => 'Übersetzung\nkopieren';

  @override
  String get historyDetailCopySource => 'Quelle\nkopieren';

  @override
  String get historyDetailUnfavorite => 'Aus Favoriten';

  @override
  String get historyDetailFavoriteAction => 'Favorisieren';

  @override
  String get historyDetailUnlock => 'Entsperren';

  @override
  String get historyDetailLockAction => 'Sperren';

  @override
  String get historyDetailTtsLabel => 'TTS';

  @override
  String glossaryTitle(int count, int max) {
    return 'Glossar ($count/$max)';
  }

  @override
  String get glossarySync => 'Synchronisieren';

  @override
  String get glossaryDeleteTitle => 'Eintrag löschen';

  @override
  String glossaryDeleteBody(String source) {
    return '„$source“ löschen?';
  }

  @override
  String glossaryLimitReached(int max) {
    return 'Glossar-Limit erreicht ($max)';
  }

  @override
  String get glossarySourceTargetRequired =>
      'Quelle und Ziel sind erforderlich';

  @override
  String get glossarySyncFailed => 'Glossar-Synchronisation fehlgeschlagen';

  @override
  String get glossaryEditTitle => 'Eintrag bearbeiten';

  @override
  String get glossaryAddTitle => 'Eintrag hinzufügen';

  @override
  String get glossarySourceLabel => 'Quelle';

  @override
  String get glossarySourceHint => 'Wort oder Ausdruck';

  @override
  String get glossaryTargetLabel => 'Ziel';

  @override
  String get glossaryTargetHint => 'Übersetzung';

  @override
  String get upgradeScreenTitle => 'TransKey upgraden';

  @override
  String get upgradeChooseYourPlan => 'Wählen Sie Ihren Tarif';

  @override
  String get upgradeUnlockFullPower =>
      'Schöpfen Sie das volle Potenzial von TransKey aus';

  @override
  String get upgradeCurrentLabel => 'Aktuell';

  @override
  String get upgradePopularBadge => 'Beliebt';

  @override
  String get upgradeTryFreeDays => '7 Tage kostenlos testen';

  @override
  String upgradeTrialActivated(String info) {
    return 'Testversion aktiviert! $info';
  }

  @override
  String get upgradeTrialActivateFailed =>
      'Testversion konnte nicht aktiviert werden';

  @override
  String get upgradeCheckoutFailed => 'Bezahlung konnte nicht geöffnet werden';

  @override
  String get upgradeMobileSubtitle => 'Alle Funktionen, nur Mobile';

  @override
  String get upgradeProSubtitle => 'Alle Funktionen, alle Plattformen';

  @override
  String get upgradeFreeFeat1 => 'Übersetzen';

  @override
  String get upgradeFreeFeat2 => '20 Anfragen/Tag';

  @override
  String get upgradeFreeFeat3 => '2000 Zeichen/Tag';

  @override
  String get upgradeFreeFeat4 => 'Glossar';

  @override
  String get upgradeMobileFeat1 => 'Alle Funktionen';

  @override
  String get upgradeMobileFeat2 => 'iOS & Android';

  @override
  String get upgradeMobileFeat3 => 'Unbegrenzt';

  @override
  String get upgradeProFeat1 => 'Alle Funktionen';

  @override
  String get upgradeProFeat2 => 'Alle Plattformen';

  @override
  String get upgradeProFeat3 => 'Desktop + Mobile';

  @override
  String get upgradeFeatureColumn => 'Funktion';

  @override
  String get upgradeMobilePrice => '📱 Mobile · 3 \$/Mon.';

  @override
  String get upgradeProPrice => '💻 Pro · 6 \$/Mon.';

  @override
  String get upgradeFooterHint =>
      '📱 Mobile: bestes Preis-Leistungs-Verhältnis nur am Handy\n💻 Pro: funktioniert auf Handy und Desktop';

  @override
  String get comparisonReplyTranslate => 'Antwortübersetzung';

  @override
  String get comparisonMobileApps => '📱 iOS & Android';

  @override
  String get comparisonDesktop => '💻 Desktop';

  @override
  String nudgeUnlock(String feature) {
    return '$feature freischalten';
  }

  @override
  String get nudgeMobileCopy =>
      'Upgrade auf Pro, um diese Funktion\nauf allen Plattformen zu nutzen.';

  @override
  String get nudgeChoosePlan =>
      'Wählen Sie einen Tarif, der Ihren Bedürfnissen entspricht.';

  @override
  String get nudgeMaybeLater => 'Vielleicht später';

  @override
  String get nudgeMobileTitle => '📱 Mobile';

  @override
  String get nudgeProTitle => '💻 Pro';

  @override
  String get nudgeUpgradeToPro => 'Auf Pro upgraden';

  @override
  String get nudgeUpgradeToProSubtitle =>
      'Nutzen Sie auf allen Plattformen — Desktop + Mobile';

  @override
  String get nudgePriceMobile => '3 \$/Monat';

  @override
  String get nudgePriceProMonthly => '6 \$/Monat';

  @override
  String get onboardWelcomeTitle => 'Willkommen bei TransKey';

  @override
  String get onboardWelcomeSubtitle =>
      'Übersetzen Sie Text in Echtzeit in\nüber 20 Sprachen sofort.';

  @override
  String get onboardChooseTitle => 'Wählen Sie Ihre Sprache';

  @override
  String get onboardChooseSubtitle =>
      'Wählen Sie Ihre bevorzugte Zielsprache.\nSie können sie jederzeit in den Einstellungen ändern.';

  @override
  String get onboardStartedTitle => 'Loslegen';

  @override
  String get onboardStartedSubtitle =>
      'Melden Sie sich an oder erstellen Sie ein kostenloses Konto,\num jetzt mit dem Übersetzen zu beginnen.';

  @override
  String get onboardGetStarted => 'Loslegen';

  @override
  String get setupTitle => 'Tastatur einrichten';

  @override
  String get setupOpenSettings => 'Einstellungen öffnen';

  @override
  String get setupOpenPermissions => 'Berechtigungen öffnen';

  @override
  String get setupStep1TitleIOS => 'TransKey-Tastatur hinzufügen';

  @override
  String get setupStep1TitleAndroid => 'Schwebende Bubble aktivieren';

  @override
  String get setupStep1DescIOS =>
      'Gehen Sie zu Einstellungen und fügen Sie TransKey als benutzerdefinierte Tastatur hinzu, um beim Tippen direkt zu übersetzen.';

  @override
  String get setupStep1DescAndroid =>
      'Erlauben Sie TransKey, über anderen Apps angezeigt zu werden, damit die schwebende Bubble bei Bedarf erscheinen kann.';

  @override
  String get setupStep2Title => 'Vollständigen Zugriff erlauben';

  @override
  String get setupStep2DescIOS =>
      'Tippen Sie in der Tastaturliste auf TransKey und aktivieren Sie „Vollständigen Zugriff erlauben“. Notwendig, um sich mit dem Internet für Übersetzungen zu verbinden.';

  @override
  String get setupStep2DescAndroid =>
      'Die Overlay-Berechtigung erlaubt TransKey, eine schwebende Bubble über anderen Apps für schnelle Übersetzungen anzuzeigen.';

  @override
  String get setupStep3Title => 'Sie sind bereit!';

  @override
  String get setupStep3DescIOS =>
      'Beim Tippen in einer App halten Sie die Globus-Taste 🌐 gedrückt, um zu TransKey zu wechseln. Tippen Sie auf „Antworten“, um Ihre Nachricht sofort zu übersetzen.';

  @override
  String get setupStep3DescAndroid =>
      'Wählen Sie Text in einer beliebigen App und teilen Sie ihn mit TransKey, oder nutzen Sie die schwebende Bubble für schnelle Übersetzungen.';

  @override
  String get setupStep4Title => 'Aus jeder App übersetzen';

  @override
  String get setupStep4DescIOS =>
      'Text auswählen → „Teilen“ tippen → TransKey wählen. Oder Text kopieren und TransKey öffnen — es liest Ihre Zwischenablage automatisch.';

  @override
  String get setupStep4DescAndroid =>
      'Text in einer App auswählen → „Teilen“ tippen → TransKey wählen. Oder nutzen Sie die schwebende Bubble nach dem Kopieren.';

  @override
  String get setupStep5Title => 'Intelligente Funktionen';

  @override
  String get setupStep5Desc =>
      'Übersetzen, Antworten, Zusammenfassen, Erklären & Verfeinern — alles KI-gestützt. Pro-Funktionen sind mit einem Schloss markiert.';
}
