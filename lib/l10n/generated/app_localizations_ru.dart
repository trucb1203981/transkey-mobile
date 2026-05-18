// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get translate => 'Перевести';

  @override
  String get summarize => 'Кратко изложить';

  @override
  String get explain => 'Объяснить';

  @override
  String get refine => 'Улучшить';

  @override
  String get reply => 'Ответить';

  @override
  String get history => 'История';

  @override
  String get glossary => 'Словарь';

  @override
  String get settings => 'Настройки';

  @override
  String get suggestions => 'Подсказки';

  @override
  String get copy => 'Копировать';

  @override
  String get save => 'Сохранить';

  @override
  String get copied => 'Скопировано';

  @override
  String get delete => 'Удалить';

  @override
  String get cancel => 'Отмена';

  @override
  String get ok => 'OK';

  @override
  String get confirm => 'Подтвердить';

  @override
  String get clear => 'Очистить';

  @override
  String get dismiss => 'Закрыть';

  @override
  String get required => 'Обязательно';

  @override
  String get addAction => 'Добавить';

  @override
  String get saveAction => 'Сохранить';

  @override
  String get next => 'Далее';

  @override
  String get skip => 'Пропустить';

  @override
  String get done => 'Готово';

  @override
  String get hintEnterText => 'Введите текст для перевода...';

  @override
  String detectedLang(String lang) {
    return 'Обнаружено: $lang';
  }

  @override
  String get autoDetect => 'Автоопределение';

  @override
  String get sourceLang => 'Исходный';

  @override
  String get targetLang => 'Целевой';

  @override
  String get swapLanguages => 'Поменять языки';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get sectionLanguage => 'Язык';

  @override
  String get sectionTranslation => 'Перевод';

  @override
  String get sectionAdvanced => 'Дополнительно';

  @override
  String get sectionOther => 'Другое';

  @override
  String get sectionSpeech => 'Озвучивание';

  @override
  String get targetLanguage => 'Целевой язык';

  @override
  String get sourceLanguage => 'Исходный язык';

  @override
  String get appLanguage => 'Язык приложения';

  @override
  String get saveHistory => 'Сохранять историю';

  @override
  String get romanization => 'Латинизация';

  @override
  String get replySuggestions => 'Подсказки для ответов';

  @override
  String get toneOverride => 'Тон перевода';

  @override
  String get replyToneOverride => 'Тон ответа';

  @override
  String get replyLanguage => 'Язык ответа';

  @override
  String get replyLanguageFromConversation => 'Из переписки';

  @override
  String get autoCloseResult => 'Автозакрытие результата';

  @override
  String get autoCloseSeconds => 'Автозакрытие (секунд)';

  @override
  String get autoCloseUnit => 'сек.';

  @override
  String get autoCloseDisabled => 'Выкл.';

  @override
  String get toneAuto => 'Авто';

  @override
  String get toneBusiness => 'Деловой';

  @override
  String get toneCasual => 'Непринуждённый';

  @override
  String get toneFormal => 'Формальный';

  @override
  String get tonePolite => 'Вежливый';

  @override
  String get toneTechnical => 'Технический';

  @override
  String get toneNeutral => 'Нейтральный';

  @override
  String get toneReplySameAsTranslate => 'Как при переводе';

  @override
  String get popupTo => 'Кому:';

  @override
  String get tabTranslate => 'Перевести';

  @override
  String get tabReply => 'Ответить';

  @override
  String get tabSummarize => 'Резюме';

  @override
  String get tabExplain => 'Объяснить';

  @override
  String get tabRefine => 'Улучшить';

  @override
  String get keyboardSetup => 'Настройка клавиатуры';

  @override
  String get bubbleSetup => 'Настройка плавающей кнопки';

  @override
  String get floatingBubble => 'Плавающая кнопка';

  @override
  String get bubbleActive => 'Активна';

  @override
  String get bubbleInactive => 'Неактивна';

  @override
  String get sendFeedback => 'Отправить отзыв';

  @override
  String get termsOfService => 'Условия использования';

  @override
  String get privacyPolicy => 'Политика конфиденциальности';

  @override
  String get version => 'Версия';

  @override
  String get upgrade => 'Обновить';

  @override
  String get upgradeToPro => 'Перейти на Pro';

  @override
  String get logOut => 'Выйти';

  @override
  String get changePassword => 'Сменить пароль';

  @override
  String get manageDevices => 'Управление устройствами';

  @override
  String get manageSubscription => 'Управление подпиской';

  @override
  String get currentPassword => 'Текущий пароль';

  @override
  String get newPassword => 'Новый пароль';

  @override
  String get confirmPassword => 'Подтвердите новый пароль';

  @override
  String get passwordTooShort => 'Пароль должен содержать минимум 8 символов';

  @override
  String get passwordMismatch => 'Пароли не совпадают';

  @override
  String get changePasswordSuccess => 'Пароль обновлён';

  @override
  String get changePasswordFailed => 'Не удалось обновить пароль';

  @override
  String get devicesTitle => 'Зарегистрированные устройства';

  @override
  String get devicesEmpty => 'Устройств пока нет.';

  @override
  String get devicesProLimit => 'Тариф Pro допускает до 2 устройств.';

  @override
  String get deviceCurrentThis => 'Это устройство';

  @override
  String deviceLastUsed(String date) {
    return 'Последнее использование: $date';
  }

  @override
  String get removeDevice => 'Удалить';

  @override
  String get removeDeviceConfirm =>
      'Удалить это устройство? Ему потребуется войти заново.';

  @override
  String get removeDeviceFailed => 'Не удалось удалить устройство';

  @override
  String get subscriptionTitle => 'Подписка';

  @override
  String get subscriptionStatus => 'Статус';

  @override
  String get subscriptionRenewsAt => 'Продлевается';

  @override
  String get subscriptionEndsAt => 'Заканчивается';

  @override
  String get subscriptionTrialEndsAt => 'Пробный период до';

  @override
  String get subscriptionInactive => 'Активная подписка отсутствует';

  @override
  String get subscriptionAdminGranted =>
      'Ваш тариф активирован службой поддержки, а не через самостоятельную оплату. Свяжитесь с нами для изменения или отмены.';

  @override
  String get subscriptionCancel => 'Отменить подписку';

  @override
  String get subscriptionCancelConfirm =>
      'Отменить подписку Pro? Pro останется до конца текущего периода.';

  @override
  String get subscriptionCancelled => 'Подписка закончится в день продления.';

  @override
  String get subscriptionCancelFailed => 'Не удалось отменить подписку';

  @override
  String get voicePickerTitle => 'Голос';

  @override
  String get voiceDefault => 'По умолчанию';

  @override
  String get speedPickerTitle => 'Скорость речи';

  @override
  String get speedNormal => 'Обычная';

  @override
  String get accessibilityPasteBack => 'Вставлять ответ в другие приложения';

  @override
  String get accessibilityPasteBackDesc =>
      'Включите TransKey в настройках Специальных возможностей, чтобы «Вставить» записывал ответ в активное поле любого приложения.';

  @override
  String get accessibilityEnabled => 'Включено';

  @override
  String get accessibilityDisabled =>
      'Не включено — нажмите, чтобы открыть настройки';

  @override
  String get feedbackTitle => 'Отправить отзыв';

  @override
  String get feedbackHint => 'Расскажите, что вы думаете...';

  @override
  String get feedbackSend => 'Отправить';

  @override
  String get feedbackThanks => 'Спасибо за ваш отзыв!';

  @override
  String get feedbackFailed => 'Не удалось отправить отзыв';

  @override
  String get feedbackCatBug => 'Сообщить об ошибке';

  @override
  String get feedbackCatFeature => 'Запрос функции';

  @override
  String get feedbackCatOther => 'Другое';

  @override
  String get feedbackHintBug => 'Что вы ожидали и что произошло вместо этого?';

  @override
  String get feedbackHintFeature => 'Что бы вы хотели, чтобы TransKey умел?';

  @override
  String get feedbackHintOther => 'Поделитесь своими мыслями...';

  @override
  String get feedbackEmailLabel => 'Email (необязательно, для ответа)';

  @override
  String get selectLanguage => 'Выберите язык';

  @override
  String get searchLanguages => 'Поиск языков...';

  @override
  String get recent => 'Недавние';

  @override
  String get allLanguages => 'Все языки';

  @override
  String get login => 'Войти';

  @override
  String get signUp => 'Регистрация';

  @override
  String get logIn => 'Войти';

  @override
  String get createAccount => 'Создать аккаунт';

  @override
  String get continueWithGoogle => 'Продолжить с Google';

  @override
  String get orDivider => 'или';

  @override
  String get emailHint => 'Email';

  @override
  String get passwordHint => 'Пароль';

  @override
  String get nameHint => 'Ваше имя';

  @override
  String get nameRequired => 'Имя обязательно';

  @override
  String get emailRequired => 'Email обязателен';

  @override
  String get emailInvalid => 'Введите корректный email';

  @override
  String get passwordRequired => 'Пароль обязателен';

  @override
  String get passwordMinSix => 'Минимум 6 символов';

  @override
  String get proDeviceLimitError =>
      'Аккаунт Pro уже зарегистрирован на максимальном числе устройств';

  @override
  String get deviceLimitError => 'Слишком много аккаунтов на этом устройстве';

  @override
  String googleSignInFailed(String error) {
    return 'Ошибка входа через Google: $error';
  }

  @override
  String get googleNotConfigured =>
      'Вход через Google не настроен (отсутствует serverClientId)';

  @override
  String get googleSignInNoIdToken =>
      'Вход через Google не вернул idToken — проверьте serverClientId';

  @override
  String get proRequired => 'Требуется тариф Pro';

  @override
  String get noTextToTranslate => 'Сначала введите текст';

  @override
  String get errorGeneric => 'Что-то пошло не так';

  @override
  String get errorSessionExpired => 'Сессия истекла — войдите снова';

  @override
  String get errorInvalidCredentials => 'Неверная почта или пароль';

  @override
  String get errorEmailNotVerified => 'Подтвердите email — проверьте почту';

  @override
  String get errorFeatureRequiresPaid => 'Эта функция требует платного тарифа';

  @override
  String get errorDeviceLimit =>
      'Достигнут лимит устройств — удалите устройство или обновите тариф';

  @override
  String get errorMobilePlanDesktopBlocked =>
      'Тариф Mobile нельзя использовать на десктопе';

  @override
  String get errorTextTooLong =>
      'Текст слишком длинный (максимум 5000 символов)';

  @override
  String get errorQuotaExceeded =>
      'Дневной лимит исчерпан — попробуйте завтра или обновите тариф';

  @override
  String get errorRateLimit => 'Слишком много запросов — подождите немного';

  @override
  String get errorMaintenance => 'Сервис на техническом обслуживании';

  @override
  String get errorNetwork => 'Нет подключения к интернету';

  @override
  String get glossaryErrSyncFailed =>
      'Не удалось синхронизировать словарь — проверьте подключение';

  @override
  String glossaryErrLimitReached(int max) {
    return 'Словарь заполнен (максимум $max записей)';
  }

  @override
  String get glossaryErrSourceTargetRequired =>
      'Источник и перевод обязательны';

  @override
  String get planFree => 'Бесплатно';

  @override
  String get planPro => 'Pro';

  @override
  String get planMobile => 'Mobile';

  @override
  String get planTrial => 'Пробный';

  @override
  String usageRequests(int used, int limit) {
    return '$used/$limit запросов';
  }

  @override
  String usageCharacters(int used, int limit) {
    return '$used/$limit символов';
  }

  @override
  String trialEndsInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'дня',
      many: 'дней',
      few: 'дня',
      one: 'день',
    );
    return 'Пробный период заканчивается через $days $_temp0';
  }

  @override
  String get trialEndsToday => 'Пробный период заканчивается сегодня';

  @override
  String get trialEndsTomorrow => 'Пробный период заканчивается завтра';

  @override
  String get trialUpgradeNow => 'Обновить сейчас';

  @override
  String get trialAlreadyUsed =>
      'Вы уже использовали бесплатный пробный период';

  @override
  String get subscriptionExpiredBanner => 'Срок вашей подписки истёк';

  @override
  String get subscriptionExpiredRenew => 'Продлить';

  @override
  String subscriptionEndsOn(String date) {
    return 'Заканчивается $date';
  }

  @override
  String get planMobileSubscription => 'Подписка Mobile';

  @override
  String get planProSubscription => 'Подписка Pro';

  @override
  String get discountFirstMonth => '−50% в первый месяц';

  @override
  String get accountBannedTitle => 'Аккаунт заблокирован';

  @override
  String get accountBannedBody =>
      'Ваш аккаунт TransKey был заблокирован. Если вы считаете это ошибкой, свяжитесь со службой поддержки.';

  @override
  String get accountBannedContact => 'Связаться с поддержкой';

  @override
  String get accountBannedLogout => 'Выйти';

  @override
  String get historyTitle => 'История';

  @override
  String get historySearchHint => 'Поиск по истории...';

  @override
  String get historyFilterAll => 'Все';

  @override
  String get historyFilterFavorites => '★ Избранное';

  @override
  String get historyFilterLocked => '🔒 Заблокированные';

  @override
  String get historyMenuClearAll => 'Очистить всё';

  @override
  String get historyMenuKeepFavorites => 'Оставить только избранное';

  @override
  String get historyClearDialogTitle => 'Очистить историю';

  @override
  String get historyClearDialogBody =>
      'Удалить всю историю? Заблокированные записи сохранятся.';

  @override
  String get historyKeepFavDialogBody =>
      'Удалить все записи, не отмеченные как избранные? Заблокированные записи сохранятся.';

  @override
  String get historyDetailSourceLabel => 'Источник';

  @override
  String get historyDetailTranslationLabel => 'Перевод';

  @override
  String get historyDetailRomanizationLabel => 'Латинизация';

  @override
  String get historyDetailFavoriteBadge => '★ Избранное';

  @override
  String get historyDetailLockedBadge => '🔒 Заблокировано';

  @override
  String get historyDetailCopyTranslation => 'Скопировать\nперевод';

  @override
  String get historyDetailCopySource => 'Скопировать\nисточник';

  @override
  String get historyDetailUnfavorite => 'Убрать из избранного';

  @override
  String get historyDetailFavoriteAction => 'В избранное';

  @override
  String get historyDetailUnlock => 'Разблокировать';

  @override
  String get historyDetailLockAction => 'Заблокировать';

  @override
  String get historyDetailTtsLabel => 'TTS';

  @override
  String glossaryTitle(int count, int max) {
    return 'Словарь ($count/$max)';
  }

  @override
  String get glossarySync => 'Синхронизировать';

  @override
  String get glossaryDeleteTitle => 'Удалить запись';

  @override
  String glossaryDeleteBody(String source) {
    return 'Удалить \"$source\"?';
  }

  @override
  String glossaryLimitReached(int max) {
    return 'Достигнут лимит словаря ($max)';
  }

  @override
  String get glossarySourceTargetRequired => 'Источник и перевод обязательны';

  @override
  String get glossarySyncFailed => 'Не удалось синхронизировать словарь';

  @override
  String get glossaryEditTitle => 'Изменить запись';

  @override
  String get glossaryAddTitle => 'Добавить запись';

  @override
  String get glossarySourceLabel => 'Источник';

  @override
  String get glossarySourceHint => 'Слово или фраза';

  @override
  String get glossaryTargetLabel => 'Перевод';

  @override
  String get glossaryTargetHint => 'Перевод';

  @override
  String get glossaryNamesLabel => 'Имена в словаре — нажмите для вставки';

  @override
  String get glossaryIsNameLabel => 'Это имя человека';

  @override
  String get glossaryIsNameHint =>
      'Помогает голосовому вводу распознать имя и указывает ИИ сохранить его точно.';

  @override
  String get upgradeScreenTitle => 'Обновить TransKey';

  @override
  String get upgradeChooseYourPlan => 'Выберите свой тариф';

  @override
  String get upgradeUnlockFullPower => 'Раскройте полную мощь TransKey';

  @override
  String get upgradeCurrentLabel => 'Текущий';

  @override
  String get upgradePopularBadge => 'Популярно';

  @override
  String get upgradeTryFreeDays => 'Попробуйте бесплатно 7 дней';

  @override
  String upgradeTrialActivated(String info) {
    return 'Пробный период активирован! $info';
  }

  @override
  String get upgradeTrialActivateFailed =>
      'Не удалось активировать пробный период';

  @override
  String get upgradeCheckoutFailed => 'Не удалось открыть оплату';

  @override
  String get upgradeMobileSubtitle => 'Все функции, только мобильно';

  @override
  String get upgradeProSubtitle => 'Все функции, все платформы';

  @override
  String get upgradeFreeFeat1 => 'Перевод';

  @override
  String get upgradeFreeFeat2 => '20 запросов/день';

  @override
  String get upgradeFreeFeat3 => '2000 символов/день';

  @override
  String get upgradeFreeFeat4 => 'Словарь';

  @override
  String get upgradeMobileFeat1 => 'Все функции';

  @override
  String get upgradeMobileFeat2 => 'iOS и Android';

  @override
  String get upgradeMobileFeat3 => 'Без ограничений';

  @override
  String get upgradeProFeat1 => 'Все функции';

  @override
  String get upgradeProFeat2 => 'Все платформы';

  @override
  String get upgradeProFeat3 => 'Десктоп + мобильный';

  @override
  String get upgradeFeatureColumn => 'Функция';

  @override
  String get upgradeMobilePrice => '📱 Mobile · \$3/mo';

  @override
  String get upgradeProPrice => '💻 Pro · \$6/mo';

  @override
  String get upgradeFooterHint =>
      '📱 Mobile: выгоднее, если вы пользуетесь только телефоном\n💻 Pro: работает и на телефоне, и на десктопе';

  @override
  String get comparisonReplyTranslate => 'Перевод ответа';

  @override
  String get comparisonMobileApps => '📱 iOS и Android';

  @override
  String get comparisonDesktop => '💻 Десктоп';

  @override
  String nudgeUnlock(String feature) {
    return 'Разблокировать $feature';
  }

  @override
  String get nudgeMobileCopy =>
      'Перейдите на Pro, чтобы пользоваться этой функцией\nна всех платформах.';

  @override
  String get nudgeChoosePlan => 'Выберите тариф, подходящий именно вам.';

  @override
  String get nudgeMaybeLater => 'Может, позже';

  @override
  String get nudgeMobileTitle => '📱 Mobile';

  @override
  String get nudgeProTitle => '💻 Pro';

  @override
  String get nudgeUpgradeToPro => 'Перейти на Pro';

  @override
  String get nudgeUpgradeToProSubtitle =>
      'Используйте на всех платформах — десктоп + мобильный';

  @override
  String get nudgePriceMobile => '\$3/month';

  @override
  String get nudgePriceProMonthly => '\$6/month';

  @override
  String get onboardWelcomeTitle => 'Добро пожаловать в TransKey';

  @override
  String get onboardWelcomeSubtitle =>
      'Переводите текст в реальном времени на\nболее чем 20 языков мгновенно.';

  @override
  String get onboardChooseTitle => 'Выберите ваш язык';

  @override
  String get onboardChooseSubtitle =>
      'Выберите предпочитаемый целевой язык.\nВы можете изменить его в любое время в настройках.';

  @override
  String get onboardStartedTitle => 'Начнём';

  @override
  String get onboardStartedSubtitle =>
      'Войдите или создайте бесплатный аккаунт,\nчтобы начать переводить прямо сейчас.';

  @override
  String get onboardGetStarted => 'Начать';

  @override
  String get setupTitle => 'Настройка клавиатуры';

  @override
  String get setupOpenSettings => 'Открыть настройки';

  @override
  String get setupOpenPermissions => 'Открыть разрешения';

  @override
  String get setupStep1TitleIOS => 'Добавьте клавиатуру TransKey';

  @override
  String get setupStep1TitleAndroid => 'Включите плавающую кнопку';

  @override
  String get setupStep1DescIOS =>
      'Перейдите в Настройки и добавьте TransKey как пользовательскую клавиатуру, чтобы переводить прямо во время набора.';

  @override
  String get setupStep1DescAndroid =>
      'Разрешите TransKey отображаться поверх других приложений, чтобы плавающая кнопка появлялась при необходимости.';

  @override
  String get setupStep2Title => 'Разрешите полный доступ';

  @override
  String get setupStep2DescIOS =>
      'Нажмите TransKey в списке клавиатур и включите «Разрешить полный доступ». Это необходимо для подключения к интернету для переводов.';

  @override
  String get setupStep2DescAndroid =>
      'Разрешение оверлея позволяет TransKey показывать плавающую кнопку поверх других приложений для быстрых переводов.';

  @override
  String get setupStep3Title => 'Всё готово!';

  @override
  String get setupStep3DescIOS =>
      'При наборе в любом приложении нажмите и удерживайте клавишу глобуса 🌐, чтобы переключиться на TransKey. Нажмите «Ответить», чтобы мгновенно перевести своё сообщение.';

  @override
  String get setupStep3DescAndroid =>
      'Выделите текст в любом приложении и поделитесь им с TransKey или используйте плавающую кнопку для быстрых переводов.';

  @override
  String get setupStep4Title => 'Переводите из любого приложения';

  @override
  String get setupStep4DescIOS =>
      'Выделите любой текст → нажмите «Поделиться» → выберите TransKey. Или скопируйте текст и откройте TransKey — он автоматически прочитает буфер обмена.';

  @override
  String get setupStep4DescAndroid =>
      'Выделите текст в любом приложении → нажмите «Поделиться» → выберите TransKey. Или используйте плавающую кнопку после копирования текста.';

  @override
  String get setupStep5Title => 'Умные функции';

  @override
  String get setupStep5Desc =>
      'Перевод, Ответ, Резюме, Объяснение и Улучшение — всё на основе ИИ. Функции Pro отмечены значком замка.';

  @override
  String get guideTitle => 'Как использовать';

  @override
  String get guideSubtitle => 'Все способы получения текста для каждой функции';

  @override
  String get guideIntroTitle =>
      'Для получения текста не требуются особые разрешения.';

  @override
  String get guideIntroBody =>
      'Каждая функция считывает текст только после того, как вы что-то намеренно сделали — скопировали текст, отсканировали экран, выбрали область, использовали системную кнопку «Поделиться» или нажали TransKey в меню выделения текста. Специальные возможности нужны только для того, чтобы результат «Ответ» сам вставлялся в окно чата, где вы печатаете.';

  @override
  String get guideFeatureTranslate => 'Перевод';

  @override
  String get guideFeatureTranslateSubtitle => 'Исходный язык → целевой язык';

  @override
  String get guideFeatureSummary => 'Резюме';

  @override
  String get guideFeatureSummarySubtitle =>
      'Сжать длинный контент до нескольких пунктов';

  @override
  String get guideFeatureRefine => 'Улучшение';

  @override
  String get guideFeatureRefineSubtitle =>
      'Улучшить грамматику / ясность вашего черновика';

  @override
  String get guideFeatureExplain => 'Объяснение';

  @override
  String get guideFeatureExplainSubtitle =>
      'Получить простое объяснение сложного текста';

  @override
  String get guideFeatureReply => 'Ответ';

  @override
  String get guideFeatureReplySubtitle =>
      'Создать предложение ответа на целевом языке';

  @override
  String get guideInputCopyTitle => 'Скопируйте текст, затем нажмите на кнопку';

  @override
  String get guideInputCopyDesc =>
      'Скопируйте любой текст в любом приложении, затем нажмите плавающую кнопку и выберите действие.';

  @override
  String get guideInputOcrTitle => 'Сканировать весь экран';

  @override
  String get guideInputOcrDesc =>
      'Нажмите кнопку → Сканировать экран. TransKey сделает один снимок экрана и прочитает с него текст.';

  @override
  String get guideInputRegionTitle => 'Сканировать часть экрана';

  @override
  String get guideInputRegionDesc =>
      'Нажмите кнопку → Сканировать область. Обведите рамкой только ту часть, которую нужно перевести.';

  @override
  String get guideInputShareTitle => 'Через кнопку «Поделиться»';

  @override
  String get guideInputShareDesc =>
      'Внутри любого приложения выделите текст → нажмите «Поделиться» → выберите TransKey.';

  @override
  String guideInputMenuTitle(String feature) {
    return 'Из меню выделения текста → TransKey: $feature';
  }

  @override
  String guideInputMenuDesc(String feature) {
    return 'Выделите текст в любом приложении — появится всплывающее меню с «Копировать»/«Поделиться». Нажмите ⋮ для дополнительных опций и выберите TransKey: $feature.';
  }

  @override
  String get guideReplyA11yTitle =>
      'Специальные возможности — по желанию, только для автовставки';

  @override
  String get guideReplyA11yBody =>
      'Если для TransKey включены Специальные возможности, ваш ответ вставляется прямо в окно чата, где вы печатаете. Без дополнительных действий.\n\nЕсли не хотите включать, ответ будет скопирован — просто удерживайте поле чата и нажмите «Вставить».';

  @override
  String get appPermissions => 'Разрешения приложения';

  @override
  String get permissionsAllSet => 'Всё настроено — нажмите для просмотра';

  @override
  String get permissionsNeedSetup =>
      'Нажмите, чтобы выдать необходимые разрешения';

  @override
  String get setupTransKey => 'Настройте TransKey';

  @override
  String get setupTransKeyBody =>
      'Выдайте разрешение на плавающую кнопку, чтобы начать. Специальные возможности по желанию и нужны только для вставки ответа одним касанием.';

  @override
  String get permFloatingBubble => 'Плавающая кнопка';

  @override
  String get permFloatingBubbleBody =>
      'Показывать TransKey поверх других приложений. Необходимо, чтобы кнопка появлялась.';

  @override
  String get permRestrictedSettings => 'Разрешить ограниченные настройки';

  @override
  String get permRestrictedSettingsBody =>
      'Android 13+ по умолчанию блокирует приложения, установленные не из магазина, в Специальных возможностях. Нажмите ⋮ в правом верхнем углу → «Разрешить ограниченные настройки».';

  @override
  String get permAccessibility => 'Специальные возможности (по желанию)';

  @override
  String get permAccessibilityBody =>
      'Позволяет TransKey вставлять подсказки ответа прямо в активное текстовое поле. Пропустите, если не против вставлять самостоятельно.';

  @override
  String get permEnabled => 'Включено';

  @override
  String get permEnable => 'Включить';

  @override
  String get permDone => 'Готово';

  @override
  String get permOpenAppDetails => 'Открыть сведения о приложении';

  @override
  String get permSkipHint =>
      'Специальные возможности необязательны. Без них подсказки ответа попадут в буфер обмена, и вам придётся вставлять их самостоятельно.';

  @override
  String get permSkipForNow => 'Пропустить пока';

  @override
  String get permFinishedCheck => 'Я закончил — проверить';

  @override
  String get voiceTooltip => 'Говорите, чтобы ввести';

  @override
  String get voiceListening => 'Слушаю…';

  @override
  String get voiceNeedsLang =>
      'Чтобы пользоваться голосом, задайте конкретный исходный язык';

  @override
  String get voicePermDenied => 'Доступ к микрофону запрещён';

  @override
  String get voiceUnsupported => 'Голосовой ввод недоступен на этом устройстве';

  @override
  String get voicePickSourceLang =>
      'Голосовому вводу нужен конкретный язык. Выберите исходный язык и снова нажмите микрофон.';

  @override
  String get paywallTitle => 'Достигнут дневной лимит';

  @override
  String get paywallBody =>
      'Вы исчерпали сегодняшнюю бесплатную квоту: 20 запросов / 2 000 символов. Посмотрите короткую рекламу, чтобы продолжить, или обновите тариф для безлимитного использования. Бесплатная квота обновляется в полночь.';

  @override
  String get paywallWatchAdCta => 'Посмотреть рекламу для продолжения';

  @override
  String get paywallWatchAdSub =>
      'Получайте дополнительные запросы и символы за каждую рекламу. Без ограничений на число реклам в день.';

  @override
  String get paywallUpgradeCta => 'Обновить — без лимитов, без рекламы';

  @override
  String get paywallUpgradeSub =>
      'От \$3/month. Отменить можно в любой момент.';

  @override
  String get paywallDismiss => 'Может, позже';

  @override
  String get paywallLoading => 'Загрузка…';

  @override
  String get paywallAdNotComplete =>
      'Реклама не была досмотрена — попробуйте снова, чтобы получить награду.';

  @override
  String get paywallCreditFailed =>
      'Не удалось начислить награду. Попробуйте снова через мгновение.';

  @override
  String get quotaWatchAd => '+ Посмотреть рекламу';

  @override
  String get quotaRewardGranted => 'Награда зачислена в сегодняшнюю квоту';

  @override
  String get historyEmpty => 'Истории переводов пока нет';

  @override
  String get glossaryEmpty => 'Словарь пуст';

  @override
  String get glossaryEmptyAddCta => 'Добавить запись';

  @override
  String get captureKeepaliveTitle => 'Окно быстрого повторного сканирования';

  @override
  String get captureKeepaliveHint =>
      'двойной тап по кнопке = повторное сканирование';

  @override
  String get captureKeepaliveExplain =>
      'После сканирования экрана сохраняйте разрешение на захват экрана активным, чтобы можно было дважды нажать кнопку (или снова выбрать «Сканировать экран») без системного запроса разрешения. Более длинное окно экономит нажатия, но индикатор трансляции остаётся видимым и слегка нагревает устройство.';

  @override
  String get captureKeepaliveOff => 'Выкл.';

  @override
  String get captureKeepaliveOffHint =>
      'Каждое сканирование снова запрашивает разрешение. Лучше для приватности / аккумулятора.';

  @override
  String get captureKeepaliveDefaultHint =>
      'Рекомендуется — баланс между скоростью повторного сканирования и аккумулятором.';

  @override
  String get captureKeepaliveShortHint =>
      'Меньше времени трансляции, но чаще запросы разрешения.';

  @override
  String get captureKeepaliveLongHint =>
      'Максимальная скорость повторного сканирования. Индикатор трансляции остаётся включён дольше.';

  @override
  String captureKeepaliveMinutes(int count) {
    return '$count мин';
  }
}
