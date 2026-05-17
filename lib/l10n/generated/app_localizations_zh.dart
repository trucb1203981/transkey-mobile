// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get translate => '翻译';

  @override
  String get summarize => '总结';

  @override
  String get explain => '解释';

  @override
  String get refine => '润色';

  @override
  String get reply => '回复';

  @override
  String get history => '历史';

  @override
  String get glossary => '术语库';

  @override
  String get settings => '设置';

  @override
  String get suggestions => '建议';

  @override
  String get copy => '复制';

  @override
  String get save => '保存';

  @override
  String get copied => '已复制';

  @override
  String get delete => '删除';

  @override
  String get cancel => '取消';

  @override
  String get ok => '确定';

  @override
  String get confirm => '确认';

  @override
  String get clear => '清空';

  @override
  String get dismiss => '关闭';

  @override
  String get required => '必填';

  @override
  String get addAction => '添加';

  @override
  String get saveAction => '保存';

  @override
  String get next => '下一步';

  @override
  String get skip => '跳过';

  @override
  String get done => '完成';

  @override
  String get hintEnterText => '输入要翻译的文本...';

  @override
  String detectedLang(String lang) {
    return '检测到:$lang';
  }

  @override
  String get autoDetect => '自动检测';

  @override
  String get sourceLang => '原文';

  @override
  String get targetLang => '目标';

  @override
  String get swapLanguages => '互换语言';

  @override
  String get settingsTitle => '设置';

  @override
  String get sectionLanguage => '语言';

  @override
  String get sectionTranslation => '翻译';

  @override
  String get sectionAdvanced => '高级';

  @override
  String get sectionOther => '其他';

  @override
  String get sectionSpeech => '朗读';

  @override
  String get targetLanguage => '目标语言';

  @override
  String get sourceLanguage => '源语言';

  @override
  String get appLanguage => '应用语言';

  @override
  String get saveHistory => '保存历史';

  @override
  String get romanization => '罗马音';

  @override
  String get replySuggestions => '回复建议';

  @override
  String get toneOverride => '翻译语气';

  @override
  String get replyToneOverride => '回复语气';

  @override
  String get replyLanguage => '回复语言';

  @override
  String get replyLanguageFromConversation => '跟随对话';

  @override
  String get autoCloseResult => '自动关闭结果';

  @override
  String get autoCloseSeconds => '自动关闭(秒)';

  @override
  String get autoCloseUnit => '秒';

  @override
  String get autoCloseDisabled => '关闭';

  @override
  String get toneAuto => '自动';

  @override
  String get toneBusiness => '商务';

  @override
  String get toneCasual => '随意';

  @override
  String get toneFormal => '正式';

  @override
  String get tonePolite => '礼貌';

  @override
  String get toneTechnical => '技术';

  @override
  String get toneNeutral => '中立';

  @override
  String get toneReplySameAsTranslate => '与翻译相同';

  @override
  String get popupTo => '至:';

  @override
  String get tabTranslate => '翻译';

  @override
  String get tabReply => '回复';

  @override
  String get tabSummarize => '总结';

  @override
  String get tabExplain => '解释';

  @override
  String get tabRefine => '润色';

  @override
  String get keyboardSetup => '键盘设置';

  @override
  String get bubbleSetup => '气泡设置';

  @override
  String get floatingBubble => '悬浮气泡';

  @override
  String get bubbleActive => '已启用';

  @override
  String get bubbleInactive => '未启用';

  @override
  String get sendFeedback => '发送反馈';

  @override
  String get termsOfService => '服务条款';

  @override
  String get privacyPolicy => '隐私政策';

  @override
  String get version => '版本';

  @override
  String get upgrade => '升级';

  @override
  String get upgradeToPro => '升级到 Pro';

  @override
  String get logOut => '退出登录';

  @override
  String get changePassword => '修改密码';

  @override
  String get manageDevices => '管理设备';

  @override
  String get manageSubscription => '管理订阅';

  @override
  String get currentPassword => '当前密码';

  @override
  String get newPassword => '新密码';

  @override
  String get confirmPassword => '确认新密码';

  @override
  String get passwordTooShort => '密码至少需 8 个字符';

  @override
  String get passwordMismatch => '密码不匹配';

  @override
  String get changePasswordSuccess => '密码已更新';

  @override
  String get changePasswordFailed => '密码更新失败';

  @override
  String get devicesTitle => '已注册设备';

  @override
  String get devicesEmpty => '尚未注册任何设备。';

  @override
  String get devicesProLimit => 'Pro 套餐最多允许 2 台设备。';

  @override
  String get deviceCurrentThis => '当前设备';

  @override
  String deviceLastUsed(String date) {
    return '上次使用:$date';
  }

  @override
  String get removeDevice => '移除';

  @override
  String get removeDeviceConfirm => '移除此设备?需要重新登录。';

  @override
  String get removeDeviceFailed => '无法移除设备';

  @override
  String get subscriptionTitle => '订阅';

  @override
  String get subscriptionStatus => '状态';

  @override
  String get subscriptionRenewsAt => '续订日';

  @override
  String get subscriptionEndsAt => '结束日';

  @override
  String get subscriptionTrialEndsAt => '试用结束';

  @override
  String get subscriptionInactive => '无有效订阅';

  @override
  String get subscriptionAdminGranted => '您的套餐由支持团队激活，并非通过自助结算。如需更改或取消，请联系我们。';

  @override
  String get subscriptionCancel => '取消订阅';

  @override
  String get subscriptionCancelConfirm => '取消 Pro 订阅?当前周期结束前仍可使用 Pro。';

  @override
  String get subscriptionCancelled => '订阅将在续订日结束。';

  @override
  String get subscriptionCancelFailed => '无法取消订阅';

  @override
  String get voicePickerTitle => '语音';

  @override
  String get voiceDefault => '默认';

  @override
  String get speedPickerTitle => '朗读速度';

  @override
  String get speedNormal => '标准';

  @override
  String get accessibilityPasteBack => '粘贴回复到其他应用';

  @override
  String get accessibilityPasteBackDesc =>
      '在无障碍设置中启用 TransKey,即可让\"粘贴\"将回复直接写入聚焦中的输入框。';

  @override
  String get accessibilityEnabled => '已启用';

  @override
  String get accessibilityDisabled => '未启用 — 点击打开设置';

  @override
  String get feedbackTitle => '发送反馈';

  @override
  String get feedbackHint => '告诉我们您的想法...';

  @override
  String get feedbackSend => '发送';

  @override
  String get feedbackThanks => '感谢您的反馈!';

  @override
  String get feedbackFailed => '发送反馈失败';

  @override
  String get selectLanguage => '选择语言';

  @override
  String get searchLanguages => '搜索语言...';

  @override
  String get recent => '最近';

  @override
  String get allLanguages => '所有语言';

  @override
  String get login => '登录';

  @override
  String get signUp => '注册';

  @override
  String get logIn => '登录';

  @override
  String get createAccount => '创建账户';

  @override
  String get continueWithGoogle => '使用 Google 继续';

  @override
  String get orDivider => '或';

  @override
  String get emailHint => '邮箱';

  @override
  String get passwordHint => '密码';

  @override
  String get nameHint => '姓名';

  @override
  String get nameRequired => '请输入姓名';

  @override
  String get emailRequired => '请输入邮箱';

  @override
  String get emailInvalid => '请输入有效邮箱';

  @override
  String get passwordRequired => '请输入密码';

  @override
  String get passwordMinSix => '至少 6 个字符';

  @override
  String get proDeviceLimitError => 'Pro 账户已达最大设备数';

  @override
  String get deviceLimitError => '此设备上账户过多';

  @override
  String googleSignInFailed(String error) {
    return 'Google 登录失败:$error';
  }

  @override
  String get googleNotConfigured => 'Google 登录未配置(缺少 serverClientId)';

  @override
  String get googleSignInNoIdToken => 'Google 未返回 idToken — 请检查 serverClientId';

  @override
  String get proRequired => '需要 Pro 套餐';

  @override
  String get noTextToTranslate => '请先输入文本';

  @override
  String get errorGeneric => '发生错误';

  @override
  String get planFree => '免费';

  @override
  String get planPro => 'Pro';

  @override
  String get planMobile => 'Mobile';

  @override
  String get planTrial => '试用';

  @override
  String usageRequests(int used, int limit) {
    return '$used/$limit 次请求';
  }

  @override
  String usageCharacters(int used, int limit) {
    return '$used/$limit 字符';
  }

  @override
  String trialEndsInDays(int days) {
    return '试用还剩 $days 天';
  }

  @override
  String get trialEndsToday => '试用今天结束';

  @override
  String get trialEndsTomorrow => '试用明天结束';

  @override
  String get trialUpgradeNow => '立即升级';

  @override
  String get trialAlreadyUsed => '您已使用过免费试用';

  @override
  String get subscriptionExpiredBanner => '订阅已过期';

  @override
  String get subscriptionExpiredRenew => '续订';

  @override
  String subscriptionEndsOn(String date) {
    return '$date 结束';
  }

  @override
  String get planMobileSubscription => 'Mobile 订阅';

  @override
  String get planProSubscription => 'Pro 订阅';

  @override
  String get discountFirstMonth => '首月 −50%';

  @override
  String get accountBannedTitle => '账户已暂停';

  @override
  String get accountBannedBody => '您的 TransKey 账户已被暂停。如认为是错误,请联系支持。';

  @override
  String get accountBannedContact => '联系支持';

  @override
  String get accountBannedLogout => '退出登录';

  @override
  String get historyTitle => '历史';

  @override
  String get historySearchHint => '搜索历史...';

  @override
  String get historyFilterAll => '全部';

  @override
  String get historyFilterFavorites => '★ 收藏';

  @override
  String get historyFilterLocked => '🔒 锁定';

  @override
  String get historyMenuClearAll => '全部清除';

  @override
  String get historyMenuKeepFavorites => '仅保留收藏';

  @override
  String get historyClearDialogTitle => '清除历史';

  @override
  String get historyClearDialogBody => '删除全部历史?锁定的条目将保留。';

  @override
  String get historyKeepFavDialogBody => '删除所有非收藏条目?锁定的条目将保留。';

  @override
  String get historyDetailSourceLabel => '原文';

  @override
  String get historyDetailTranslationLabel => '翻译';

  @override
  String get historyDetailRomanizationLabel => '罗马音';

  @override
  String get historyDetailFavoriteBadge => '★ 收藏';

  @override
  String get historyDetailLockedBadge => '🔒 锁定';

  @override
  String get historyDetailCopyTranslation => '复制\n翻译';

  @override
  String get historyDetailCopySource => '复制\n原文';

  @override
  String get historyDetailUnfavorite => '取消收藏';

  @override
  String get historyDetailFavoriteAction => '收藏';

  @override
  String get historyDetailUnlock => '解锁';

  @override
  String get historyDetailLockAction => '锁定';

  @override
  String get historyDetailTtsLabel => '朗读';

  @override
  String glossaryTitle(int count, int max) {
    return '术语库 ($count/$max)';
  }

  @override
  String get glossarySync => '同步';

  @override
  String get glossaryDeleteTitle => '删除条目';

  @override
  String glossaryDeleteBody(String source) {
    return '删除 \"$source\"?';
  }

  @override
  String glossaryLimitReached(int max) {
    return '已达术语库上限 ($max)';
  }

  @override
  String get glossarySourceTargetRequired => '请同时填写原文和翻译';

  @override
  String get glossarySyncFailed => '术语库同步失败';

  @override
  String get glossaryEditTitle => '编辑条目';

  @override
  String get glossaryAddTitle => '添加条目';

  @override
  String get glossarySourceLabel => '原文';

  @override
  String get glossarySourceHint => '单词或短语';

  @override
  String get glossaryTargetLabel => '翻译';

  @override
  String get glossaryTargetHint => '译文';

  @override
  String get upgradeScreenTitle => '升级 TransKey';

  @override
  String get upgradeChooseYourPlan => '选择套餐';

  @override
  String get upgradeUnlockFullPower => '解锁 TransKey 的全部能力';

  @override
  String get upgradeCurrentLabel => '当前';

  @override
  String get upgradePopularBadge => '热门';

  @override
  String get upgradeTryFreeDays => '免费试用 7 天';

  @override
  String upgradeTrialActivated(String info) {
    return '试用已激活!$info';
  }

  @override
  String get upgradeTrialActivateFailed => '试用激活失败';

  @override
  String get upgradeCheckoutFailed => '无法打开结账页面';

  @override
  String get upgradeMobileSubtitle => '全部功能,仅限移动端';

  @override
  String get upgradeProSubtitle => '全部功能,所有平台';

  @override
  String get upgradeFreeFeat1 => '翻译';

  @override
  String get upgradeFreeFeat2 => '20 次/天';

  @override
  String get upgradeFreeFeat3 => '2000 字符/天';

  @override
  String get upgradeFreeFeat4 => '术语库';

  @override
  String get upgradeMobileFeat1 => '全部功能';

  @override
  String get upgradeMobileFeat2 => 'iOS & Android';

  @override
  String get upgradeMobileFeat3 => '无限制';

  @override
  String get upgradeProFeat1 => '全部功能';

  @override
  String get upgradeProFeat2 => '所有平台';

  @override
  String get upgradeProFeat3 => '桌面 + 移动';

  @override
  String get upgradeFeatureColumn => '功能';

  @override
  String get upgradeMobilePrice => '📱 Mobile · \$3/月';

  @override
  String get upgradeProPrice => '💻 Pro · \$6/月';

  @override
  String get upgradeFooterHint => '📱 Mobile:只用手机的最佳性价比\n💻 Pro:手机和桌面通用';

  @override
  String get comparisonReplyTranslate => '回复翻译';

  @override
  String get comparisonMobileApps => '📱 iOS & Android';

  @override
  String get comparisonDesktop => '💻 桌面';

  @override
  String nudgeUnlock(String feature) {
    return '解锁 $feature';
  }

  @override
  String get nudgeMobileCopy => '升级到 Pro,可在所有平台\n使用此功能。';

  @override
  String get nudgeChoosePlan => '选择适合您的套餐。';

  @override
  String get nudgeMaybeLater => '稍后';

  @override
  String get nudgeMobileTitle => '📱 Mobile';

  @override
  String get nudgeProTitle => '💻 Pro';

  @override
  String get nudgeUpgradeToPro => '升级到 Pro';

  @override
  String get nudgeUpgradeToProSubtitle => '所有平台均可使用 — 桌面 + 移动';

  @override
  String get nudgePriceMobile => '\$3/月';

  @override
  String get nudgePriceProMonthly => '\$6/月';

  @override
  String get onboardWelcomeTitle => '欢迎使用 TransKey';

  @override
  String get onboardWelcomeSubtitle => '实时翻译\n20+ 种语言。';

  @override
  String get onboardChooseTitle => '选择您的语言';

  @override
  String get onboardChooseSubtitle => '选择您偏好的目标语言。\n可随时在设置中更改。';

  @override
  String get onboardStartedTitle => '开始使用';

  @override
  String get onboardStartedSubtitle => '登录或创建免费账户\n立即开始翻译。';

  @override
  String get onboardGetStarted => '开始使用';

  @override
  String get setupTitle => '设置键盘';

  @override
  String get setupOpenSettings => '打开设置';

  @override
  String get setupOpenPermissions => '打开权限';

  @override
  String get setupStep1TitleIOS => '添加 TransKey 键盘';

  @override
  String get setupStep1TitleAndroid => '启用悬浮气泡';

  @override
  String get setupStep1DescIOS => '进入设置,将 TransKey 添加为自定义键盘,即可在输入时直接翻译。';

  @override
  String get setupStep1DescAndroid => '允许 TransKey 在其他应用上层显示,即可在需要时显示悬浮气泡。';

  @override
  String get setupStep2Title => '允许完全访问';

  @override
  String get setupStep2DescIOS => '点击键盘列表中的 TransKey 并启用\"允许完全访问\"。翻译需要网络连接。';

  @override
  String get setupStep2DescAndroid => '悬浮窗权限让 TransKey 在其他应用之上显示悬浮气泡,实现快速翻译。';

  @override
  String get setupStep3Title => '全部就绪!';

  @override
  String get setupStep3DescIOS =>
      '在任意应用中输入时,长按地球仪键🌐切换到 TransKey。点击\"回复\"立即翻译您的消息。';

  @override
  String get setupStep3DescAndroid => '在任意应用中选择文本并分享到 TransKey,或使用悬浮气泡进行快速翻译。';

  @override
  String get setupStep4Title => '从任意应用翻译';

  @override
  String get setupStep4DescIOS =>
      '选择文本 → 点击\"分享\" → 选择 TransKey。或复制文本后打开 TransKey — 它会自动读取剪贴板。';

  @override
  String get setupStep4DescAndroid =>
      '在任意应用中选择文本 → 点击\"分享\" → 选择 TransKey。或复制文本后使用悬浮气泡。';

  @override
  String get setupStep5Title => 'AI 功能';

  @override
  String get setupStep5Desc => '翻译、回复、总结、解释、润色 — 均由 AI 驱动。Pro 功能带有锁形图标。';

  @override
  String get guideTitle => '使用方法';

  @override
  String get guideSubtitle => '每个功能可用的所有文本输入方式';

  @override
  String get guideIntroTitle => '捕获文本无需开启任何特殊权限。';

  @override
  String get guideIntroBody =>
      '所有功能仅在你主动操作后才读取内容 — 复制文本、扫描屏幕、选取区域、使用系统分享按钮,或从文本选择菜单点 TransKey。辅助功能只用于把 Reply 结果直接粘贴到你正在输入的聊天框。';

  @override
  String get guideFeatureTranslate => '翻译';

  @override
  String get guideFeatureTranslateSubtitle => '源语言 → 目标语言';

  @override
  String get guideFeatureSummary => '总结';

  @override
  String get guideFeatureSummarySubtitle => '将长内容浓缩为几个要点';

  @override
  String get guideFeatureRefine => '润色';

  @override
  String get guideFeatureRefineSubtitle => '改善你自己草稿的语法与清晰度';

  @override
  String get guideFeatureExplain => '解释';

  @override
  String get guideFeatureExplainSubtitle => '用通俗的语言解释难懂的文本';

  @override
  String get guideFeatureReply => '回复';

  @override
  String get guideFeatureReplySubtitle => '用目标语言生成回复建议';

  @override
  String get guideInputCopyTitle => '复制文本后点击气泡';

  @override
  String get guideInputCopyDesc => '在任意应用复制文本,然后点击悬浮气泡并选择操作。';

  @override
  String get guideInputOcrTitle => '扫描整个屏幕';

  @override
  String get guideInputOcrDesc => '点击气泡 → 扫描屏幕。TransKey 截取一张图,读取上面的文字。';

  @override
  String get guideInputRegionTitle => '扫描屏幕一部分';

  @override
  String get guideInputRegionDesc => '点击气泡 → 扫描区域。拖动方框圈出你想翻译的部分。';

  @override
  String get guideInputShareTitle => '从分享按钮';

  @override
  String get guideInputShareDesc => '在任意应用:选中文本 → 点击分享 → 选择 TransKey。';

  @override
  String guideInputMenuTitle(String feature) {
    return '从文本选择菜单 → TransKey: $feature';
  }

  @override
  String guideInputMenuDesc(String feature) {
    return '在任意应用选中文本,出现 复制/分享 弹窗。点 ⋮ 查看更多,然后选 TransKey: $feature。';
  }

  @override
  String get guideReplyA11yTitle => '辅助功能 — 可选,仅用于自动粘贴';

  @override
  String get guideReplyA11yBody =>
      '如果为 TransKey 开启辅助功能,你的回复会直接粘贴到正在输入的聊天框,无需额外步骤。\n\n如果不想开启,回复会自动复制好 — 长按聊天框点 粘贴 即可。';

  @override
  String get appPermissions => '应用权限';

  @override
  String get permissionsAllSet => '全部就绪 — 点击查看';

  @override
  String get permissionsNeedSetup => '点击授予所需权限';

  @override
  String get setupTransKey => '设置 TransKey';

  @override
  String get setupTransKeyBody => '授予悬浮气泡权限即可开始。辅助功能为可选项,仅用于一键粘贴 Reply。';

  @override
  String get permFloatingBubble => '悬浮气泡';

  @override
  String get permFloatingBubbleBody => '在其他应用上方显示 TransKey。气泡显示必需。';

  @override
  String get permRestrictedSettings => '允许受限设置';

  @override
  String get permRestrictedSettingsBody =>
      'Android 13+ 默认禁止旁加载应用使用辅助功能。点击右上角 ⋮ → \"允许受限设置\"。';

  @override
  String get permAccessibility => '辅助功能 (可选)';

  @override
  String get permAccessibilityBody =>
      '允许 TransKey 将 Reply 建议直接粘贴到当前聚焦的输入框。如果你不介意手动粘贴可以跳过。';

  @override
  String get permEnabled => '已启用';

  @override
  String get permEnable => '启用';

  @override
  String get permDone => '完成';

  @override
  String get permOpenAppDetails => '打开应用详情';

  @override
  String get permSkipHint => '辅助功能为可选项。没有它,Reply 建议会进入剪贴板,你需要自己粘贴。';

  @override
  String get permSkipForNow => '暂时跳过';

  @override
  String get permFinishedCheck => '已完成 — 检查';

  @override
  String get voiceTooltip => '语音输入';

  @override
  String get voiceListening => '正在聆听…';

  @override
  String get voicePermDenied => '麦克风权限被拒绝';

  @override
  String get voiceUnsupported => '此设备不支持语音输入';

  @override
  String get voicePickSourceLang => '请先选择源语言 — 语音输入无法自动检测';

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
