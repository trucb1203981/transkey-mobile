// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get translate => '번역';

  @override
  String get summarize => '요약';

  @override
  String get explain => '설명';

  @override
  String get refine => '다듬기';

  @override
  String get reply => '답장';

  @override
  String get history => '기록';

  @override
  String get glossary => '용어집';

  @override
  String get settings => '설정';

  @override
  String get suggestions => '추천';

  @override
  String get copy => '복사';

  @override
  String get save => '저장';

  @override
  String get copied => '복사됨';

  @override
  String get delete => '삭제';

  @override
  String get cancel => '취소';

  @override
  String get ok => '확인';

  @override
  String get confirm => '확인';

  @override
  String get clear => '지우기';

  @override
  String get dismiss => '닫기';

  @override
  String get required => '필수';

  @override
  String get addAction => '추가';

  @override
  String get saveAction => '저장';

  @override
  String get next => '다음';

  @override
  String get skip => '건너뛰기';

  @override
  String get done => '완료';

  @override
  String get hintEnterText => '번역할 텍스트 입력...';

  @override
  String detectedLang(String lang) {
    return '감지: $lang';
  }

  @override
  String get autoDetect => '자동 감지';

  @override
  String get sourceLang => '원문';

  @override
  String get targetLang => '번역';

  @override
  String get swapLanguages => '언어 바꾸기';

  @override
  String get settingsTitle => '설정';

  @override
  String get sectionLanguage => '언어';

  @override
  String get sectionTranslation => '번역';

  @override
  String get sectionAdvanced => '고급';

  @override
  String get sectionOther => '기타';

  @override
  String get sectionSpeech => '음성 읽기';

  @override
  String get targetLanguage => '번역 언어';

  @override
  String get sourceLanguage => '원문 언어';

  @override
  String get appLanguage => '앱 언어';

  @override
  String get saveHistory => '기록 저장';

  @override
  String get romanization => '로마자 표기';

  @override
  String get replySuggestions => '답장 추천';

  @override
  String get toneOverride => '번역 어조';

  @override
  String get replyToneOverride => '답장 어조';

  @override
  String get replyLanguage => '답장 언어';

  @override
  String get replyLanguageFromConversation => '대화에 맞춤';

  @override
  String get autoCloseResult => '결과 자동 닫기';

  @override
  String get autoCloseSeconds => '자동 닫기(초)';

  @override
  String get autoCloseUnit => '초';

  @override
  String get autoCloseDisabled => '끔';

  @override
  String get toneAuto => '자동';

  @override
  String get toneBusiness => '비즈니스';

  @override
  String get toneCasual => '캐주얼';

  @override
  String get toneFormal => '격식';

  @override
  String get tonePolite => '공손';

  @override
  String get toneTechnical => '기술';

  @override
  String get toneNeutral => '중립';

  @override
  String get toneReplySameAsTranslate => '번역과 동일';

  @override
  String get popupTo => '번역 →';

  @override
  String get tabTranslate => '번역';

  @override
  String get tabReply => '답장';

  @override
  String get tabSummarize => '요약';

  @override
  String get tabExplain => '설명';

  @override
  String get tabRefine => '다듬기';

  @override
  String get keyboardSetup => '키보드 설정';

  @override
  String get bubbleSetup => '버블 설정';

  @override
  String get floatingBubble => '플로팅 버블';

  @override
  String get bubbleActive => '활성화됨';

  @override
  String get bubbleInactive => '비활성화됨';

  @override
  String get sendFeedback => '피드백 보내기';

  @override
  String get termsOfService => '이용 약관';

  @override
  String get privacyPolicy => '개인정보 처리방침';

  @override
  String get version => '버전';

  @override
  String get upgrade => '업그레이드';

  @override
  String get upgradeToPro => 'Pro로 업그레이드';

  @override
  String get logOut => '로그아웃';

  @override
  String get changePassword => '비밀번호 변경';

  @override
  String get manageDevices => '기기 관리';

  @override
  String get manageSubscription => '구독 관리';

  @override
  String get currentPassword => '현재 비밀번호';

  @override
  String get newPassword => '새 비밀번호';

  @override
  String get confirmPassword => '새 비밀번호 확인';

  @override
  String get passwordTooShort => '비밀번호는 8자 이상이어야 합니다';

  @override
  String get passwordMismatch => '비밀번호가 일치하지 않습니다';

  @override
  String get changePasswordSuccess => '비밀번호가 변경되었습니다';

  @override
  String get changePasswordFailed => '비밀번호 변경 실패';

  @override
  String get devicesTitle => '등록된 기기';

  @override
  String get devicesEmpty => '등록된 기기가 없습니다.';

  @override
  String get devicesProLimit => 'Pro 플랜은 최대 2대까지 사용할 수 있습니다.';

  @override
  String get deviceCurrentThis => '현재 기기';

  @override
  String deviceLastUsed(String date) {
    return '마지막 사용: $date';
  }

  @override
  String get removeDevice => '삭제';

  @override
  String get removeDeviceConfirm => '이 기기를 삭제할까요? 다시 로그인해야 합니다.';

  @override
  String get removeDeviceFailed => '기기를 삭제할 수 없습니다';

  @override
  String get subscriptionTitle => '구독';

  @override
  String get subscriptionStatus => '상태';

  @override
  String get subscriptionRenewsAt => '갱신일';

  @override
  String get subscriptionEndsAt => '종료일';

  @override
  String get subscriptionTrialEndsAt => '체험판 종료';

  @override
  String get subscriptionInactive => '활성 구독이 없습니다';

  @override
  String get subscriptionAdminGranted =>
      '회원님의 요금제는 셀프 결제가 아닌 지원팀에 의해 활성화되었습니다. 변경하거나 취소하려면 문의해주세요.';

  @override
  String get subscriptionCancel => '구독 취소';

  @override
  String get subscriptionCancelConfirm =>
      'Pro 구독을 취소할까요? 현재 기간 종료까지는 Pro를 계속 사용할 수 있습니다.';

  @override
  String get subscriptionCancelled => '갱신일에 구독이 종료됩니다.';

  @override
  String get subscriptionCancelFailed => '구독을 취소할 수 없습니다';

  @override
  String get voicePickerTitle => '음성';

  @override
  String get voiceDefault => '기본';

  @override
  String get speedPickerTitle => '읽기 속도';

  @override
  String get speedNormal => '보통';

  @override
  String get accessibilityPasteBack => '다른 앱에 답장 붙여넣기';

  @override
  String get accessibilityPasteBackDesc =>
      '접근성 설정에서 TransKey를 활성화하면 \"붙여넣기\"가 포커스된 입력란에 답장을 직접 입력합니다.';

  @override
  String get accessibilityEnabled => '활성화됨';

  @override
  String get accessibilityDisabled => '비활성화됨 — 탭하여 설정 열기';

  @override
  String get feedbackTitle => '피드백 보내기';

  @override
  String get feedbackHint => '의견을 알려주세요...';

  @override
  String get feedbackSend => '보내기';

  @override
  String get feedbackThanks => '피드백 감사합니다!';

  @override
  String get feedbackFailed => '피드백 전송 실패';

  @override
  String get selectLanguage => '언어 선택';

  @override
  String get searchLanguages => '언어 검색...';

  @override
  String get recent => '최근';

  @override
  String get allLanguages => '모든 언어';

  @override
  String get login => '로그인';

  @override
  String get signUp => '가입';

  @override
  String get logIn => '로그인';

  @override
  String get createAccount => '계정 만들기';

  @override
  String get continueWithGoogle => 'Google로 계속하기';

  @override
  String get orDivider => '또는';

  @override
  String get emailHint => '이메일';

  @override
  String get passwordHint => '비밀번호';

  @override
  String get nameHint => '이름';

  @override
  String get nameRequired => '이름을 입력하세요';

  @override
  String get emailRequired => '이메일을 입력하세요';

  @override
  String get emailInvalid => '유효한 이메일을 입력하세요';

  @override
  String get passwordRequired => '비밀번호를 입력하세요';

  @override
  String get passwordMinSix => '6자 이상';

  @override
  String get proDeviceLimitError => 'Pro 계정이 최대 기기 수에 도달했습니다';

  @override
  String get deviceLimitError => '이 기기에 너무 많은 계정이 있습니다';

  @override
  String googleSignInFailed(String error) {
    return 'Google 로그인 실패: $error';
  }

  @override
  String get googleNotConfigured => 'Google 로그인이 설정되지 않음 (serverClientId 누락)';

  @override
  String get googleSignInNoIdToken =>
      'Google이 idToken을 반환하지 않음 — serverClientId 확인';

  @override
  String get proRequired => 'Pro 플랜이 필요합니다';

  @override
  String get noTextToTranslate => '먼저 텍스트를 입력하세요';

  @override
  String get errorGeneric => '오류가 발생했습니다';

  @override
  String get planFree => '무료';

  @override
  String get planPro => 'Pro';

  @override
  String get planMobile => 'Mobile';

  @override
  String get planTrial => '체험판';

  @override
  String usageRequests(int used, int limit) {
    return '$used/$limit 요청';
  }

  @override
  String usageCharacters(int used, int limit) {
    return '$used/$limit 자';
  }

  @override
  String trialEndsInDays(int days) {
    return '체험판 $days일 남음';
  }

  @override
  String get trialEndsToday => '체험판 오늘 종료';

  @override
  String get trialEndsTomorrow => '체험판 내일 종료';

  @override
  String get trialUpgradeNow => '지금 업그레이드';

  @override
  String get trialAlreadyUsed => '이미 무료 체험판을 사용했습니다';

  @override
  String get subscriptionExpiredBanner => '구독이 만료되었습니다';

  @override
  String get subscriptionExpiredRenew => '갱신';

  @override
  String subscriptionEndsOn(String date) {
    return '$date에 종료';
  }

  @override
  String get planMobileSubscription => 'Mobile 구독';

  @override
  String get planProSubscription => 'Pro 구독';

  @override
  String get discountFirstMonth => '첫 달 −50%';

  @override
  String get accountBannedTitle => '계정 정지됨';

  @override
  String get accountBannedBody => 'TransKey 계정이 정지되었습니다. 오류라고 생각되면 지원팀에 문의하세요.';

  @override
  String get accountBannedContact => '지원 문의';

  @override
  String get accountBannedLogout => '로그아웃';

  @override
  String get historyTitle => '기록';

  @override
  String get historySearchHint => '기록 검색...';

  @override
  String get historyFilterAll => '전체';

  @override
  String get historyFilterFavorites => '★ 즐겨찾기';

  @override
  String get historyFilterLocked => '🔒 잠김';

  @override
  String get historyMenuClearAll => '모두 삭제';

  @override
  String get historyMenuKeepFavorites => '즐겨찾기만 유지';

  @override
  String get historyClearDialogTitle => '기록 지우기';

  @override
  String get historyClearDialogBody => '모든 기록을 삭제할까요? 잠긴 항목은 유지됩니다.';

  @override
  String get historyKeepFavDialogBody => '즐겨찾기가 아닌 항목을 모두 삭제할까요? 잠긴 항목은 유지됩니다.';

  @override
  String get historyDetailSourceLabel => '원문';

  @override
  String get historyDetailTranslationLabel => '번역';

  @override
  String get historyDetailRomanizationLabel => '로마자 표기';

  @override
  String get historyDetailFavoriteBadge => '★ 즐겨찾기';

  @override
  String get historyDetailLockedBadge => '🔒 잠김';

  @override
  String get historyDetailCopyTranslation => '번역\n복사';

  @override
  String get historyDetailCopySource => '원문\n복사';

  @override
  String get historyDetailUnfavorite => '해제';

  @override
  String get historyDetailFavoriteAction => '즐겨찾기';

  @override
  String get historyDetailUnlock => '잠금 해제';

  @override
  String get historyDetailLockAction => '잠금';

  @override
  String get historyDetailTtsLabel => '음성';

  @override
  String glossaryTitle(int count, int max) {
    return '용어집 ($count/$max)';
  }

  @override
  String get glossarySync => '동기화';

  @override
  String get glossaryDeleteTitle => '항목 삭제';

  @override
  String glossaryDeleteBody(String source) {
    return '\"$source\"을(를) 삭제할까요?';
  }

  @override
  String glossaryLimitReached(int max) {
    return '용어집 한도 도달 ($max)';
  }

  @override
  String get glossarySourceTargetRequired => '원문과 번역을 모두 입력하세요';

  @override
  String get glossarySyncFailed => '용어집 동기화 실패';

  @override
  String get glossaryEditTitle => '항목 편집';

  @override
  String get glossaryAddTitle => '항목 추가';

  @override
  String get glossarySourceLabel => '원문';

  @override
  String get glossarySourceHint => '단어 또는 구문';

  @override
  String get glossaryTargetLabel => '번역';

  @override
  String get glossaryTargetHint => '번역어';

  @override
  String get upgradeScreenTitle => 'TransKey 업그레이드';

  @override
  String get upgradeChooseYourPlan => '플랜 선택';

  @override
  String get upgradeUnlockFullPower => 'TransKey의 모든 기능을 해제하세요';

  @override
  String get upgradeCurrentLabel => '현재';

  @override
  String get upgradePopularBadge => '인기';

  @override
  String get upgradeTryFreeDays => '7일 무료 체험';

  @override
  String upgradeTrialActivated(String info) {
    return '체험판 시작! $info';
  }

  @override
  String get upgradeTrialActivateFailed => '체험판 시작 실패';

  @override
  String get upgradeCheckoutFailed => '결제 페이지를 열 수 없습니다';

  @override
  String get upgradeMobileSubtitle => '모든 기능, 모바일 전용';

  @override
  String get upgradeProSubtitle => '모든 기능, 모든 플랫폼';

  @override
  String get upgradeFreeFeat1 => '번역';

  @override
  String get upgradeFreeFeat2 => '20회/일';

  @override
  String get upgradeFreeFeat3 => '2000자/일';

  @override
  String get upgradeFreeFeat4 => '용어집';

  @override
  String get upgradeMobileFeat1 => '모든 기능';

  @override
  String get upgradeMobileFeat2 => 'iOS & Android';

  @override
  String get upgradeMobileFeat3 => '무제한';

  @override
  String get upgradeProFeat1 => '모든 기능';

  @override
  String get upgradeProFeat2 => '모든 플랫폼';

  @override
  String get upgradeProFeat3 => 'Desktop + Mobile';

  @override
  String get upgradeFeatureColumn => '기능';

  @override
  String get upgradeMobilePrice => '📱 Mobile · \$3/월';

  @override
  String get upgradeProPrice => '💻 Pro · \$6/월';

  @override
  String get upgradeFooterHint =>
      '📱 Mobile: 휴대폰만 사용한다면 최고의 가성비\n💻 Pro: 휴대폰과 데스크톱 모두 사용 가능';

  @override
  String get comparisonReplyTranslate => '답장 번역';

  @override
  String get comparisonMobileApps => '📱 iOS & Android';

  @override
  String get comparisonDesktop => '💻 Desktop';

  @override
  String nudgeUnlock(String feature) {
    return '$feature 잠금 해제';
  }

  @override
  String get nudgeMobileCopy => 'Pro로 업그레이드하면 모든 플랫폼에서\n이 기능을 사용할 수 있습니다.';

  @override
  String get nudgeChoosePlan => '필요에 맞는 플랜을 선택하세요.';

  @override
  String get nudgeMaybeLater => '나중에';

  @override
  String get nudgeMobileTitle => '📱 Mobile';

  @override
  String get nudgeProTitle => '💻 Pro';

  @override
  String get nudgeUpgradeToPro => 'Pro로 업그레이드';

  @override
  String get nudgeUpgradeToProSubtitle => '모든 플랫폼에서 사용 — 데스크톱 + 모바일';

  @override
  String get nudgePriceMobile => '\$3/월';

  @override
  String get nudgePriceProMonthly => '\$6/월';

  @override
  String get onboardWelcomeTitle => 'TransKey에 오신 것을 환영합니다';

  @override
  String get onboardWelcomeSubtitle => '20개 이상의 언어를\n실시간으로 번역하세요.';

  @override
  String get onboardChooseTitle => '언어 선택';

  @override
  String get onboardChooseSubtitle => '원하는 번역 언어를 선택하세요.\n설정에서 언제든 변경 가능합니다.';

  @override
  String get onboardStartedTitle => '시작하기';

  @override
  String get onboardStartedSubtitle => '로그인하거나 무료 계정을 만들어\n지금 바로 번역을 시작하세요.';

  @override
  String get onboardGetStarted => '시작하기';

  @override
  String get setupTitle => '키보드 설정';

  @override
  String get setupOpenSettings => '설정 열기';

  @override
  String get setupOpenPermissions => '권한 열기';

  @override
  String get setupStep1TitleIOS => 'TransKey 키보드 추가';

  @override
  String get setupStep1TitleAndroid => '플로팅 버블 활성화';

  @override
  String get setupStep1DescIOS =>
      '설정으로 가서 TransKey를 사용자 정의 키보드로 추가하면 입력하면서 바로 번역할 수 있습니다.';

  @override
  String get setupStep1DescAndroid =>
      '다른 앱 위에 TransKey를 표시하도록 허용하면 필요할 때 플로팅 버블이 나타납니다.';

  @override
  String get setupStep2Title => '전체 액세스 허용';

  @override
  String get setupStep2DescIOS =>
      '키보드 목록에서 TransKey를 탭하고 \"전체 액세스 허용\"을 활성화하세요. 번역을 위해 인터넷 연결이 필요합니다.';

  @override
  String get setupStep2DescAndroid =>
      '오버레이 권한을 통해 TransKey가 다른 앱 위에 플로팅 버블을 표시하여 빠른 번역을 제공합니다.';

  @override
  String get setupStep3Title => '준비 완료!';

  @override
  String get setupStep3DescIOS =>
      '어떤 앱에서든 입력 시 지구본 키🌐를 길게 눌러 TransKey로 전환. \"답장\"을 탭하여 즉시 번역하세요.';

  @override
  String get setupStep3DescAndroid =>
      '어떤 앱에서든 텍스트를 선택하여 TransKey에 공유하거나 플로팅 버블로 빠르게 번역하세요.';

  @override
  String get setupStep4Title => '어떤 앱에서든 번역';

  @override
  String get setupStep4DescIOS =>
      '텍스트 선택 → \"공유\" 탭 → TransKey 선택. 또는 텍스트를 복사하고 TransKey를 여세요 — 클립보드를 자동으로 읽습니다.';

  @override
  String get setupStep4DescAndroid =>
      '어떤 앱에서든 텍스트 선택 → \"공유\" 탭 → TransKey 선택. 또는 텍스트 복사 후 플로팅 버블 사용.';

  @override
  String get setupStep5Title => 'AI 기능';

  @override
  String get setupStep5Desc =>
      '번역, 답장, 요약, 설명, 다듬기 — 모두 AI 기반. Pro 기능은 자물쇠 아이콘으로 표시됩니다.';

  @override
  String get guideTitle => '사용법';

  @override
  String get guideSubtitle => '각 기능에서 텍스트를 가져오는 모든 방법';

  @override
  String get guideIntroTitle => '텍스트 캡처에 특별한 권한은 필요하지 않습니다.';

  @override
  String get guideIntroBody =>
      '모든 기능은 사용자가 의도적으로 동작했을 때만 텍스트를 읽습니다 — 복사, 화면 스캔, 영역 선택, 시스템 공유 사용, 또는 텍스트 선택 메뉴에서 TransKey 탭. 접근성은 Reply 결과를 입력 중인 채팅창에 바로 붙여넣기 위해서만 사용됩니다.';

  @override
  String get guideFeatureTranslate => '번역';

  @override
  String get guideFeatureTranslateSubtitle => '원본 언어 → 대상 언어';

  @override
  String get guideFeatureSummary => '요약';

  @override
  String get guideFeatureSummarySubtitle => '긴 내용을 몇 가지 핵심으로 요약';

  @override
  String get guideFeatureRefine => '다듬기';

  @override
  String get guideFeatureRefineSubtitle => '초안의 문법과 명료성을 향상';

  @override
  String get guideFeatureExplain => '설명';

  @override
  String get guideFeatureExplainSubtitle => '어려운 문장을 쉬운 말로 설명';

  @override
  String get guideFeatureReply => '답장';

  @override
  String get guideFeatureReplySubtitle => '대상 언어로 답장 제안 생성';

  @override
  String get guideInputCopyTitle => '텍스트 복사 후 버블 탭';

  @override
  String get guideInputCopyDesc => '어떤 앱에서든 텍스트를 복사한 후 플로팅 버블을 탭하여 동작을 선택하세요.';

  @override
  String get guideInputOcrTitle => '화면 전체 스캔';

  @override
  String get guideInputOcrDesc =>
      '버블 → 화면 스캔. TransKey가 스크린샷 한 장을 찍어 그 위의 글자를 읽습니다.';

  @override
  String get guideInputRegionTitle => '화면 일부만 스캔';

  @override
  String get guideInputRegionDesc => '버블 → 영역 스캔. 번역할 부분만 박스로 드래그하세요.';

  @override
  String get guideInputShareTitle => '공유 버튼에서';

  @override
  String get guideInputShareDesc => '어떤 앱에서든: 텍스트 선택 → 공유 탭 → TransKey 선택.';

  @override
  String guideInputMenuTitle(String feature) {
    return '텍스트 선택 메뉴에서 → TransKey: $feature';
  }

  @override
  String guideInputMenuDesc(String feature) {
    return '앱에서 텍스트를 선택하면 복사/공유 팝업이 나타납니다. ⋮ 탭으로 더 보기 → TransKey: $feature 선택.';
  }

  @override
  String get guideReplyA11yTitle => '접근성 — 선택, 자동 붙여넣기 전용';

  @override
  String get guideReplyA11yBody =>
      'TransKey 접근성을 켜두면, 답장이 입력 중인 채팅창에 바로 붙여집니다. 추가 동작 불필요.\n\n켜고 싶지 않으면 답장이 자동 복사됩니다 — 채팅창을 길게 눌러 붙여넣기 탭.';

  @override
  String get appPermissions => '앱 권한';

  @override
  String get permissionsAllSet => '모두 설정 완료 — 탭하여 확인';

  @override
  String get permissionsNeedSetup => '필요한 권한을 부여하려면 탭';

  @override
  String get setupTransKey => 'TransKey 설정';

  @override
  String get setupTransKeyBody =>
      '플로팅 버블 권한만 부여하면 시작할 수 있습니다. 접근성은 선택사항이며 원탭 Reply 붙여넣기에만 필요합니다.';

  @override
  String get permFloatingBubble => '플로팅 버블';

  @override
  String get permFloatingBubbleBody => '다른 앱 위에 TransKey 표시. 버블이 나타나는 데 필수.';

  @override
  String get permRestrictedSettings => '제한된 설정 허용';

  @override
  String get permRestrictedSettingsBody =>
      'Android 13+는 사이드로드 앱의 접근성을 기본 차단합니다. 우상단 ⋮ → \"제한된 설정 허용\".';

  @override
  String get permAccessibility => '접근성 (선택)';

  @override
  String get permAccessibilityBody =>
      'Reply 제안을 포커스된 텍스트 필드에 직접 붙여넣습니다. 수동 붙여넣기가 괜찮으면 건너뛰세요.';

  @override
  String get permEnabled => '활성화됨';

  @override
  String get permEnable => '활성화';

  @override
  String get permDone => '완료';

  @override
  String get permOpenAppDetails => '앱 정보 열기';

  @override
  String get permSkipHint =>
      '접근성은 선택사항입니다. 없으면 Reply 결과가 클립보드로 가고 직접 붙여넣어야 합니다.';

  @override
  String get permSkipForNow => '지금은 건너뛰기';

  @override
  String get permFinishedCheck => '완료 — 확인';

  @override
  String get voiceTooltip => '음성 입력';

  @override
  String get voiceListening => '듣는 중…';

  @override
  String get voicePermDenied => '마이크 권한이 거부되었습니다';

  @override
  String get voiceUnsupported => '이 기기에서는 음성 입력을 사용할 수 없습니다';

  @override
  String get voicePickSourceLang => '먼저 원본 언어를 선택하세요 — 음성 입력은 자동 감지할 수 없습니다';

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
