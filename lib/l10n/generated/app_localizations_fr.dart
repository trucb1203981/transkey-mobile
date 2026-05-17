// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get translate => 'Traduire';

  @override
  String get summarize => 'Résumer';

  @override
  String get explain => 'Expliquer';

  @override
  String get refine => 'Affiner';

  @override
  String get reply => 'Répondre';

  @override
  String get history => 'Historique';

  @override
  String get glossary => 'Glossaire';

  @override
  String get settings => 'Paramètres';

  @override
  String get suggestions => 'Suggestions';

  @override
  String get copy => 'Copier';

  @override
  String get save => 'Enregistrer';

  @override
  String get copied => 'Copié';

  @override
  String get delete => 'Supprimer';

  @override
  String get cancel => 'Annuler';

  @override
  String get ok => 'OK';

  @override
  String get confirm => 'Confirmer';

  @override
  String get clear => 'Effacer';

  @override
  String get dismiss => 'Ignorer';

  @override
  String get required => 'Requis';

  @override
  String get addAction => 'Ajouter';

  @override
  String get saveAction => 'Enregistrer';

  @override
  String get next => 'Suivant';

  @override
  String get skip => 'Passer';

  @override
  String get done => 'Terminé';

  @override
  String get hintEnterText => 'Saisissez le texte à traduire...';

  @override
  String detectedLang(String lang) {
    return 'Détecté : $lang';
  }

  @override
  String get autoDetect => 'Détection auto';

  @override
  String get sourceLang => 'Source';

  @override
  String get targetLang => 'Cible';

  @override
  String get swapLanguages => 'Inverser les langues';

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get sectionLanguage => 'Langue';

  @override
  String get sectionTranslation => 'Traduction';

  @override
  String get sectionAdvanced => 'Avancé';

  @override
  String get sectionOther => 'Autre';

  @override
  String get sectionSpeech => 'Lecture à voix haute';

  @override
  String get targetLanguage => 'Langue cible';

  @override
  String get sourceLanguage => 'Langue source';

  @override
  String get appLanguage => 'Langue de l’app';

  @override
  String get saveHistory => 'Enregistrer l’historique';

  @override
  String get romanization => 'Romanisation';

  @override
  String get replySuggestions => 'Suggestions de réponse';

  @override
  String get toneOverride => 'Ton de traduction';

  @override
  String get replyToneOverride => 'Ton de réponse';

  @override
  String get replyLanguage => 'Langue de réponse';

  @override
  String get replyLanguageFromConversation => 'Depuis la conversation';

  @override
  String get autoCloseResult => 'Fermeture automatique';

  @override
  String get autoCloseSeconds => 'Fermeture auto (secondes)';

  @override
  String get autoCloseUnit => 'secondes';

  @override
  String get autoCloseDisabled => 'Désactivée';

  @override
  String get toneAuto => 'Auto';

  @override
  String get toneBusiness => 'Affaires';

  @override
  String get toneCasual => 'Décontracté';

  @override
  String get toneFormal => 'Formel';

  @override
  String get tonePolite => 'Poli';

  @override
  String get toneTechnical => 'Technique';

  @override
  String get toneNeutral => 'Neutre';

  @override
  String get toneReplySameAsTranslate => 'Identique à la traduction';

  @override
  String get popupTo => 'Vers :';

  @override
  String get tabTranslate => 'Traduire';

  @override
  String get tabReply => 'Répondre';

  @override
  String get tabSummarize => 'Résumer';

  @override
  String get tabExplain => 'Expliquer';

  @override
  String get tabRefine => 'Affiner';

  @override
  String get keyboardSetup => 'Configurer le clavier';

  @override
  String get bubbleSetup => 'Configurer la bulle';

  @override
  String get floatingBubble => 'Bulle flottante';

  @override
  String get bubbleActive => 'Active';

  @override
  String get bubbleInactive => 'Inactive';

  @override
  String get sendFeedback => 'Envoyer un retour';

  @override
  String get termsOfService => 'Conditions d’utilisation';

  @override
  String get privacyPolicy => 'Politique de confidentialité';

  @override
  String get version => 'Version';

  @override
  String get upgrade => 'Mettre à niveau';

  @override
  String get upgradeToPro => 'Passer à Pro';

  @override
  String get logOut => 'Se déconnecter';

  @override
  String get changePassword => 'Changer le mot de passe';

  @override
  String get manageDevices => 'Gérer les appareils';

  @override
  String get manageSubscription => 'Gérer l’abonnement';

  @override
  String get currentPassword => 'Mot de passe actuel';

  @override
  String get newPassword => 'Nouveau mot de passe';

  @override
  String get confirmPassword => 'Confirmer le nouveau mot de passe';

  @override
  String get passwordTooShort =>
      'Le mot de passe doit comporter au moins 8 caractères';

  @override
  String get passwordMismatch => 'Les mots de passe ne correspondent pas';

  @override
  String get changePasswordSuccess => 'Mot de passe mis à jour';

  @override
  String get changePasswordFailed => 'Échec de la mise à jour du mot de passe';

  @override
  String get devicesTitle => 'Appareils enregistrés';

  @override
  String get devicesEmpty => 'Aucun appareil enregistré.';

  @override
  String get devicesProLimit => 'Le forfait Pro permet jusqu’à 2 appareils.';

  @override
  String get deviceCurrentThis => 'Cet appareil';

  @override
  String deviceLastUsed(String date) {
    return 'Dernière utilisation : $date';
  }

  @override
  String get removeDevice => 'Supprimer';

  @override
  String get removeDeviceConfirm =>
      'Supprimer cet appareil ? Il devra se reconnecter.';

  @override
  String get removeDeviceFailed => 'Impossible de supprimer l’appareil';

  @override
  String get subscriptionTitle => 'Abonnement';

  @override
  String get subscriptionStatus => 'Statut';

  @override
  String get subscriptionRenewsAt => 'Renouvelle';

  @override
  String get subscriptionEndsAt => 'Se termine';

  @override
  String get subscriptionTrialEndsAt => 'Fin de l’essai';

  @override
  String get subscriptionInactive => 'Aucun abonnement actif';

  @override
  String get subscriptionAdminGranted =>
      'Votre forfait a été activé par le support, pas via la facturation en libre-service. Contactez-nous pour le modifier ou l’annuler.';

  @override
  String get subscriptionCancel => 'Annuler l’abonnement';

  @override
  String get subscriptionCancelConfirm =>
      'Annuler votre abonnement Pro ? Vous garderez Pro jusqu’à la fin de la période en cours.';

  @override
  String get subscriptionCancelled =>
      'L’abonnement se terminera à la date de renouvellement.';

  @override
  String get subscriptionCancelFailed => 'Impossible d’annuler l’abonnement';

  @override
  String get voicePickerTitle => 'Voix';

  @override
  String get voiceDefault => 'Par défaut';

  @override
  String get speedPickerTitle => 'Vitesse de lecture';

  @override
  String get speedNormal => 'Normale';

  @override
  String get accessibilityPasteBack => 'Coller la réponse dans d’autres apps';

  @override
  String get accessibilityPasteBackDesc =>
      'Activez TransKey dans les paramètres d’Accessibilité pour que « Coller » écrive la réponse dans le champ actif de n’importe quelle app.';

  @override
  String get accessibilityEnabled => 'Activé';

  @override
  String get accessibilityDisabled =>
      'Non activé — appuyez pour ouvrir les paramètres';

  @override
  String get feedbackTitle => 'Envoyer un retour';

  @override
  String get feedbackHint => 'Dites-nous ce que vous en pensez...';

  @override
  String get feedbackSend => 'Envoyer';

  @override
  String get feedbackThanks => 'Merci pour votre retour !';

  @override
  String get feedbackFailed => 'Échec de l’envoi du retour';

  @override
  String get selectLanguage => 'Sélectionner la langue';

  @override
  String get searchLanguages => 'Rechercher des langues...';

  @override
  String get recent => 'Récentes';

  @override
  String get allLanguages => 'Toutes les langues';

  @override
  String get login => 'Connexion';

  @override
  String get signUp => 'Inscription';

  @override
  String get logIn => 'Se connecter';

  @override
  String get createAccount => 'Créer un compte';

  @override
  String get continueWithGoogle => 'Continuer avec Google';

  @override
  String get orDivider => 'ou';

  @override
  String get emailHint => 'E-mail';

  @override
  String get passwordHint => 'Mot de passe';

  @override
  String get nameHint => 'Votre nom';

  @override
  String get nameRequired => 'Le nom est requis';

  @override
  String get emailRequired => 'L’e-mail est requis';

  @override
  String get emailInvalid => 'Entrez un e-mail valide';

  @override
  String get passwordRequired => 'Le mot de passe est requis';

  @override
  String get passwordMinSix => 'Au moins 6 caractères';

  @override
  String get proDeviceLimitError =>
      'Le compte Pro est déjà enregistré sur le nombre maximum d’appareils';

  @override
  String get deviceLimitError => 'Trop de comptes sur cet appareil';

  @override
  String googleSignInFailed(String error) {
    return 'Échec de la connexion Google : $error';
  }

  @override
  String get googleNotConfigured =>
      'Connexion Google non configurée (serverClientId manquant)';

  @override
  String get googleSignInNoIdToken =>
      'La connexion Google n’a retourné aucun idToken — vérifiez serverClientId';

  @override
  String get proRequired => 'Forfait Pro requis';

  @override
  String get noTextToTranslate => 'Saisissez d’abord du texte';

  @override
  String get errorGeneric => 'Une erreur s’est produite';

  @override
  String get planFree => 'Gratuit';

  @override
  String get planPro => 'Pro';

  @override
  String get planMobile => 'Mobile';

  @override
  String get planTrial => 'Essai';

  @override
  String usageRequests(int used, int limit) {
    return '$used/$limit requêtes';
  }

  @override
  String usageCharacters(int used, int limit) {
    return '$used/$limit car.';
  }

  @override
  String trialEndsInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'jours',
      one: 'jour',
    );
    return 'Essai se termine dans $days $_temp0';
  }

  @override
  String get trialEndsToday => 'L’essai se termine aujourd’hui';

  @override
  String get trialEndsTomorrow => 'L’essai se termine demain';

  @override
  String get trialUpgradeNow => 'Mettre à niveau';

  @override
  String get trialAlreadyUsed => 'Vous avez déjà utilisé votre essai gratuit';

  @override
  String get subscriptionExpiredBanner => 'Votre abonnement a expiré';

  @override
  String get subscriptionExpiredRenew => 'Renouveler';

  @override
  String subscriptionEndsOn(String date) {
    return 'Se termine le $date';
  }

  @override
  String get planMobileSubscription => 'Abonnement Mobile';

  @override
  String get planProSubscription => 'Abonnement Pro';

  @override
  String get discountFirstMonth => '−50 % le premier mois';

  @override
  String get accountBannedTitle => 'Compte suspendu';

  @override
  String get accountBannedBody =>
      'Votre compte TransKey a été suspendu. Veuillez contacter le support si vous pensez qu’il s’agit d’une erreur.';

  @override
  String get accountBannedContact => 'Contacter le support';

  @override
  String get accountBannedLogout => 'Se déconnecter';

  @override
  String get historyTitle => 'Historique';

  @override
  String get historySearchHint => 'Rechercher dans l’historique...';

  @override
  String get historyFilterAll => 'Tout';

  @override
  String get historyFilterFavorites => '★ Favoris';

  @override
  String get historyFilterLocked => '🔒 Verrouillés';

  @override
  String get historyMenuClearAll => 'Tout effacer';

  @override
  String get historyMenuKeepFavorites => 'Garder uniquement les favoris';

  @override
  String get historyClearDialogTitle => 'Effacer l’historique';

  @override
  String get historyClearDialogBody =>
      'Supprimer tout l’historique ? Les entrées verrouillées seront conservées.';

  @override
  String get historyKeepFavDialogBody =>
      'Supprimer toutes les entrées non favorites ? Les entrées verrouillées seront conservées.';

  @override
  String get historyDetailSourceLabel => 'Source';

  @override
  String get historyDetailTranslationLabel => 'Traduction';

  @override
  String get historyDetailRomanizationLabel => 'Romanisation';

  @override
  String get historyDetailFavoriteBadge => '★ Favori';

  @override
  String get historyDetailLockedBadge => '🔒 Verrouillé';

  @override
  String get historyDetailCopyTranslation => 'Copier\nla traduction';

  @override
  String get historyDetailCopySource => 'Copier\nla source';

  @override
  String get historyDetailUnfavorite => 'Retirer des favoris';

  @override
  String get historyDetailFavoriteAction => 'Favoriser';

  @override
  String get historyDetailUnlock => 'Déverrouiller';

  @override
  String get historyDetailLockAction => 'Verrouiller';

  @override
  String get historyDetailTtsLabel => 'TTS';

  @override
  String glossaryTitle(int count, int max) {
    return 'Glossaire ($count/$max)';
  }

  @override
  String get glossarySync => 'Synchroniser';

  @override
  String get glossaryDeleteTitle => 'Supprimer l’entrée';

  @override
  String glossaryDeleteBody(String source) {
    return 'Supprimer « $source » ?';
  }

  @override
  String glossaryLimitReached(int max) {
    return 'Limite du glossaire atteinte ($max)';
  }

  @override
  String get glossarySourceTargetRequired => 'Source et cible sont requises';

  @override
  String get glossarySyncFailed => 'Échec de la synchronisation du glossaire';

  @override
  String get glossaryEditTitle => 'Modifier l’entrée';

  @override
  String get glossaryAddTitle => 'Ajouter une entrée';

  @override
  String get glossarySourceLabel => 'Source';

  @override
  String get glossarySourceHint => 'Mot ou expression';

  @override
  String get glossaryTargetLabel => 'Cible';

  @override
  String get glossaryTargetHint => 'Traduction';

  @override
  String get upgradeScreenTitle => 'Mettre TransKey à niveau';

  @override
  String get upgradeChooseYourPlan => 'Choisissez votre forfait';

  @override
  String get upgradeUnlockFullPower =>
      'Déverrouillez toute la puissance de TransKey';

  @override
  String get upgradeCurrentLabel => 'Actuel';

  @override
  String get upgradePopularBadge => 'Populaire';

  @override
  String get upgradeTryFreeDays => 'Essayez gratuitement 7 jours';

  @override
  String upgradeTrialActivated(String info) {
    return 'Essai activé ! $info';
  }

  @override
  String get upgradeTrialActivateFailed => 'Échec de l’activation de l’essai';

  @override
  String get upgradeCheckoutFailed => 'Échec de l’ouverture du paiement';

  @override
  String get upgradeMobileSubtitle =>
      'Toutes les fonctionnalités, mobile uniquement';

  @override
  String get upgradeProSubtitle =>
      'Toutes les fonctionnalités, toutes les plateformes';

  @override
  String get upgradeFreeFeat1 => 'Traduire';

  @override
  String get upgradeFreeFeat2 => '20 req/jour';

  @override
  String get upgradeFreeFeat3 => '2000 car./jour';

  @override
  String get upgradeFreeFeat4 => 'Glossaire';

  @override
  String get upgradeMobileFeat1 => 'Toutes les fonctionnalités';

  @override
  String get upgradeMobileFeat2 => 'iOS & Android';

  @override
  String get upgradeMobileFeat3 => 'Illimité';

  @override
  String get upgradeProFeat1 => 'Toutes les fonctionnalités';

  @override
  String get upgradeProFeat2 => 'Toutes les plateformes';

  @override
  String get upgradeProFeat3 => 'Bureau + Mobile';

  @override
  String get upgradeFeatureColumn => 'Fonctionnalité';

  @override
  String get upgradeMobilePrice => '📱 Mobile · 3 \$/mois';

  @override
  String get upgradeProPrice => '💻 Pro · 6 \$/mois';

  @override
  String get upgradeFooterHint =>
      '📱 Mobile : meilleure valeur si vous n’utilisez que votre téléphone\n💻 Pro : fonctionne sur téléphone et bureau';

  @override
  String get comparisonReplyTranslate => 'Traduction de réponse';

  @override
  String get comparisonMobileApps => '📱 iOS & Android';

  @override
  String get comparisonDesktop => '💻 Bureau';

  @override
  String nudgeUnlock(String feature) {
    return 'Débloquer $feature';
  }

  @override
  String get nudgeMobileCopy =>
      'Passez à Pro pour utiliser cette fonctionnalité\nsur toutes les plateformes.';

  @override
  String get nudgeChoosePlan => 'Choisissez un forfait adapté à vos besoins.';

  @override
  String get nudgeMaybeLater => 'Peut-être plus tard';

  @override
  String get nudgeMobileTitle => '📱 Mobile';

  @override
  String get nudgeProTitle => '💻 Pro';

  @override
  String get nudgeUpgradeToPro => 'Passer à Pro';

  @override
  String get nudgeUpgradeToProSubtitle =>
      'Utilisez sur toutes les plateformes — bureau + mobile';

  @override
  String get nudgePriceMobile => '3 \$/mois';

  @override
  String get nudgePriceProMonthly => '6 \$/mois';

  @override
  String get onboardWelcomeTitle => 'Bienvenue dans TransKey';

  @override
  String get onboardWelcomeSubtitle =>
      'Traduisez du texte en temps réel dans\nplus de 20 langues instantanément.';

  @override
  String get onboardChooseTitle => 'Choisissez votre langue';

  @override
  String get onboardChooseSubtitle =>
      'Choisissez votre langue cible préférée.\nVous pouvez la modifier à tout moment dans les paramètres.';

  @override
  String get onboardStartedTitle => 'Commencer';

  @override
  String get onboardStartedSubtitle =>
      'Connectez-vous ou créez un compte gratuit\npour commencer à traduire.';

  @override
  String get onboardGetStarted => 'Commencer';

  @override
  String get setupTitle => 'Configurer le clavier';

  @override
  String get setupOpenSettings => 'Ouvrir les paramètres';

  @override
  String get setupOpenPermissions => 'Ouvrir les autorisations';

  @override
  String get setupStep1TitleIOS => 'Ajouter le clavier TransKey';

  @override
  String get setupStep1TitleAndroid => 'Activer la bulle flottante';

  @override
  String get setupStep1DescIOS =>
      'Allez dans Paramètres et ajoutez TransKey comme clavier personnalisé pour traduire directement en tapant.';

  @override
  String get setupStep1DescAndroid =>
      'Autorisez TransKey à s’afficher au-dessus des autres apps pour que la bulle flottante puisse apparaître quand vous en avez besoin.';

  @override
  String get setupStep2Title => 'Autoriser l’accès complet';

  @override
  String get setupStep2DescIOS =>
      'Appuyez sur TransKey dans la liste des claviers et activez « Autoriser l’accès complet ». Nécessaire pour se connecter à Internet pour les traductions.';

  @override
  String get setupStep2DescAndroid =>
      'L’autorisation de superposition permet à TransKey d’afficher une bulle flottante au-dessus des autres apps pour des traductions rapides.';

  @override
  String get setupStep3Title => 'Tout est prêt !';

  @override
  String get setupStep3DescIOS =>
      'Lorsque vous tapez dans une app, maintenez la touche globe 🌐 pour passer à TransKey. Appuyez sur « Répondre » pour traduire votre message instantanément.';

  @override
  String get setupStep3DescAndroid =>
      'Sélectionnez du texte dans une app et partagez-le avec TransKey, ou utilisez la bulle flottante pour des traductions rapides.';

  @override
  String get setupStep4Title => 'Traduire depuis n’importe quelle app';

  @override
  String get setupStep4DescIOS =>
      'Sélectionnez du texte → appuyez sur « Partager » → choisissez TransKey. Ou copiez le texte et ouvrez TransKey — il lit votre presse-papiers automatiquement.';

  @override
  String get setupStep4DescAndroid =>
      'Sélectionnez du texte dans une app → appuyez sur « Partager » → choisissez TransKey. Ou utilisez la bulle flottante après avoir copié le texte.';

  @override
  String get setupStep5Title => 'Fonctionnalités intelligentes';

  @override
  String get setupStep5Desc =>
      'Traduire, Répondre, Résumer, Expliquer & Affiner — tout est propulsé par l’IA. Les fonctionnalités Pro sont marquées d’un cadenas.';

  @override
  String get guideTitle => 'Comment utiliser';

  @override
  String get guideSubtitle =>
      'Toutes les façons de capturer du texte pour chaque fonctionnalité';

  @override
  String get guideIntroTitle =>
      'Aucune Accessibilité requise pour capturer du texte.';

  @override
  String get guideIntroBody =>
      'Chaque fonctionnalité lit le texte source via une action explicite — Copier, OCR, Sélection de zone, Partage système, ou menu de sélection. L\'Accessibilité sert uniquement pour une commodité optionnelle : coller automatiquement une Réponse dans le champ de saisie ciblé.';

  @override
  String get guideFeatureTranslate => 'Traduire';

  @override
  String get guideFeatureTranslateSubtitle => 'Langue source → langue cible';

  @override
  String get guideFeatureSummary => 'Résumer';

  @override
  String get guideFeatureSummarySubtitle =>
      'Condenser un contenu long en quelques puces';

  @override
  String get guideFeatureRefine => 'Affiner';

  @override
  String get guideFeatureRefineSubtitle =>
      'Améliorer la grammaire / clarté de votre propre brouillon';

  @override
  String get guideFeatureExplain => 'Expliquer';

  @override
  String get guideFeatureExplainSubtitle =>
      'Obtenir une explication simple d\'un texte difficile';

  @override
  String get guideFeatureReply => 'Répondre';

  @override
  String get guideFeatureReplySubtitle =>
      'Générer une suggestion de réponse dans la langue cible';

  @override
  String get guideInputCopyTitle => 'Copier le texte + taper la bulle';

  @override
  String get guideInputCopyDesc =>
      'Copiez du texte dans n\'importe quelle application, puis tapez la bulle flottante et choisissez l\'action.';

  @override
  String get guideInputOcrTitle => 'Scan écran (OCR)';

  @override
  String get guideInputOcrDesc =>
      'Bulle → Scan écran. Capture une image, exécute l\'OCR sur l\'appareil.';

  @override
  String get guideInputRegionTitle => 'Sélection de zone';

  @override
  String get guideInputRegionDesc =>
      'Bulle → Traduire la zone sélectionnée. Dessinez un cadre autour de la zone souhaitée.';

  @override
  String get guideInputShareTitle => 'Menu Partager';

  @override
  String get guideInputShareDesc =>
      'Dans n\'importe quelle app : sélectionnez du texte → Partager → TransKey.';

  @override
  String guideInputMenuTitle(String feature) {
    return 'Menu de sélection → TransKey: $feature';
  }

  @override
  String guideInputMenuDesc(String feature) {
    return 'Appui long sur le texte → débordement ⋮ → TransKey: $feature.';
  }

  @override
  String get guideReplyA11yTitle => 'Accessibilité (optionnel)';

  @override
  String get guideReplyA11yBody =>
      'Accessibilité activée : le résultat est collé directement dans le champ de saisie ciblé après génération.\n\nAccessibilité désactivée : le résultat est copié dans le presse-papiers. Collez-le manuellement où vous voulez.';

  @override
  String get appPermissions => 'Permissions de l\'app';

  @override
  String get permissionsAllSet => 'Tout est prêt — tapez pour vérifier';

  @override
  String get permissionsNeedSetup =>
      'Tapez pour accorder les permissions requises';

  @override
  String get setupTransKey => 'Configurer TransKey';

  @override
  String get setupTransKeyBody =>
      'Accordez l\'autorisation de bulle flottante pour commencer. L\'Accessibilité est optionnelle et n\'est nécessaire que pour le collage de Réponse en un tap.';

  @override
  String get permFloatingBubble => 'Bulle flottante';

  @override
  String get permFloatingBubbleBody =>
      'Afficher TransKey au-dessus des autres apps. Requis pour que la bulle apparaisse.';

  @override
  String get permRestrictedSettings => 'Autoriser les paramètres restreints';

  @override
  String get permRestrictedSettingsBody =>
      'Android 13+ bloque par défaut l\'Accessibilité pour les apps installées hors store. Tapez ⋮ en haut à droite → \"Autoriser les paramètres restreints\".';

  @override
  String get permAccessibility => 'Accessibilité (optionnel)';

  @override
  String get permAccessibilityBody =>
      'Permet à TransKey de coller les suggestions de Réponse directement dans le champ ciblé. Ignorez si le collage manuel ne vous dérange pas.';

  @override
  String get permEnabled => 'Activé';

  @override
  String get permEnable => 'Activer';

  @override
  String get permDone => 'Terminé';

  @override
  String get permOpenAppDetails => 'Ouvrir les détails de l\'app';

  @override
  String get permSkipHint =>
      'L\'Accessibilité est optionnelle. Sans elle, les suggestions de Réponse arrivent dans le presse-papiers et vous les collez vous-même.';

  @override
  String get permSkipForNow => 'Ignorer pour l\'instant';

  @override
  String get permFinishedCheck => 'J\'ai terminé — vérifier';
}
