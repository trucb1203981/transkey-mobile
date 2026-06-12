// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get translate => '翻訳';

  @override
  String get summarize => '要約';

  @override
  String get explain => '説明';

  @override
  String get refine => '推敲';

  @override
  String get reply => '返信';

  @override
  String get history => '履歴';

  @override
  String get glossary => '用語集';

  @override
  String get settings => '設定';

  @override
  String get suggestions => '候補';

  @override
  String get copy => 'コピー';

  @override
  String get save => '保存';

  @override
  String get copied => 'コピーしました';

  @override
  String get delete => '削除';

  @override
  String get cancel => 'キャンセル';

  @override
  String get ok => 'OK';

  @override
  String get confirm => '確定';

  @override
  String get clear => 'クリア';

  @override
  String get dismiss => '閉じる';

  @override
  String get required => '必須';

  @override
  String get addAction => '追加';

  @override
  String get saveAction => '保存';

  @override
  String get next => '次へ';

  @override
  String get skip => 'スキップ';

  @override
  String get done => '完了';

  @override
  String get hintEnterText => '翻訳するテキストを入力...';

  @override
  String detectedLang(String lang) {
    return '検出: $lang';
  }

  @override
  String get autoDetect => '自動検出';

  @override
  String get sourceLang => '元';

  @override
  String get targetLang => '先';

  @override
  String get swapLanguages => '言語を入れ替え';

  @override
  String get settingsTitle => '設定';

  @override
  String get sectionLanguage => '言語';

  @override
  String get sectionTranslation => '翻訳';

  @override
  String get sectionAdvanced => '詳細';

  @override
  String get sectionOther => 'その他';

  @override
  String get helpImproveApp => 'アプリの改善に協力する';

  @override
  String get helpImproveAppHint =>
      '匿名の利用情報を共有して TransKey の改善に役立てます。翻訳内容や写真は送信されません。';

  @override
  String get sectionSpeech => '読み上げ';

  @override
  String get targetLanguage => '翻訳先の言語';

  @override
  String get sourceLanguage => '翻訳元の言語';

  @override
  String get appLanguage => 'アプリの言語';

  @override
  String get saveHistory => '履歴を保存';

  @override
  String get romanization => 'ローマ字';

  @override
  String get replySuggestions => '返信候補';

  @override
  String get toneOverride => '翻訳のトーン';

  @override
  String get replyToneOverride => '返信のトーン';

  @override
  String get replyLanguage => '返信の言語';

  @override
  String get replyLanguageFromConversation => '会話に合わせる';

  @override
  String get autoCloseResult => '結果を自動で閉じる';

  @override
  String get autoCloseSeconds => '自動で閉じる(秒)';

  @override
  String get autoCloseUnit => '秒';

  @override
  String get autoCloseDisabled => 'オフ';

  @override
  String get toneAuto => '自動';

  @override
  String get toneBusiness => 'ビジネス';

  @override
  String get toneCasual => 'カジュアル';

  @override
  String get toneFormal => 'フォーマル';

  @override
  String get tonePolite => '丁寧';

  @override
  String get toneTechnical => '技術的';

  @override
  String get toneNeutral => '中立';

  @override
  String get toneReplySameAsTranslate => '翻訳と同じ';

  @override
  String get popupTo => '翻訳先:';

  @override
  String get tabTranslate => '翻訳';

  @override
  String get tabReply => '返信';

  @override
  String get tabSummarize => '要約';

  @override
  String get tabExplain => '説明';

  @override
  String get tabRefine => '推敲';

  @override
  String get keyboardSetup => 'キーボード設定';

  @override
  String get keyboardSettingsTitle => 'バブル＆キーボード';

  @override
  String get keyboardSettingsSectionStatus => 'バブルと権限';

  @override
  String get keyboardSettingsSectionBehavior => 'バブルの動作';

  @override
  String get imeSectionTitle => 'キーボード';

  @override
  String get imeKeyboardTitle => 'TransKey キーボード';

  @override
  String get imeStatusActive => 'アクティブ — TransKeyで入力中';

  @override
  String get imeStatusEnabledNotSelected => '有効。タップして TransKey に切り替え。';

  @override
  String get imeStatusNotEnabled => '無効。タップしてシステム設定で有効化。';

  @override
  String get bubbleSetup => 'バブル設定';

  @override
  String get floatingBubble => 'フローティングバブル';

  @override
  String get bubbleActive => '有効';

  @override
  String get bubbleInactive => '無効';

  @override
  String get permissionsNeedSetup => '必要な権限を許可するにはタップ';

  @override
  String get sendFeedback => 'フィードバックを送信';

  @override
  String get termsOfService => '利用規約';

  @override
  String get privacyPolicy => 'プライバシーポリシー';

  @override
  String get openSourceLicenses => 'オープンソースライセンス';

  @override
  String get version => 'バージョン';

  @override
  String get upgrade => 'アップグレード';

  @override
  String get upgradeToPro => 'Proにアップグレード';

  @override
  String get logOut => 'ログアウト';

  @override
  String get changePassword => 'パスワード変更';

  @override
  String get manageDevices => 'デバイス管理';

  @override
  String get manageSubscription => 'サブスクリプション管理';

  @override
  String get currentPassword => '現在のパスワード';

  @override
  String get newPassword => '新しいパスワード';

  @override
  String get confirmPassword => '新しいパスワード(確認)';

  @override
  String get passwordTooShort => 'パスワードは8文字以上にしてください';

  @override
  String get passwordMismatch => 'パスワードが一致しません';

  @override
  String get changePasswordSuccess => 'パスワードを更新しました';

  @override
  String get changePasswordFailed => 'パスワードの更新に失敗しました';

  @override
  String get devicesTitle => '登録済みデバイス';

  @override
  String get devicesEmpty => 'まだ登録されたデバイスはありません。';

  @override
  String get devicesProLimit => 'Proプランは最大2台のデバイスを使用できます。';

  @override
  String get deviceCurrentThis => 'このデバイス';

  @override
  String deviceLastUsed(String date) {
    return '最終使用: $date';
  }

  @override
  String get removeDevice => '削除';

  @override
  String get removeDeviceConfirm => 'このデバイスを削除しますか?再ログインが必要になります。';

  @override
  String get removeDeviceFailed => 'デバイスを削除できませんでした';

  @override
  String get subscriptionTitle => 'サブスクリプション';

  @override
  String get subscriptionStatus => 'ステータス';

  @override
  String get subscriptionRenewsAt => '更新日';

  @override
  String get subscriptionEndsAt => '終了日';

  @override
  String get subscriptionTrialEndsAt => 'トライアル終了';

  @override
  String get subscriptionInactive => '有効なサブスクリプションはありません';

  @override
  String get subscriptionAdminGranted =>
      'ご利用のプランはサポートによってアクティベートされており、セルフサーブ課金経由ではありません。変更・解約はサポートまでご連絡ください。';

  @override
  String get subscriptionCancel => 'サブスクリプションをキャンセル';

  @override
  String get subscriptionCancelConfirm =>
      'Proサブスクリプションをキャンセルしますか?現在の期間が終わるまでProのまま使えます。';

  @override
  String get subscriptionCancelled => '更新日に終了します。';

  @override
  String get subscriptionCancelFailed => 'サブスクリプションをキャンセルできませんでした';

  @override
  String get voicePickerTitle => '音声';

  @override
  String get voiceDefault => 'デフォルト';

  @override
  String get speedPickerTitle => '読み上げ速度';

  @override
  String get speedNormal => '標準';

  @override
  String get feedbackTitle => 'フィードバックを送信';

  @override
  String get feedbackHint => 'ご意見をお聞かせください...';

  @override
  String get feedbackSend => '送信';

  @override
  String get feedbackThanks => 'フィードバックをありがとうございました!';

  @override
  String get feedbackFailed => 'フィードバックを送信できませんでした';

  @override
  String get feedbackCatBug => 'バグ報告';

  @override
  String get feedbackCatFeature => '機能リクエスト';

  @override
  String get feedbackCatOther => 'その他';

  @override
  String get feedbackHintBug => '期待した動作と実際の動作を教えてください。';

  @override
  String get feedbackHintFeature => 'TransKey にどんな機能があると便利ですか？';

  @override
  String get feedbackHintOther => 'ご意見をお聞かせください...';

  @override
  String get feedbackEmailLabel => 'メール(任意、返信用)';

  @override
  String get selectLanguage => '言語を選択';

  @override
  String get searchLanguages => '言語を検索...';

  @override
  String get recent => '最近';

  @override
  String get allLanguages => 'すべての言語';

  @override
  String get login => 'ログイン';

  @override
  String get signUp => '登録';

  @override
  String get logIn => 'ログイン';

  @override
  String get createAccount => 'アカウントを作成';

  @override
  String get continueWithGoogle => 'Googleで続行';

  @override
  String get orDivider => 'または';

  @override
  String get emailHint => 'メール';

  @override
  String get passwordHint => 'パスワード';

  @override
  String get nameHint => 'お名前';

  @override
  String get nameRequired => '名前を入力してください';

  @override
  String get emailRequired => 'メールを入力してください';

  @override
  String get emailInvalid => 'メールアドレスが無効です';

  @override
  String get passwordRequired => 'パスワードを入力してください';

  @override
  String get passwordMinSix => '6文字以上';

  @override
  String get proDeviceLimitError => 'Proアカウントは登録できるデバイス数の上限に達しています';

  @override
  String get deviceLimitError => 'このデバイスにアカウントが多すぎます';

  @override
  String googleSignInFailed(String error) {
    return 'Googleログインに失敗: $error';
  }

  @override
  String get googleNotConfigured => '現在Googleログインを利用できません。別の方法でログインしてください。';

  @override
  String get googleSignInNoIdToken => 'Googleログインが完了しませんでした。もう一度お試しください。';

  @override
  String get proRequired => 'Proプランが必要です';

  @override
  String get noTextToTranslate => '先にテキストを入力してください';

  @override
  String get errorGeneric => 'エラーが発生しました';

  @override
  String get errorSessionExpired => 'セッションが切れました — もう一度サインインしてください';

  @override
  String get errorInvalidCredentials => 'メールアドレスまたはパスワードが正しくありません';

  @override
  String get errorEmailNotVerified => 'メールを認証してください — 受信トレイをご確認ください';

  @override
  String get errorEmailAlreadyExists => 'このメールは既に登録されています';

  @override
  String get errorWrongPassword => '現在のパスワードが正しくありません';

  @override
  String get errorFeatureRequiresPaid => 'この機能は有料プランが必要です';

  @override
  String get errorDeviceLimit => 'デバイス数の上限に達しました — 端末を削除するかアップグレードしてください';

  @override
  String get errorMobilePlanDesktopBlocked => 'Mobile プランはデスクトップでは使えません';

  @override
  String get errorTextTooLong => 'テキストが長すぎます(最大 5000 文字)';

  @override
  String get errorQuotaExceeded => '本日の上限に達しました — 明日再度お試しいただくか、アップグレードしてください';

  @override
  String get errorRateLimit => 'リクエストが多すぎます — 少し待ってください';

  @override
  String get errorMaintenance => 'サービスはメンテナンス中です';

  @override
  String get errorNetwork => 'インターネットに接続されていません';

  @override
  String get glossaryErrSyncFailed => '用語集を同期できませんでした — 接続をご確認ください';

  @override
  String glossaryErrLimitReached(int max) {
    return '用語集が満杯です(最大 $max 件)';
  }

  @override
  String get glossaryErrSourceTargetRequired => '原文と訳文の両方が必要です';

  @override
  String get planFree => '無料';

  @override
  String get planPro => 'Pro';

  @override
  String get planMobile => 'Mobile';

  @override
  String get planTrial => 'トライアル';

  @override
  String usageRequests(int used, int limit) {
    return '$used/$limit リクエスト';
  }

  @override
  String usageCharacters(int used, int limit) {
    return '$used/$limit 文字';
  }

  @override
  String trialEndsInDays(int days) {
    return 'トライアル終了まであと$days日';
  }

  @override
  String get trialEndsToday => 'トライアルは本日終了';

  @override
  String get trialEndsTomorrow => 'トライアルは明日終了';

  @override
  String get trialUpgradeNow => '今すぐアップグレード';

  @override
  String get trialAlreadyUsed => '無料トライアルは使用済みです';

  @override
  String get subscriptionExpiredBanner => 'サブスクリプションが期限切れ';

  @override
  String get subscriptionExpiredRenew => '更新';

  @override
  String subscriptionEndsOn(String date) {
    return '$dateに終了';
  }

  @override
  String get planMobileSubscription => 'Mobileサブスクリプション';

  @override
  String get planProSubscription => 'Proサブスクリプション';

  @override
  String get discountFirstMonth => '初月−50%';

  @override
  String get accountBannedTitle => 'アカウント停止';

  @override
  String get accountBannedBody =>
      'TransKeyアカウントが停止されています。誤りと思われる場合はサポートにお問い合わせください。';

  @override
  String get accountBannedContact => 'サポートに連絡';

  @override
  String get accountBannedLogout => 'ログアウト';

  @override
  String get historyTitle => '履歴';

  @override
  String get historySearchHint => '履歴を検索...';

  @override
  String get historyFilterAll => 'すべて';

  @override
  String get historyFilterFavorites => '★ お気に入り';

  @override
  String get historyFilterLocked => '🔒 ロック';

  @override
  String get historyMenuClearAll => 'すべて削除';

  @override
  String get historyMenuKeepFavorites => 'お気に入りのみ残す';

  @override
  String get historyClearDialogTitle => '履歴を削除';

  @override
  String get historyClearDialogBody => '全履歴を削除しますか?ロックされた項目は残されます。';

  @override
  String get historyKeepFavDialogBody => 'お気に入り以外を削除しますか?ロックされた項目は残されます。';

  @override
  String get historyDetailSourceLabel => '原文';

  @override
  String get historyDetailTranslationLabel => '翻訳';

  @override
  String get historyDetailRomanizationLabel => 'ローマ字';

  @override
  String get historyDetailFavoriteBadge => '★ お気に入り';

  @override
  String get historyDetailLockedBadge => '🔒 ロック';

  @override
  String get historyDetailCopyTranslation => '翻訳を\nコピー';

  @override
  String get historyDetailCopySource => '原文を\nコピー';

  @override
  String get historyDetailUnfavorite => '解除';

  @override
  String get historyDetailFavoriteAction => 'お気に入り';

  @override
  String get historyDetailUnlock => '解除';

  @override
  String get historyDetailLockAction => 'ロック';

  @override
  String get historyDetailTtsLabel => '読上';

  @override
  String glossaryTitle(int count, int max) {
    return '用語集 ($count/$max)';
  }

  @override
  String get glossarySync => '同期';

  @override
  String get glossaryDeleteTitle => '項目を削除';

  @override
  String glossaryDeleteBody(String source) {
    return '\"$source\"を削除しますか?';
  }

  @override
  String glossaryLimitReached(int max) {
    return '用語集の上限に達しました ($max)';
  }

  @override
  String get glossarySourceTargetRequired => '原文と翻訳の両方を入力してください';

  @override
  String get glossarySyncFailed => '用語集の同期に失敗しました';

  @override
  String get glossaryEditTitle => '項目を編集';

  @override
  String get glossaryAddTitle => '項目を追加';

  @override
  String get glossarySourceLabel => '原文';

  @override
  String get glossarySourceHint => '単語またはフレーズ';

  @override
  String get glossaryTargetLabel => '翻訳';

  @override
  String get glossaryTargetHint => '訳語';

  @override
  String get glossaryNamesLabel => '用語集の名前 — タップで挿入';

  @override
  String get glossaryIsNameLabel => 'これは人名です';

  @override
  String get glossaryIsNameHint => '音声入力が名前を認識し、翻訳時にそのまま保持します。';

  @override
  String get upgradeScreenTitle => 'TransKeyをアップグレード';

  @override
  String get upgradeChooseYourPlan => 'プランを選択';

  @override
  String get upgradeUnlockFullPower => 'TransKeyの全機能を解放';

  @override
  String get upgradeCurrentLabel => '現在';

  @override
  String get upgradePopularBadge => '人気';

  @override
  String get upgradeTryFreeDays => '7日間無料で試す';

  @override
  String upgradeTrialActivated(String info) {
    return 'トライアル開始! $info';
  }

  @override
  String get upgradeTrialActivateFailed => 'トライアルの開始に失敗しました';

  @override
  String get upgradeCheckoutFailed => 'チェックアウトを開けませんでした';

  @override
  String get upgradeMobileSubtitle => '全機能、モバイル限定';

  @override
  String get upgradeProSubtitle => '全機能、全プラットフォーム';

  @override
  String get upgradeFreeFeat1 => '翻訳';

  @override
  String get upgradeFreeFeat2 => '20リクエスト/日';

  @override
  String get upgradeFreeFeat3 => '2000文字/日';

  @override
  String get upgradeFreeFeat4 => '用語集';

  @override
  String get upgradeMobileFeat1 => '全機能';

  @override
  String get upgradeMobileFeat2 => 'iOS & Android';

  @override
  String get upgradeMobileFeat3 => '無制限';

  @override
  String get upgradeProFeat1 => '全機能';

  @override
  String get upgradeProFeat2 => '全プラットフォーム';

  @override
  String get upgradeProFeat3 => 'Desktop + Mobile';

  @override
  String get upgradeFeatureColumn => '機能';

  @override
  String get upgradeFooterHint =>
      '📱 Mobile: 電話のみで使う場合のベストバリュー\n💻 Pro: 電話とデスクトップの両方で使える';

  @override
  String get comparisonReplyTranslate => '返信翻訳';

  @override
  String get comparisonMobileApps => '📱 iOS & Android';

  @override
  String get comparisonDesktop => '💻 Desktop';

  @override
  String nudgeUnlock(String feature) {
    return '$featureを解放';
  }

  @override
  String get nudgeMobileCopy => 'Proにアップグレードすると\n全プラットフォームでこの機能を使えます。';

  @override
  String get nudgeChoosePlan => 'ニーズに合うプランをお選びください。';

  @override
  String get nudgeMaybeLater => 'あとで';

  @override
  String get nudgeMobileTitle => '📱 Mobile';

  @override
  String get nudgeProTitle => '💻 Pro';

  @override
  String get nudgeUpgradeToPro => 'Proにアップグレード';

  @override
  String get nudgeUpgradeToProSubtitle => '全プラットフォームで使える — desktop + mobile';

  @override
  String nudgePriceMobile(String price) {
    return '$price/月';
  }

  @override
  String nudgePriceProMonthly(String price) {
    return '$price/月';
  }

  @override
  String get onboardWelcomeTitle => 'TransKeyへようこそ';

  @override
  String get onboardWelcomeSubtitle => '20以上の言語を\nリアルタイムで翻訳。';

  @override
  String get onboardChooseTitle => '言語を選択';

  @override
  String get onboardChooseSubtitle => '翻訳先の言語を選んでください。\n設定でいつでも変更可能。';

  @override
  String get onboardStartedTitle => 'はじめる';

  @override
  String get onboardStartedSubtitle => 'ログインまたは無料アカウントを作成して\nすぐに翻訳を始めましょう。';

  @override
  String get onboardGetStarted => 'はじめる';

  @override
  String get setupTitle => 'キーボードを設定';

  @override
  String get setupTitleAndroid => 'TransKey を設定';

  @override
  String get setupOpenSettings => '設定を開く';

  @override
  String get setupOpenPermissions => '権限を開く';

  @override
  String get setupStep1TitleIOS => 'TransKeyキーボードを追加';

  @override
  String get setupStep1TitleAndroid => 'フローティングバブルを有効化';

  @override
  String get setupStep1DescIOS =>
      '設定を開き、TransKeyをカスタムキーボードとして追加すると、入力しながら直接翻訳できます。';

  @override
  String get setupStep1DescAndroid =>
      '他のアプリの上にTransKeyを表示する権限を与えると、必要なときにフローティングバブルが表示されます。';

  @override
  String get setupStep2Title => 'フルアクセスを許可';

  @override
  String get setupStep2TitleAndroid => 'バブルが有効です';

  @override
  String get setupStep2DescIOS =>
      'キーボード一覧のTransKeyをタップし、「フルアクセスを許可」を有効にしてください。翻訳のためにインターネット接続が必要です。';

  @override
  String get setupStep2DescAndroid =>
      'オーバーレイ権限により、TransKeyは他のアプリの上にフローティングバブルを表示してすばやく翻訳できます。';

  @override
  String get setupStep3Title => '準備完了!';

  @override
  String get setupStep3DescIOS =>
      'アプリで入力中に地球儀キー🌐を長押ししてTransKeyに切り替え。「返信」をタップしてメッセージを即翻訳。';

  @override
  String get setupStep3DescAndroid =>
      'TransKeyボタンが画面に表示されました。テキストをコピーしてボタンをタップ、操作を選ぶだけ - アプリを離れずに結果が表示されます。';

  @override
  String get setupStep4Title => 'どのアプリからでも翻訳';

  @override
  String get setupStep4DescIOS =>
      'テキストを選択 → 「共有」 → TransKey を選ぶ。またはコピーしてTransKeyを開けば、クリップボードを自動で読み取ります。';

  @override
  String get setupStep4DescAndroid =>
      'アプリでテキストをコピー → TransKeyボタンをタップ → 翻訳・返信など操作を選ぶ → 終わったら画面をタップして閉じる';

  @override
  String get setupStep5Title => 'スマート機能';

  @override
  String get setupStep5Desc => '翻訳・返信・要約・説明・推敲。Pro限定機能には鍵アイコンがついています。';

  @override
  String get guideTitle => '使い方';

  @override
  String get guidePlanCompareTitle => 'プランの機能一覧';

  @override
  String get guidePlanFreeLabel => '無料';

  @override
  String get guidePlanPaidLabel => '有料';

  @override
  String get guidePlanFreeItems => '翻訳\n単語帳';

  @override
  String get guidePlanPaidItems =>
      'カメラ翻訳\n画面スキャン\n要約\n文章改善\n解説\n返信\nトーン選択\n発音記号';

  @override
  String get guideSectionFree => '無料の機能';

  @override
  String get guideSectionPaid => '有料の機能';

  @override
  String get guideFreeBadge => '無料';

  @override
  String get guidePaidBadge => '有料';

  @override
  String get guideInputPaidBadge => '有料';

  @override
  String get guideFeatureGlossary => '用語集';

  @override
  String get guideFeatureGlossarySubtitle => '優先的に使うカスタム翻訳を保存';

  @override
  String get guideInputGlossaryTitle => '用語集タブから';

  @override
  String get guideInputGlossaryDesc =>
      '用語集タブを開いて単語ペアを追加。TransKey はそれらの単語を見つけたときに優先的にカスタム訳を使います。';

  @override
  String get guideFeatureCamera => 'カメラ翻訳';

  @override
  String get guideFeatureCameraSubtitle => '看板・メニュー・本など文字を撮影して翻訳';

  @override
  String get guideInputCameraTitle => 'カメラボタンをタップ';

  @override
  String get guideInputCameraDesc =>
      'ホーム画面上部のカメラアイコンをタップ。テキストにカメラを向けて撮影すると翻訳が画像上に表示されます。';

  @override
  String get guideInputVoiceTitle => '音声でテキストを入力';

  @override
  String get guideInputVoiceDesc =>
      'ホーム画面でマイクボタンをタップして話すと、音声がテキストに変換されて自動翻訳されます。';

  @override
  String get guideSubtitle => '各機能でテキストを取り込むあらゆる方法';

  @override
  String get guideIntroTitle => 'テキスト取得に特別な権限は不要です。';

  @override
  String get guideIntroBody =>
      'どの機能も、あなたが意図的に操作したときだけテキストを読み取ります — コピー、画面のスキャン、範囲選択、システムの共有、またはテキスト選択メニューから TransKey をタップ。';

  @override
  String get guideFeatureTranslate => '翻訳';

  @override
  String get guideFeatureTranslateSubtitle => 'ソース言語 → ターゲット言語';

  @override
  String get guideFeatureSummary => '要約';

  @override
  String get guideFeatureSummarySubtitle => '長い内容を数個の要点に凝縮';

  @override
  String get guideFeatureRefine => '推敲';

  @override
  String get guideFeatureRefineSubtitle => 'あなたの下書きの文法と明瞭さを改善';

  @override
  String get guideFeatureExplain => '説明';

  @override
  String get guideFeatureExplainSubtitle => '難しい文章をやさしい言葉で解説';

  @override
  String get guideFeatureReply => '返信';

  @override
  String get guideFeatureReplySubtitle => 'ターゲット言語で返信案を生成';

  @override
  String get guideInputCopyTitle => 'テキストをコピーしてバブルをタップ';

  @override
  String get guideInputCopyDesc => '任意のアプリでテキストをコピーし、フローティングバブルをタップしてアクションを選択。';

  @override
  String get guideInputOcrTitle => '画面全体をスキャン';

  @override
  String get guideInputOcrDesc =>
      'バブル → 画面スキャン。TransKey がスクリーンショットを 1 枚撮り、その上の文字を読み取ります。';

  @override
  String get guideInputRegionTitle => '画面の一部だけスキャン';

  @override
  String get guideInputRegionDesc => 'バブル → 範囲をスキャン。翻訳したい部分だけを四角で囲んでください。';

  @override
  String get guideInputShareTitle => '共有ボタンから';

  @override
  String get guideInputShareDesc => '任意のアプリ:テキストを選択 → 共有をタップ → TransKey を選択。';

  @override
  String guideInputMenuTitle(String feature) {
    return 'テキスト選択メニューから → TransKey: $feature';
  }

  @override
  String guideInputMenuDesc(String feature) {
    return 'アプリでテキストを選択するとコピー/共有のポップアップが出ます。⋮ をタップしてその他のオプションから TransKey: $feature を選択。';
  }

  @override
  String get voiceTooltip => '音声入力';

  @override
  String get voiceListening => '聞き取り中…';

  @override
  String get voiceNeedsLang => '音声入力には元の言語を指定してください';

  @override
  String get voicePermDenied => 'マイクの権限が拒否されました';

  @override
  String get voiceUnsupported => 'この端末では音声入力を利用できません';

  @override
  String get voicePickSourceLang => '先に元の言語を選択してください — 音声入力は自動検出できません';

  @override
  String get paywallTitle => '本日の上限に達しました';

  @override
  String get paywallBody =>
      '本日の無料枠 20 リクエスト / 2,000 文字を使い切りました。短い広告を視聴して続けるか、アップグレードして無制限にご利用ください。無料枠は深夜にリセットされます。';

  @override
  String get paywallWatchAdCta => '広告を見て続ける';

  @override
  String get paywallWatchAdSub => '広告ごとに追加のリクエスト数と文字数を獲得できます。1日の視聴回数に制限はありません。';

  @override
  String get paywallUpgradeCta => 'アップグレード — 無制限、広告なし';

  @override
  String paywallUpgradeSub(String price) {
    return '$price/月から。いつでもキャンセル可能。';
  }

  @override
  String get paywallDismiss => 'あとで';

  @override
  String get paywallLoading => '読み込み中…';

  @override
  String get paywallAdNotComplete => '広告が完了しませんでした — もう一度試して報酬を獲得してください。';

  @override
  String get paywallCreditFailed => '報酬を付与できませんでした。少し時間をおいて再試行してください。';

  @override
  String get quotaWatchAd => '+ 広告を見る';

  @override
  String get quotaRewardGranted => '本日の枠に報酬が追加されました';

  @override
  String get historyEmpty => '翻訳履歴はまだありません';

  @override
  String get glossaryEmpty => '用語集は空です';

  @override
  String get glossaryEmptyAddCta => '用語を追加';

  @override
  String get captureKeepaliveTitle => '再スキャン許可の保持時間';

  @override
  String get captureKeepaliveHint => 'ダブルタップで再スキャン';

  @override
  String get captureKeepaliveExplain =>
      'スキャン後、画面キャプチャ許可をこの時間だけ保持し、次回ダブルタップ（または再度Lens選択）でシステム許可を再要求せずに済むようにします。長く保持するほど操作が減りますが、画面録画インジケーターが表示され続け、端末がわずかに発熱します。';

  @override
  String get bubbleIdleTitle => 'Bubble auto-stop';

  @override
  String get bubbleIdleExplain =>
      'Stop the floating bubble when you haven\'t used it for a while. Saves battery.';

  @override
  String get bubbleIdleOff => 'Never';

  @override
  String bubbleIdleMinutes(int count) {
    return '$count min';
  }

  @override
  String get captureKeepaliveOff => 'オフ';

  @override
  String get captureKeepaliveOffHint => '毎回許可を要求します。プライバシー・省電力重視。';

  @override
  String get captureKeepaliveDefaultHint => '推奨 — 再スキャン速度とバッテリーのバランス。';

  @override
  String get captureKeepaliveShortHint => '録画表示は短めですが、許可ダイアログが頻繁に出ます。';

  @override
  String get captureKeepaliveLongHint => '最速の再スキャン。録画インジケーターが長く表示されます。';

  @override
  String captureKeepaliveMinutes(int count) {
    return '$count 分';
  }

  @override
  String get cameraTitle => 'カメラ';

  @override
  String get cameraCapture => '撮影';

  @override
  String get cameraRetake => '撮り直し';

  @override
  String get cameraCopyAll => 'すべてコピー';

  @override
  String get cameraNoText => 'テキストが検出されません。もう一度お試しください。';

  @override
  String get cameraTapShowTranslations => 'タップして翻訳を表示';

  @override
  String get cameraLowQuality => '画質が低い';

  @override
  String get cameraConfidenceReliable => '信頼できる';

  @override
  String get cameraConfidenceCaution => '要確認';

  @override
  String get cameraConfidenceUnreliable => '信頼できない';

  @override
  String get cameraHoldSteady => '動かさないで';

  @override
  String get cameraPausedTitle => 'カメラ一時停止中';

  @override
  String get cameraPausedTapToResume => 'タップして再開';

  @override
  String get cameraWaitFocus => 'ピント合わせ中、動かさないで';

  @override
  String get cameraCopyTranslation => '訳をコピー';

  @override
  String get cameraCopyOriginal => '原文をコピー';

  @override
  String get cameraRetryBlock => 'もう一度翻訳';

  @override
  String get cameraSaveBlock => 'フレーズ集に保存';

  @override
  String get cameraSavingPhrasebook => '保存中…';

  @override
  String get cameraBlockRetrying => '再翻訳中…';

  @override
  String cameraBatchProgress(int current, int total) {
    return '$total枚中 $current枚目を翻訳中…';
  }

  @override
  String get cameraSaveNoteLabel => 'メモを追加（任意）';

  @override
  String get cameraSaveNoteHint => '例：ホテルの近く、辛い';

  @override
  String get cameraSaveSkipNote => 'スキップ';

  @override
  String get cameraCopyLineHeader => '行ごとにコピー';

  @override
  String get cameraSignStoreName => '店名';

  @override
  String get cameraSignPhone => '電話番号';

  @override
  String get cameraSignAddress => '住所';

  @override
  String get cameraShare => '共有';

  @override
  String get cameraShareSubject => 'TransKeyで翻訳';

  @override
  String get cameraShareFailed => '共有できませんでした。再試行してください。';

  @override
  String get cameraTranslating => '翻訳中...';

  @override
  String get cameraTranslate => '翻訳する';

  @override
  String get cameraPermission => 'この機能を使用するにはカメラの許可が必要です。';

  @override
  String get cameraSettingsTitle => 'カメラ設定';

  @override
  String get cameraSettingsReset => 'リセット';

  @override
  String get cameraSettingsConfidence => '不明瞭な文字を隠す';

  @override
  String get cameraSettingsConfidenceHint =>
      'はっきり読めない文字を隠します。高いほど厳しく、結果がすっきりしますが薄い文字を逃すことがあります。';

  @override
  String get cameraOriginalLabel => '元';

  @override
  String get cameraSettingsHideLow => '低品質ブロックを非表示';

  @override
  String get cameraSettingsHideLowHint => 'しきい値以上でも警告レベル未満のブロックを非表示。クリーンな書類向け。';

  @override
  String get cameraSettingsShowOriginal => '元のテキストを表示';

  @override
  String get cameraSettingsShowOriginalHint => '各翻訳カードの下に元のテキストを常に表示。';

  @override
  String get cameraSettingsOpacity => 'オーバーレイの透明度';

  @override
  String get cameraSettingsOpacityHint => 'カード背景の透明度。低い = 後ろの写真がより見える。';

  @override
  String get cameraSettingsFontScale => '文字サイズ';

  @override
  String get cameraSettingsFontScaleHint =>
      '翻訳テキストを大きくします。テキストが吹き出しからはみ出る場合があります。';

  @override
  String get cameraSettingsPrimaryColor => '統一オーバーレイカラー';

  @override
  String get cameraSettingsPrimaryColorHint =>
      '写真から色を検出する代わりに、すべてのカードにアプリカラーを使用します。';

  @override
  String get cameraSceneAuto => '自動';

  @override
  String get cameraSceneDocument => '書類';

  @override
  String get cameraSceneMenu => 'メニュー';

  @override
  String get cameraSceneSign => '看板';

  @override
  String get cameraSceneScreenshot => 'スクリーンショット';

  @override
  String get cameraSceneManga => 'マンガ';

  @override
  String get cameraSceneOther => 'その他';

  @override
  String get cameraScenePickerTitle => '何をキャプチャしますか？';

  @override
  String get cameraScenePickerHint =>
      'より正確な結果を得るために、まずモードを選択してください。下の選択バーから切り替えることもできます。';

  @override
  String get cameraSceneAutoDesc => '最適なモードを自動的に選択';

  @override
  String get cameraSceneMangaDesc => '漫画 / Web漫画 / 中国漫画 / コミック - 吹き出しごとに1カード';

  @override
  String get cameraSceneMenuDesc => 'レストランメニュー - 明らかな価格はスキップ';

  @override
  String get cameraSceneSignDesc => '店舗、看板、バナー';

  @override
  String get cameraSceneDocumentDesc => '公文書、書籍、論文';

  @override
  String get cameraSceneScreenshotDesc => 'アプリやウェブサイトのスクリーンショット';

  @override
  String get mangaNoDialogue => 'セリフが見つかりません';

  @override
  String get splittingItems => '項目を分割中…';

  @override
  String cameraDetected(String scene) {
    return '検出: $scene';
  }

  @override
  String get cameraWhatIsThis => 'これは何?';

  @override
  String get cameraWhatIsThisHint => 'プレビューの文字をタップして質問';

  @override
  String get cameraExplainTitle => 'これは何?';

  @override
  String get cameraEditTextTitle => 'テキストを編集';

  @override
  String get cameraReExplain => '再解析';

  @override
  String get cameraExplainEmpty => '説明がありません。';

  @override
  String get cameraExplainStaleBadge => 'オフライン保存 — 古い可能性あり';

  @override
  String get cameraExplainError => '説明を取得できませんでした。再試行。';

  @override
  String get cameraResultExplainHint => 'カードを長押しして質問';

  @override
  String get cameraExplainDisclaimer => '参考のみ — 実際の意味と異なる場合があります';

  @override
  String get phrasebookTitle => 'フレーズ集';

  @override
  String get phrasebookEmpty => 'フレーズ集は空です。カメラでテキストを認識し、保存をタップ。';

  @override
  String get phrasebookSave => '保存';

  @override
  String get phrasebookSaved => '保存しました';

  @override
  String get phrasebookSaveFailed => '保存できませんでした。再試行。';

  @override
  String get phrasebookTitleTooLong => 'タイトルが長すぎます（最大1000文字）。短くしてから再試行してください。';

  @override
  String get phrasebookDelete => '削除';

  @override
  String get phrasebookDeleteConfirm => 'フレーズ集から削除しますか？';

  @override
  String get phrasebookDeleted => '削除しました';

  @override
  String get phrasebookNote => 'メモ';

  @override
  String get phrasebookNoteHint => '例: ... のお店で注文 — 辛すぎ';

  @override
  String get phrasebookNoteSave => 'メモを保存';

  @override
  String get phrasebookCopy => 'コピー';

  @override
  String get phrasebookViewAll => 'フレーズ集を開く';

  @override
  String get phrasebookCategoryAll => 'すべて';

  @override
  String get phrasebookCategoryMenu => 'メニュー';

  @override
  String get phrasebookCategoryPlace => '場所';

  @override
  String get phrasebookCategoryDocument => '文書';

  @override
  String get phrasebookCategoryOther => 'その他';

  @override
  String get phrasebookCategoryChange => 'カテゴリ変更';

  @override
  String get cameraTipsTitle => 'カメラのヒント';

  @override
  String get cameraTipsGotIt => 'OK';

  @override
  String get cameraTip1Title => 'モードを選ぶ';

  @override
  String get cameraTip1Body =>
      'スキャンする対象を選ぶと結果が良くなります：メニュー、お店の看板、書類 — または何でもAuto。';

  @override
  String get cameraTip2Title => '言語を選ぶ';

  @override
  String get cameraTip2Body =>
      '読み取る言語と翻訳先の言語を選びます（左上）。看板や文字がうまく出ないときは、Autoのままにせず読み取る言語を選んでください。';

  @override
  String get cameraTip3Title => '「これは何？」と聞く';

  @override
  String get cameraTip3Body => '結果を長押しすると、その料理や場所が何かが分かり、声に出した読み方も聞けます。';

  @override
  String get cameraTip4Title => 'ドラッグで削除';

  @override
  String get cameraTip4Body => '不要なカードは下のゴミ箱エリアにドラッグして削除します。';

  @override
  String get cameraTip5Title => '保存済みの写真をスキャン';

  @override
  String get cameraTip5Body => 'シャッター横のギャラリーアイコンをタップして、端末内の写真を翻訳できます。';

  @override
  String get upgradePurchaseSuccess => 'サブスクリプションを有効化しました。お楽しみください！';

  @override
  String get upgradeRestoreSuccess => '購入を復元しました。サブスクリプションは有効です。';

  @override
  String get upgradeRestoreNothing => '復元する以前の購入はありません。';

  @override
  String get upgradePickProPeriod => 'Proプランを選択';

  @override
  String get upgradePickMobilePeriod => 'Mobileプランを選択';

  @override
  String get upgradeRestoreButton => '購入を復元';

  @override
  String get homeTagline => '翻訳 · 要約 · 解説';

  @override
  String get historyEmptyTagline => '翻訳がここに表示されます';

  @override
  String get glossaryEmptyTagline => 'よく使う用語を保存して正確な名前にする';

  @override
  String get quotaTodayUsage => '今日の使用量';

  @override
  String get quotaWallTitle => '本日の利用枠を使い切りました';

  @override
  String get quotaWallBody => '短い広告を見て翻訳回数を追加するか、アップグレードして無制限に使えます。';

  @override
  String get quotaWallWatchAdCta => '広告を見て回数を追加';

  @override
  String get quotaWallUpgradeCta => 'アップグレードして無制限利用';

  @override
  String get quotaWallCloseCta => 'あとで';

  @override
  String get guideScreenshotTipTitle => 'バブルを写さずにスクショ';

  @override
  String get guideScreenshotTipBody =>
      'バブルをタップしてメニューを開き、右下のカメラアイコンをタップします。バブルが数秒間消えるので、きれいなスクリーンショットを撮れます。その後は自動で戻ります。';

  @override
  String get accountDeleteButton => 'アカウントを削除';

  @override
  String get accountDeleteTitle => 'アカウントを削除しますか?';

  @override
  String get accountDeleteWarning =>
      'アカウントと関連するすべてのデータ(履歴、フレーズ帳、端末情報)が完全に削除され、元に戻せません。有料プランをご利用中の場合は、先にストアで解約してください。';

  @override
  String get accountDeleteConfirm => '完全に削除';

  @override
  String get accountDeleteFailed => 'アカウントを削除できませんでした。もう一度お試しください。';

  @override
  String get continueWithApple => 'Appleで続ける';

  @override
  String get appleSignInFailed => 'Appleサインインに失敗しました。もう一度お試しください。';
}
