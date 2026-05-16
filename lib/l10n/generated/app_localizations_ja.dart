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
  String get bubbleSetup => 'バブル設定';

  @override
  String get floatingBubble => 'フローティングバブル';

  @override
  String get bubbleActive => '有効';

  @override
  String get bubbleInactive => '無効';

  @override
  String get sendFeedback => 'フィードバックを送信';

  @override
  String get termsOfService => '利用規約';

  @override
  String get privacyPolicy => 'プライバシーポリシー';

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
  String get accessibilityPasteBack => '返信を他のアプリに貼り付け';

  @override
  String get accessibilityPasteBackDesc =>
      'アクセシビリティ設定でTransKeyを有効にすると、「貼り付け」でフォーカス中の入力欄に返信を直接書き込めます。';

  @override
  String get accessibilityEnabled => '有効';

  @override
  String get accessibilityDisabled => '未有効 — タップして設定を開く';

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
  String get googleNotConfigured => 'Googleログインが未設定です(serverClientIdがありません)';

  @override
  String get googleSignInNoIdToken =>
      'GoogleからidTokenが返されません — serverClientIdを確認してください';

  @override
  String get proRequired => 'Proプランが必要です';

  @override
  String get noTextToTranslate => '先にテキストを入力してください';

  @override
  String get errorGeneric => 'エラーが発生しました';

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
  String get upgradeMobilePrice => '📱 Mobile · \$3/月';

  @override
  String get upgradeProPrice => '💻 Pro · \$6/月';

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
  String get nudgePriceMobile => '\$3/月';

  @override
  String get nudgePriceProMonthly => '\$6/月';

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
  String get setupStep2DescIOS =>
      'キーボード一覧のTransKeyをタップし、「フルアクセスを許可」を有効にしてください。翻訳のためにインターネット接続が必要です。';

  @override
  String get setupStep2DescAndroid =>
      'オーバーレイ権限により、TransKeyは他のアプリの上にフローティングバブルを表示してすばやく翻訳できます。';

  @override
  String get setupStep3Title => '準備完了!';

  @override
  String get setupStep3DescIOS =>
      'アプリで入力中に地球儀キー🌐を長押ししてTransKeyに切り替え。「Reply」をタップしてメッセージを即翻訳。';

  @override
  String get setupStep3DescAndroid =>
      'アプリでテキストを選択してTransKeyに共有するか、フローティングバブルで素早く翻訳できます。';

  @override
  String get setupStep4Title => 'どのアプリからでも翻訳';

  @override
  String get setupStep4DescIOS =>
      'テキストを選択 → 「共有」 → TransKey を選ぶ。またはコピーしてTransKeyを開けば、クリップボードを自動で読み取ります。';

  @override
  String get setupStep4DescAndroid =>
      'テキストを選択 → 「共有」 → TransKey を選ぶ。またはコピー後にフローティングバブルを使えます。';

  @override
  String get setupStep5Title => 'AI機能';

  @override
  String get setupStep5Desc =>
      '翻訳・返信・要約・説明・推敲 — すべてAI搭載。Pro限定機能には鍵アイコンがついています。';
}
