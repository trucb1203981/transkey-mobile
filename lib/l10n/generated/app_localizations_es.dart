// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get translate => 'Traducir';

  @override
  String get summarize => 'Resumir';

  @override
  String get explain => 'Explicar';

  @override
  String get refine => 'Refinar';

  @override
  String get reply => 'Responder';

  @override
  String get history => 'Historial';

  @override
  String get glossary => 'Glosario';

  @override
  String get settings => 'Ajustes';

  @override
  String get suggestions => 'Sugerencias';

  @override
  String get copy => 'Copiar';

  @override
  String get save => 'Guardar';

  @override
  String get copied => 'Copiado';

  @override
  String get delete => 'Eliminar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get ok => 'OK';

  @override
  String get confirm => 'Confirmar';

  @override
  String get clear => 'Borrar';

  @override
  String get dismiss => 'Descartar';

  @override
  String get required => 'Obligatorio';

  @override
  String get addAction => 'Añadir';

  @override
  String get saveAction => 'Guardar';

  @override
  String get next => 'Siguiente';

  @override
  String get skip => 'Omitir';

  @override
  String get done => 'Listo';

  @override
  String get hintEnterText => 'Introduzca el texto a traducir...';

  @override
  String detectedLang(String lang) {
    return 'Detectado: $lang';
  }

  @override
  String get autoDetect => 'Detección automática';

  @override
  String get sourceLang => 'Origen';

  @override
  String get targetLang => 'Destino';

  @override
  String get swapLanguages => 'Intercambiar idiomas';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get sectionLanguage => 'Idioma';

  @override
  String get sectionTranslation => 'Traducción';

  @override
  String get sectionAdvanced => 'Avanzado';

  @override
  String get sectionOther => 'Otros';

  @override
  String get helpImproveApp => 'Ayudar a mejorar la aplicación';

  @override
  String get helpImproveAppHint =>
      'Comparte información de uso anónima para mejorar TransKey. No se envían textos ni fotos.';

  @override
  String get sectionSpeech => 'Leer en voz alta';

  @override
  String get targetLanguage => 'Idioma destino';

  @override
  String get sourceLanguage => 'Idioma origen';

  @override
  String get appLanguage => 'Idioma de la app';

  @override
  String get saveHistory => 'Guardar historial';

  @override
  String get romanization => 'Romanización';

  @override
  String get replySuggestions => 'Sugerencias de respuesta';

  @override
  String get toneOverride => 'Tono de traducción';

  @override
  String get replyToneOverride => 'Tono de respuesta';

  @override
  String get replyLanguage => 'Idioma de respuesta';

  @override
  String get replyLanguageFromConversation => 'De la conversación';

  @override
  String get autoCloseResult => 'Cierre automático';

  @override
  String get autoCloseSeconds => 'Cierre auto (segundos)';

  @override
  String get autoCloseUnit => 'segundos';

  @override
  String get autoCloseDisabled => 'Desactivado';

  @override
  String get toneAuto => 'Auto';

  @override
  String get toneBusiness => 'Negocios';

  @override
  String get toneCasual => 'Casual';

  @override
  String get toneFormal => 'Formal';

  @override
  String get tonePolite => 'Cortés';

  @override
  String get toneTechnical => 'Técnico';

  @override
  String get toneNeutral => 'Neutral';

  @override
  String get toneReplySameAsTranslate => 'Igual que traducción';

  @override
  String get popupTo => 'A:';

  @override
  String get tabTranslate => 'Traducir';

  @override
  String get tabReply => 'Responder';

  @override
  String get tabSummarize => 'Resumir';

  @override
  String get tabExplain => 'Explicar';

  @override
  String get tabRefine => 'Refinar';

  @override
  String get keyboardSetup => 'Configurar teclado';

  @override
  String get bubbleSetup => 'Configurar burbuja';

  @override
  String get floatingBubble => 'Burbuja flotante';

  @override
  String get bubbleActive => 'Activa';

  @override
  String get bubbleInactive => 'Inactiva';

  @override
  String get sendFeedback => 'Enviar comentarios';

  @override
  String get termsOfService => 'Términos de servicio';

  @override
  String get privacyPolicy => 'Política de privacidad';

  @override
  String get version => 'Versión';

  @override
  String get upgrade => 'Actualizar';

  @override
  String get upgradeToPro => 'Actualizar a Pro';

  @override
  String get logOut => 'Cerrar sesión';

  @override
  String get changePassword => 'Cambiar contraseña';

  @override
  String get manageDevices => 'Gestionar dispositivos';

  @override
  String get manageSubscription => 'Gestionar suscripción';

  @override
  String get currentPassword => 'Contraseña actual';

  @override
  String get newPassword => 'Nueva contraseña';

  @override
  String get confirmPassword => 'Confirmar nueva contraseña';

  @override
  String get passwordTooShort =>
      'La contraseña debe tener al menos 8 caracteres';

  @override
  String get passwordMismatch => 'Las contraseñas no coinciden';

  @override
  String get changePasswordSuccess => 'Contraseña actualizada';

  @override
  String get changePasswordFailed => 'Error al actualizar la contraseña';

  @override
  String get devicesTitle => 'Dispositivos registrados';

  @override
  String get devicesEmpty => 'No hay dispositivos registrados aún.';

  @override
  String get devicesProLimit => 'El plan Pro permite hasta 2 dispositivos.';

  @override
  String get deviceCurrentThis => 'Este dispositivo';

  @override
  String deviceLastUsed(String date) {
    return 'Último uso: $date';
  }

  @override
  String get removeDevice => 'Eliminar';

  @override
  String get removeDeviceConfirm =>
      '¿Eliminar este dispositivo? Tendrá que volver a iniciar sesión.';

  @override
  String get removeDeviceFailed => 'No se pudo eliminar el dispositivo';

  @override
  String get subscriptionTitle => 'Suscripción';

  @override
  String get subscriptionStatus => 'Estado';

  @override
  String get subscriptionRenewsAt => 'Se renueva';

  @override
  String get subscriptionEndsAt => 'Termina';

  @override
  String get subscriptionTrialEndsAt => 'Fin de la prueba';

  @override
  String get subscriptionInactive => 'Sin suscripción activa';

  @override
  String get subscriptionAdminGranted =>
      'Su plan fue activado por soporte, no mediante facturación de autoservicio. Contáctenos para cambiarlo o cancelarlo.';

  @override
  String get subscriptionCancel => 'Cancelar suscripción';

  @override
  String get subscriptionCancelConfirm =>
      '¿Cancelar su suscripción Pro? Mantendrá Pro hasta el final del período actual.';

  @override
  String get subscriptionCancelled =>
      'La suscripción terminará en la fecha de renovación.';

  @override
  String get subscriptionCancelFailed => 'No se pudo cancelar la suscripción';

  @override
  String get voicePickerTitle => 'Voz';

  @override
  String get voiceDefault => 'Predeterminada';

  @override
  String get speedPickerTitle => 'Velocidad de lectura';

  @override
  String get speedNormal => 'Normal';

  @override
  String get accessibilityPasteBack => 'Pegar respuesta en otras apps';

  @override
  String get accessibilityPasteBackDesc =>
      'Active TransKey en los ajustes de Accesibilidad para que «Pegar» escriba la respuesta en el campo activo de cualquier app.';

  @override
  String get accessibilityEnabled => 'Activado';

  @override
  String get accessibilityDisabled => 'No activado — toque para abrir ajustes';

  @override
  String get feedbackTitle => 'Enviar comentarios';

  @override
  String get feedbackHint => 'Díganos qué piensa...';

  @override
  String get feedbackSend => 'Enviar';

  @override
  String get feedbackThanks => '¡Gracias por su comentario!';

  @override
  String get feedbackFailed => 'Error al enviar comentarios';

  @override
  String get feedbackCatBug => 'Reportar un error';

  @override
  String get feedbackCatFeature => 'Sugerencia de función';

  @override
  String get feedbackCatOther => 'Otro';

  @override
  String get feedbackHintBug => '¿Qué esperabas y qué pasó en su lugar?';

  @override
  String get feedbackHintFeature => '¿Qué te gustaría que TransKey haga?';

  @override
  String get feedbackHintOther => 'Comparte tu opinión...';

  @override
  String get feedbackEmailLabel => 'Correo (opcional, para responderte)';

  @override
  String get selectLanguage => 'Seleccionar idioma';

  @override
  String get searchLanguages => 'Buscar idiomas...';

  @override
  String get recent => 'Recientes';

  @override
  String get allLanguages => 'Todos los idiomas';

  @override
  String get login => 'Iniciar sesión';

  @override
  String get signUp => 'Registrarse';

  @override
  String get logIn => 'Iniciar sesión';

  @override
  String get createAccount => 'Crear cuenta';

  @override
  String get continueWithGoogle => 'Continuar con Google';

  @override
  String get orDivider => 'o';

  @override
  String get emailHint => 'Correo electrónico';

  @override
  String get passwordHint => 'Contraseña';

  @override
  String get nameHint => 'Su nombre';

  @override
  String get nameRequired => 'El nombre es obligatorio';

  @override
  String get emailRequired => 'El correo es obligatorio';

  @override
  String get emailInvalid => 'Introduzca un correo válido';

  @override
  String get passwordRequired => 'La contraseña es obligatoria';

  @override
  String get passwordMinSix => 'Al menos 6 caracteres';

  @override
  String get proDeviceLimitError =>
      'La cuenta Pro ya está registrada en el máximo de dispositivos';

  @override
  String get deviceLimitError => 'Demasiadas cuentas en este dispositivo';

  @override
  String googleSignInFailed(String error) {
    return 'Inicio de sesión de Google fallido: $error';
  }

  @override
  String get googleNotConfigured =>
      'El inicio de sesión con Google no está disponible. Prueba otra forma de iniciar sesión.';

  @override
  String get googleSignInNoIdToken =>
      'El inicio de sesión con Google no se completó. Inténtalo de nuevo.';

  @override
  String get proRequired => 'Se requiere plan Pro';

  @override
  String get noTextToTranslate => 'Introduzca texto primero';

  @override
  String get errorGeneric => 'Algo salió mal';

  @override
  String get errorSessionExpired => 'Sesión caducada — inicia sesión de nuevo';

  @override
  String get errorInvalidCredentials => 'Correo o contraseña incorrectos';

  @override
  String get errorEmailNotVerified =>
      'Verifica tu correo — revisa tu bandeja de entrada';

  @override
  String get errorFeatureRequiresPaid =>
      'Esta función requiere un plan de pago';

  @override
  String get errorDeviceLimit =>
      'Límite de dispositivos alcanzado — elimina uno o mejora tu plan';

  @override
  String get errorMobilePlanDesktopBlocked =>
      'El plan Mobile no se puede usar en escritorio';

  @override
  String get errorTextTooLong => 'Texto demasiado largo (máx. 5000 caracteres)';

  @override
  String get errorQuotaExceeded =>
      'Cuota diaria alcanzada — inténtalo mañana o mejora tu plan';

  @override
  String get errorRateLimit => 'Demasiadas solicitudes — espera un momento';

  @override
  String get errorMaintenance => 'Servicio en mantenimiento';

  @override
  String get errorNetwork => 'Sin conexión a internet';

  @override
  String get glossaryErrSyncFailed =>
      'No se pudo sincronizar el glosario — comprueba la conexión';

  @override
  String glossaryErrLimitReached(int max) {
    return 'Glosario lleno (máx. $max entradas)';
  }

  @override
  String get glossaryErrSourceTargetRequired =>
      'Origen y destino son obligatorios';

  @override
  String get planFree => 'Gratis';

  @override
  String get planPro => 'Pro';

  @override
  String get planMobile => 'Mobile';

  @override
  String get planTrial => 'Prueba';

  @override
  String usageRequests(int used, int limit) {
    return '$used/$limit solicitudes';
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
      other: 'días',
      one: 'día',
    );
    return 'Prueba termina en $days $_temp0';
  }

  @override
  String get trialEndsToday => 'La prueba termina hoy';

  @override
  String get trialEndsTomorrow => 'La prueba termina mañana';

  @override
  String get trialUpgradeNow => 'Actualizar ahora';

  @override
  String get trialAlreadyUsed => 'Ya ha usado su prueba gratuita';

  @override
  String get subscriptionExpiredBanner => 'Su suscripción ha expirado';

  @override
  String get subscriptionExpiredRenew => 'Renovar';

  @override
  String subscriptionEndsOn(String date) {
    return 'Termina el $date';
  }

  @override
  String get planMobileSubscription => 'Suscripción Mobile';

  @override
  String get planProSubscription => 'Suscripción Pro';

  @override
  String get discountFirstMonth => '−50 % el primer mes';

  @override
  String get accountBannedTitle => 'Cuenta suspendida';

  @override
  String get accountBannedBody =>
      'Su cuenta TransKey ha sido suspendida. Contacte con soporte si cree que es un error.';

  @override
  String get accountBannedContact => 'Contactar soporte';

  @override
  String get accountBannedLogout => 'Cerrar sesión';

  @override
  String get historyTitle => 'Historial';

  @override
  String get historySearchHint => 'Buscar en el historial...';

  @override
  String get historyFilterAll => 'Todo';

  @override
  String get historyFilterFavorites => '★ Favoritos';

  @override
  String get historyFilterLocked => '🔒 Bloqueados';

  @override
  String get historyMenuClearAll => 'Borrar todo';

  @override
  String get historyMenuKeepFavorites => 'Mantener solo favoritos';

  @override
  String get historyClearDialogTitle => 'Borrar historial';

  @override
  String get historyClearDialogBody =>
      '¿Eliminar todo el historial? Las entradas bloqueadas se conservarán.';

  @override
  String get historyKeepFavDialogBody =>
      '¿Eliminar todas las entradas no favoritas? Las entradas bloqueadas se conservarán.';

  @override
  String get historyDetailSourceLabel => 'Origen';

  @override
  String get historyDetailTranslationLabel => 'Traducción';

  @override
  String get historyDetailRomanizationLabel => 'Romanización';

  @override
  String get historyDetailFavoriteBadge => '★ Favorito';

  @override
  String get historyDetailLockedBadge => '🔒 Bloqueado';

  @override
  String get historyDetailCopyTranslation => 'Copiar\ntraducción';

  @override
  String get historyDetailCopySource => 'Copiar\norigen';

  @override
  String get historyDetailUnfavorite => 'Quitar favorito';

  @override
  String get historyDetailFavoriteAction => 'Favorito';

  @override
  String get historyDetailUnlock => 'Desbloquear';

  @override
  String get historyDetailLockAction => 'Bloquear';

  @override
  String get historyDetailTtsLabel => 'TTS';

  @override
  String glossaryTitle(int count, int max) {
    return 'Glosario ($count/$max)';
  }

  @override
  String get glossarySync => 'Sincronizar';

  @override
  String get glossaryDeleteTitle => 'Eliminar entrada';

  @override
  String glossaryDeleteBody(String source) {
    return '¿Eliminar «$source»?';
  }

  @override
  String glossaryLimitReached(int max) {
    return 'Límite del glosario alcanzado ($max)';
  }

  @override
  String get glossarySourceTargetRequired =>
      'Origen y destino son obligatorios';

  @override
  String get glossarySyncFailed => 'Error al sincronizar el glosario';

  @override
  String get glossaryEditTitle => 'Editar entrada';

  @override
  String get glossaryAddTitle => 'Añadir entrada';

  @override
  String get glossarySourceLabel => 'Origen';

  @override
  String get glossarySourceHint => 'Palabra o frase';

  @override
  String get glossaryTargetLabel => 'Destino';

  @override
  String get glossaryTargetHint => 'Traducción';

  @override
  String get glossaryNamesLabel => 'Nombres del glosario — toca para insertar';

  @override
  String get glossaryIsNameLabel => 'Es el nombre de una persona';

  @override
  String get glossaryIsNameHint =>
      'Ayuda a la entrada de voz a reconocer el nombre y lo mantiene sin cambios al traducir.';

  @override
  String get upgradeScreenTitle => 'Actualizar TransKey';

  @override
  String get upgradeChooseYourPlan => 'Elija su plan';

  @override
  String get upgradeUnlockFullPower => 'Desbloquee todo el poder de TransKey';

  @override
  String get upgradeCurrentLabel => 'Actual';

  @override
  String get upgradePopularBadge => 'Popular';

  @override
  String get upgradeTryFreeDays => 'Pruebe gratis 7 días';

  @override
  String upgradeTrialActivated(String info) {
    return '¡Prueba activada! $info';
  }

  @override
  String get upgradeTrialActivateFailed => 'Error al activar la prueba';

  @override
  String get upgradeCheckoutFailed => 'Error al abrir el pago';

  @override
  String get upgradeMobileSubtitle => 'Todas las funciones, solo móvil';

  @override
  String get upgradeProSubtitle => 'Todas las funciones, todas las plataformas';

  @override
  String get upgradeFreeFeat1 => 'Traducir';

  @override
  String get upgradeFreeFeat2 => '20 sol./día';

  @override
  String get upgradeFreeFeat3 => '2000 car./día';

  @override
  String get upgradeFreeFeat4 => 'Glosario';

  @override
  String get upgradeMobileFeat1 => 'Todas las funciones';

  @override
  String get upgradeMobileFeat2 => 'iOS y Android';

  @override
  String get upgradeMobileFeat3 => 'Ilimitado';

  @override
  String get upgradeProFeat1 => 'Todas las funciones';

  @override
  String get upgradeProFeat2 => 'Todas las plataformas';

  @override
  String get upgradeProFeat3 => 'Escritorio + Móvil';

  @override
  String get upgradeFeatureColumn => 'Función';

  @override
  String upgradeMobilePrice(Object price) {
    return '📱 Mobile · $price/mes';
  }

  @override
  String get upgradeProPrice => '💻 Pro · 6 \$/mes';

  @override
  String get upgradeFooterHint =>
      '📱 Mobile: mejor valor si solo usa su teléfono\n💻 Pro: funciona en teléfono y escritorio';

  @override
  String get comparisonReplyTranslate => 'Traducción de respuesta';

  @override
  String get comparisonMobileApps => '📱 iOS y Android';

  @override
  String get comparisonDesktop => '💻 Escritorio';

  @override
  String nudgeUnlock(String feature) {
    return 'Desbloquear $feature';
  }

  @override
  String get nudgeMobileCopy =>
      'Actualice a Pro para usar esta función\nen todas las plataformas.';

  @override
  String get nudgeChoosePlan =>
      'Elija un plan que se ajuste a sus necesidades.';

  @override
  String get nudgeMaybeLater => 'Quizás más tarde';

  @override
  String get nudgeMobileTitle => '📱 Mobile';

  @override
  String get nudgeProTitle => '💻 Pro';

  @override
  String get nudgeUpgradeToPro => 'Actualizar a Pro';

  @override
  String get nudgeUpgradeToProSubtitle =>
      'Use en todas las plataformas — escritorio + móvil';

  @override
  String nudgePriceMobile(String price) {
    return '$price/mes';
  }

  @override
  String nudgePriceProMonthly(String price) {
    return '$price/mes';
  }

  @override
  String get onboardWelcomeTitle => 'Bienvenido a TransKey';

  @override
  String get onboardWelcomeSubtitle =>
      'Traduzca texto en tiempo real en\nmás de 20 idiomas al instante.';

  @override
  String get onboardChooseTitle => 'Elija su idioma';

  @override
  String get onboardChooseSubtitle =>
      'Elija su idioma destino preferido.\nPuede cambiarlo en cualquier momento en ajustes.';

  @override
  String get onboardStartedTitle => 'Empezar';

  @override
  String get onboardStartedSubtitle =>
      'Inicie sesión o cree una cuenta gratuita\npara empezar a traducir ahora.';

  @override
  String get onboardGetStarted => 'Empezar';

  @override
  String get setupTitle => 'Configurar teclado';

  @override
  String get setupOpenSettings => 'Abrir ajustes';

  @override
  String get setupOpenPermissions => 'Abrir permisos';

  @override
  String get setupStep1TitleIOS => 'Añadir teclado TransKey';

  @override
  String get setupStep1TitleAndroid => 'Activar burbuja flotante';

  @override
  String get setupStep1DescIOS =>
      'Vaya a Ajustes y añada TransKey como teclado personalizado para traducir directamente mientras escribe.';

  @override
  String get setupStep1DescAndroid =>
      'Permita que TransKey se muestre sobre otras apps para que la burbuja flotante aparezca cuando la necesite.';

  @override
  String get setupStep2Title => 'Permitir acceso completo';

  @override
  String get setupStep2DescIOS =>
      'Toque TransKey en la lista de teclados y active «Permitir acceso completo». Necesario para conectarse a Internet para las traducciones.';

  @override
  String get setupStep2DescAndroid =>
      'El permiso de superposición permite a TransKey mostrar una burbuja flotante sobre otras apps para traducciones rápidas.';

  @override
  String get setupStep3Title => '¡Todo listo!';

  @override
  String get setupStep3DescIOS =>
      'Al escribir en cualquier app, mantenga la tecla del globo 🌐 para cambiar a TransKey. Toque «Responder» para traducir su mensaje al instante.';

  @override
  String get setupStep3DescAndroid =>
      'Seleccione texto en cualquier app y compártalo con TransKey, o use la burbuja flotante para traducciones rápidas.';

  @override
  String get setupStep4Title => 'Traducir desde cualquier app';

  @override
  String get setupStep4DescIOS =>
      'Seleccione texto → toque «Compartir» → elija TransKey. O copie texto y abra TransKey — lee su portapapeles automáticamente.';

  @override
  String get setupStep4DescAndroid =>
      'Seleccione texto en cualquier app → toque «Compartir» → elija TransKey. O use la burbuja flotante después de copiar texto.';

  @override
  String get setupStep5Title => 'Funciones inteligentes';

  @override
  String get setupStep5Desc =>
      'Traducir, Responder, Resumir, Explicar y Refinar — todo con IA. Las funciones Pro están marcadas con un candado.';

  @override
  String get guideTitle => 'Cómo usar';

  @override
  String get guideSubtitle =>
      'Todas las formas de capturar texto para cada función';

  @override
  String get guideIntroTitle =>
      'No se necesita ningún permiso especial para capturar texto.';

  @override
  String get guideIntroBody =>
      'Cada función solo lee el texto cuando haces algo a propósito — copiar texto, escanear la pantalla, seleccionar un área, usar el botón Compartir del sistema, o tocar TransKey desde el menú de selección. La Accesibilidad se usa solo para que el resultado de Reply se pegue directamente en el chat en el que estás escribiendo.';

  @override
  String get guideFeatureTranslate => 'Traducir';

  @override
  String get guideFeatureTranslateSubtitle => 'Idioma origen → idioma destino';

  @override
  String get guideFeatureSummary => 'Resumir';

  @override
  String get guideFeatureSummarySubtitle =>
      'Condensar contenido largo en unos pocos puntos';

  @override
  String get guideFeatureRefine => 'Refinar';

  @override
  String get guideFeatureRefineSubtitle =>
      'Mejorar la gramática / claridad de tu propio borrador';

  @override
  String get guideFeatureExplain => 'Explicar';

  @override
  String get guideFeatureExplainSubtitle =>
      'Obtener una explicación sencilla de un texto difícil';

  @override
  String get guideFeatureReply => 'Responder';

  @override
  String get guideFeatureReplySubtitle =>
      'Generar una sugerencia de respuesta en el idioma destino';

  @override
  String get guideInputCopyTitle => 'Copiar texto, luego tocar la burbuja';

  @override
  String get guideInputCopyDesc =>
      'Copia texto en cualquier app, luego toca la burbuja flotante y elige la acción.';

  @override
  String get guideInputOcrTitle => 'Escanear toda la pantalla';

  @override
  String get guideInputOcrDesc =>
      'Toca la burbuja → Escanear pantalla. TransKey toma una captura y lee el texto que aparece.';

  @override
  String get guideInputRegionTitle => 'Escanear parte de la pantalla';

  @override
  String get guideInputRegionDesc =>
      'Toca la burbuja → Escanear área. Arrastra un recuadro alrededor de lo que quieras traducir.';

  @override
  String get guideInputShareTitle => 'Desde el botón Compartir';

  @override
  String get guideInputShareDesc =>
      'En cualquier app: selecciona texto → toca Compartir → elige TransKey.';

  @override
  String guideInputMenuTitle(String feature) {
    return 'Desde el menú de selección → TransKey: $feature';
  }

  @override
  String guideInputMenuDesc(String feature) {
    return 'Selecciona texto en cualquier app — aparece el menú Copiar/Compartir. Toca ⋮ para más opciones, y elige TransKey: $feature.';
  }

  @override
  String get guideReplyA11yTitle =>
      'Accesibilidad — opcional, solo para pegado automático';

  @override
  String get guideReplyA11yBody =>
      'Si Accesibilidad está activada para TransKey, tu respuesta se pega directamente en el chat en el que estás escribiendo. Sin pasos extra.\n\nSi prefieres no activarla, la respuesta se copia para ti — solo mantén pulsado el chat y toca Pegar.';

  @override
  String get appPermissions => 'Permisos de la app';

  @override
  String get permissionsAllSet => 'Todo listo — toca para revisar';

  @override
  String get permissionsNeedSetup =>
      'Toca para conceder los permisos necesarios';

  @override
  String get setupTransKey => 'Configurar TransKey';

  @override
  String get setupTransKeyBody =>
      'Concede el permiso de burbuja flotante para empezar. La Accesibilidad es opcional y solo se necesita para pegar Respuesta con un toque.';

  @override
  String get permFloatingBubble => 'Burbuja flotante';

  @override
  String get permFloatingBubbleBody =>
      'Mostrar TransKey sobre otras apps. Necesario para que la burbuja aparezca.';

  @override
  String get permRestrictedSettings => 'Permitir configuración restringida';

  @override
  String get permRestrictedSettingsBody =>
      'Android 13+ bloquea por defecto la Accesibilidad para apps sideload. Toca ⋮ arriba a la derecha → \"Permitir configuración restringida\".';

  @override
  String get permAccessibility => 'Accesibilidad (opcional)';

  @override
  String get permAccessibilityBody =>
      'Permite a TransKey pegar sugerencias de Respuesta directamente en el campo enfocado. Omite si no te importa pegar manualmente.';

  @override
  String get permEnabled => 'Activado';

  @override
  String get permEnable => 'Activar';

  @override
  String get permDone => 'Hecho';

  @override
  String get permOpenAppDetails => 'Abrir detalles de la app';

  @override
  String get permSkipHint =>
      'La Accesibilidad es opcional. Sin ella, las sugerencias de Respuesta van al portapapeles y las pegas tú.';

  @override
  String get permSkipForNow => 'Omitir por ahora';

  @override
  String get permFinishedCheck => 'He terminado — comprobar';

  @override
  String get voiceTooltip => 'Hablar para escribir';

  @override
  String get voiceListening => 'Escuchando…';

  @override
  String get voiceNeedsLang =>
      'Establece un idioma de origen específico para usar la voz';

  @override
  String get voicePermDenied => 'Permiso de micrófono denegado';

  @override
  String get voiceUnsupported =>
      'Entrada de voz no disponible en este dispositivo';

  @override
  String get voicePickSourceLang =>
      'Selecciona primero un idioma de origen — la entrada de voz no puede auto-detectar';

  @override
  String get paywallTitle => 'Límite diario alcanzado';

  @override
  String get paywallBody =>
      'Has usado tu cuota gratuita de hoy: 20 solicitudes / 2.000 caracteres. Mira un anuncio corto para seguir, o mejora tu plan para uso ilimitado. Tu cuota gratuita se restablece a medianoche.';

  @override
  String get paywallWatchAdCta => 'Ver anuncio para continuar';

  @override
  String get paywallWatchAdSub =>
      'Gana solicitudes y caracteres adicionales con cada anuncio. Sin límite de anuncios al día.';

  @override
  String get paywallUpgradeCta => 'Mejorar — ilimitado, sin anuncios';

  @override
  String paywallUpgradeSub(String price) {
    return 'Desde $price/mes. Cancela cuando quieras.';
  }

  @override
  String get paywallDismiss => 'Quizá más tarde';

  @override
  String get paywallLoading => 'Cargando…';

  @override
  String get paywallAdNotComplete =>
      'No completaste el anuncio — vuelve a intentarlo para ganar la recompensa.';

  @override
  String get paywallCreditFailed =>
      'No se pudo acreditar la recompensa. Inténtalo en un momento.';

  @override
  String get quotaWatchAd => '+ Ver anuncio';

  @override
  String get quotaRewardGranted => 'Recompensa acreditada a la cuota de hoy';

  @override
  String get historyEmpty => 'Aún no hay historial de traducciones';

  @override
  String get glossaryEmpty => 'El glosario está vacío';

  @override
  String get glossaryEmptyAddCta => 'Añadir entrada';

  @override
  String get captureKeepaliveTitle => 'Ventana de re-captura rápida';

  @override
  String get captureKeepaliveHint => 'doble toque = re-escanear';

  @override
  String get captureKeepaliveExplain =>
      'Tras una captura, conserva el permiso de captura de pantalla durante este tiempo para que un doble toque (o seleccionar Lens otra vez) no pida permiso al sistema de nuevo. Más tiempo = menos toques, pero el indicador de transmisión queda visible y el dispositivo se calienta un poco.';

  @override
  String get captureKeepaliveOff => 'Desactivado';

  @override
  String get captureKeepaliveOffHint =>
      'Cada captura pide permiso de nuevo. Mejor para privacidad y batería.';

  @override
  String get captureKeepaliveDefaultHint =>
      'Recomendado — equilibra velocidad y batería.';

  @override
  String get captureKeepaliveShortHint =>
      'Menos tiempo de transmisión, pero más solicitudes de permiso.';

  @override
  String get captureKeepaliveLongHint =>
      'Re-captura más rápida. El indicador queda visible más tiempo.';

  @override
  String captureKeepaliveMinutes(int count) {
    return '$count min';
  }

  @override
  String get cameraTitle => 'Cámara';

  @override
  String get cameraCapture => 'Capturar';

  @override
  String get cameraRetake => 'Repetir';

  @override
  String get cameraCopyAll => 'Copiar todo';

  @override
  String get cameraNoText => 'No se detectó texto. Inténtalo de nuevo.';

  @override
  String get cameraTapShowTranslations => 'Toque para mostrar las traducciones';

  @override
  String get cameraLowQuality => 'Baja calidad';

  @override
  String get cameraTranslating => 'Traduciendo...';

  @override
  String get cameraTranslate => 'Traducir';

  @override
  String get cameraPermission =>
      'Se necesita permiso de cámara para usar esta función.';

  @override
  String get cameraSettingsTitle => 'Ajustes de la cámara';

  @override
  String get cameraSettingsReset => 'Restablecer';

  @override
  String get cameraSettingsConfidence => 'Ocultar texto poco claro';

  @override
  String get cameraSettingsConfidenceHint =>
      'Oculta el texto que la cámara lee mal. Más alto = más estricto — resultados más limpios, pero puede omitir texto tenue.';

  @override
  String get cameraOriginalLabel => 'Original';

  @override
  String get cameraSettingsHideLow => 'Ocultar bloques de baja calidad';

  @override
  String get cameraSettingsHideLowHint =>
      'Ocultar también bloques sobre el umbral pero bajo el nivel de advertencia. Para documentos limpios.';

  @override
  String get cameraSettingsShowOriginal => 'Mostrar texto original';

  @override
  String get cameraSettingsShowOriginalHint =>
      'Mostrar siempre el texto fuente bajo cada tarjeta de traducción.';

  @override
  String get cameraSettingsOpacity => 'Opacidad de la superposición';

  @override
  String get cameraSettingsOpacityHint =>
      'Transparencia del fondo de la tarjeta. Más bajo = la foto detrás se ve más.';

  @override
  String get cameraSceneAuto => 'Auto';

  @override
  String get cameraSceneDocument => 'Documento';

  @override
  String get cameraSceneMenu => 'Menú';

  @override
  String get cameraSceneSign => 'Letrero';

  @override
  String get cameraSceneScreenshot => 'Captura de pantalla';

  @override
  String get cameraWhatIsThis => '¿Qué es esto?';

  @override
  String get cameraWhatIsThisHint =>
      'Toca un texto en la vista previa para preguntar';

  @override
  String get cameraExplainTitle => '¿Qué es esto?';

  @override
  String get cameraEditTextTitle => 'Editar texto';

  @override
  String get cameraReExplain => 'Volver a explicar';

  @override
  String get cameraExplainEmpty => 'No hay explicación disponible.';

  @override
  String get cameraExplainError =>
      'No se pudo obtener la explicación. Inténtalo de nuevo.';

  @override
  String get cameraResultExplainHint =>
      'Mantén pulsada una tarjeta para preguntar';

  @override
  String get cameraExplainDisclaimer =>
      'Solo referencia — el significado real puede diferir';

  @override
  String get phrasebookTitle => 'Cuaderno de frases';

  @override
  String get phrasebookEmpty =>
      'Tu cuaderno está vacío. Usa la cámara para identificar texto y toca Guardar.';

  @override
  String get phrasebookSave => 'Guardar';

  @override
  String get phrasebookSaved => 'Guardado';

  @override
  String get phrasebookSaveFailed => 'No se pudo guardar. Inténtalo de nuevo.';

  @override
  String get phrasebookTitleTooLong =>
      'Título demasiado largo (máx 1000 caracteres). Acórtalo e inténtalo de nuevo.';

  @override
  String get phrasebookDelete => 'Eliminar';

  @override
  String get phrasebookDeleteConfirm => '¿Eliminar este elemento del cuaderno?';

  @override
  String get phrasebookDeleted => 'Eliminado';

  @override
  String get phrasebookNote => 'Nota';

  @override
  String get phrasebookNoteHint => 'ej.: pedido en ... — muy picante';

  @override
  String get phrasebookNoteSave => 'Guardar nota';

  @override
  String get phrasebookCopy => 'Copiar';

  @override
  String get phrasebookViewAll => 'Abrir cuaderno';

  @override
  String get phrasebookCategoryAll => 'Todo';

  @override
  String get phrasebookCategoryMenu => 'Menú';

  @override
  String get phrasebookCategoryPlace => 'Lugar';

  @override
  String get phrasebookCategoryDocument => 'Documento';

  @override
  String get phrasebookCategoryOther => 'Otro';

  @override
  String get phrasebookCategoryChange => 'Cambiar categoría';

  @override
  String get cameraTipsTitle => 'Consejos de cámara';

  @override
  String get cameraTipsGotIt => 'Entendido';

  @override
  String get cameraTip1Title => 'Elige el modo';

  @override
  String get cameraTip1Body =>
      'Elige lo que escaneas para el mejor resultado: un menú, un letrero, un documento — o Auto para todo.';

  @override
  String get cameraTip2Title => 'Elige tus idiomas';

  @override
  String get cameraTip2Body =>
      'Indica el idioma que lees y al que traducir (arriba a la izquierda). Si un letrero o texto no sale bien, elige el idioma de lectura en vez de Auto.';

  @override
  String get cameraTip3Title => 'Pregunta \"¿Qué es esto?\"';

  @override
  String get cameraTip3Body =>
      'Mantén pulsado un resultado para saber qué es un plato o lugar — y oír cómo se pronuncia.';

  @override
  String get cameraTip4Title => 'Arrastra para quitar';

  @override
  String get cameraTip4Body =>
      'Arrastra una tarjeta a la papelera de abajo para quitar los bloques que no necesites.';

  @override
  String get cameraTip5Title => 'Escanea una foto guardada';

  @override
  String get cameraTip5Body =>
      'Toca el icono de galería junto al obturador para traducir una foto que ya tienes en el teléfono.';
}
