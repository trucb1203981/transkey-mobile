// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get translate => 'Traduzir';

  @override
  String get summarize => 'Resumir';

  @override
  String get explain => 'Explicar';

  @override
  String get refine => 'Aprimorar';

  @override
  String get reply => 'Responder';

  @override
  String get history => 'Histórico';

  @override
  String get glossary => 'Glossário';

  @override
  String get settings => 'Configurações';

  @override
  String get suggestions => 'Sugestões';

  @override
  String get copy => 'Copiar';

  @override
  String get save => 'Salvar';

  @override
  String get copied => 'Copiado';

  @override
  String get delete => 'Excluir';

  @override
  String get cancel => 'Cancelar';

  @override
  String get ok => 'OK';

  @override
  String get confirm => 'Confirmar';

  @override
  String get clear => 'Limpar';

  @override
  String get dismiss => 'Dispensar';

  @override
  String get required => 'Obrigatório';

  @override
  String get addAction => 'Adicionar';

  @override
  String get saveAction => 'Salvar';

  @override
  String get next => 'Próximo';

  @override
  String get skip => 'Pular';

  @override
  String get done => 'Concluído';

  @override
  String get hintEnterText => 'Digite o texto para traduzir...';

  @override
  String detectedLang(String lang) {
    return 'Detectado: $lang';
  }

  @override
  String get autoDetect => 'Detecção automática';

  @override
  String get sourceLang => 'Origem';

  @override
  String get targetLang => 'Destino';

  @override
  String get swapLanguages => 'Inverter idiomas';

  @override
  String get settingsTitle => 'Configurações';

  @override
  String get sectionLanguage => 'Idioma';

  @override
  String get sectionTranslation => 'Tradução';

  @override
  String get sectionAdvanced => 'Avançado';

  @override
  String get sectionOther => 'Outros';

  @override
  String get sectionSpeech => 'Ler em voz alta';

  @override
  String get targetLanguage => 'Idioma de destino';

  @override
  String get sourceLanguage => 'Idioma de origem';

  @override
  String get appLanguage => 'Idioma do app';

  @override
  String get saveHistory => 'Salvar histórico';

  @override
  String get romanization => 'Romanização';

  @override
  String get replySuggestions => 'Sugestões de resposta';

  @override
  String get toneOverride => 'Tom da tradução';

  @override
  String get replyToneOverride => 'Tom da resposta';

  @override
  String get replyLanguage => 'Idioma da resposta';

  @override
  String get replyLanguageFromConversation => 'A partir da conversa';

  @override
  String get autoCloseResult => 'Fechar resultado automaticamente';

  @override
  String get autoCloseSeconds => 'Fechar automaticamente (segundos)';

  @override
  String get autoCloseUnit => 'segundos';

  @override
  String get autoCloseDisabled => 'Desativado';

  @override
  String get toneAuto => 'Automático';

  @override
  String get toneBusiness => 'Comercial';

  @override
  String get toneCasual => 'Casual';

  @override
  String get toneFormal => 'Formal';

  @override
  String get tonePolite => 'Educado';

  @override
  String get toneTechnical => 'Técnico';

  @override
  String get toneNeutral => 'Neutro';

  @override
  String get toneReplySameAsTranslate => 'Igual à tradução';

  @override
  String get popupTo => 'Para:';

  @override
  String get tabTranslate => 'Traduzir';

  @override
  String get tabReply => 'Responder';

  @override
  String get tabSummarize => 'Resumir';

  @override
  String get tabExplain => 'Explicar';

  @override
  String get tabRefine => 'Aprimorar';

  @override
  String get keyboardSetup => 'Configuração do teclado';

  @override
  String get bubbleSetup => 'Configuração do botão flutuante';

  @override
  String get floatingBubble => 'Botão flutuante';

  @override
  String get bubbleActive => 'Ativo';

  @override
  String get bubbleInactive => 'Inativo';

  @override
  String get sendFeedback => 'Enviar feedback';

  @override
  String get termsOfService => 'Termos de Serviço';

  @override
  String get privacyPolicy => 'Política de Privacidade';

  @override
  String get version => 'Versão';

  @override
  String get upgrade => 'Atualizar';

  @override
  String get upgradeToPro => 'Atualizar para Pro';

  @override
  String get logOut => 'Sair';

  @override
  String get changePassword => 'Alterar senha';

  @override
  String get manageDevices => 'Gerenciar dispositivos';

  @override
  String get manageSubscription => 'Gerenciar assinatura';

  @override
  String get currentPassword => 'Senha atual';

  @override
  String get newPassword => 'Nova senha';

  @override
  String get confirmPassword => 'Confirmar nova senha';

  @override
  String get passwordTooShort => 'A senha deve ter no mínimo 8 caracteres';

  @override
  String get passwordMismatch => 'As senhas não coincidem';

  @override
  String get changePasswordSuccess => 'Senha atualizada';

  @override
  String get changePasswordFailed => 'Falha ao atualizar a senha';

  @override
  String get devicesTitle => 'Dispositivos registrados';

  @override
  String get devicesEmpty => 'Nenhum dispositivo registrado ainda.';

  @override
  String get devicesProLimit => 'O plano Pro permite até 2 dispositivos.';

  @override
  String get deviceCurrentThis => 'Este dispositivo';

  @override
  String deviceLastUsed(String date) {
    return 'Último uso: $date';
  }

  @override
  String get removeDevice => 'Remover';

  @override
  String get removeDeviceConfirm =>
      'Remover este dispositivo? Ele precisará fazer login novamente.';

  @override
  String get removeDeviceFailed => 'Não foi possível remover o dispositivo';

  @override
  String get subscriptionTitle => 'Assinatura';

  @override
  String get subscriptionStatus => 'Status';

  @override
  String get subscriptionRenewsAt => 'Renova em';

  @override
  String get subscriptionEndsAt => 'Termina em';

  @override
  String get subscriptionTrialEndsAt => 'Avaliação termina em';

  @override
  String get subscriptionInactive => 'Nenhuma assinatura ativa';

  @override
  String get subscriptionAdminGranted =>
      'Seu plano foi ativado pelo suporte, não através do autoatendimento. Entre em contato conosco para alterá-lo ou cancelá-lo.';

  @override
  String get subscriptionCancel => 'Cancelar assinatura';

  @override
  String get subscriptionCancelConfirm =>
      'Cancelar sua assinatura Pro? Você manterá o Pro até o fim do período atual.';

  @override
  String get subscriptionCancelled =>
      'A assinatura terminará na data de renovação.';

  @override
  String get subscriptionCancelFailed =>
      'Não foi possível cancelar a assinatura';

  @override
  String get voicePickerTitle => 'Voz';

  @override
  String get voiceDefault => 'Padrão';

  @override
  String get speedPickerTitle => 'Velocidade da fala';

  @override
  String get speedNormal => 'Normal';

  @override
  String get accessibilityPasteBack => 'Colar resposta em outros aplicativos';

  @override
  String get accessibilityPasteBackDesc =>
      'Ative o TransKey nas configurações de Acessibilidade para permitir que \"Colar\" escreva a resposta no campo focado de qualquer app.';

  @override
  String get accessibilityEnabled => 'Ativado';

  @override
  String get accessibilityDisabled =>
      'Não ativado — toque para abrir as configurações';

  @override
  String get feedbackTitle => 'Enviar feedback';

  @override
  String get feedbackHint => 'Conte-nos o que você acha...';

  @override
  String get feedbackSend => 'Enviar';

  @override
  String get feedbackThanks => 'Obrigado pelo seu feedback!';

  @override
  String get feedbackFailed => 'Falha ao enviar feedback';

  @override
  String get feedbackCatBug => 'Reportar um bug';

  @override
  String get feedbackCatFeature => 'Solicitar funcionalidade';

  @override
  String get feedbackCatOther => 'Outro';

  @override
  String get feedbackHintBug =>
      'O que você esperava que acontecesse e o que aconteceu?';

  @override
  String get feedbackHintFeature =>
      'O que você gostaria que o TransKey fizesse?';

  @override
  String get feedbackHintOther => 'Compartilhe suas ideias...';

  @override
  String get feedbackEmailLabel => 'E-mail (opcional, para uma resposta)';

  @override
  String get selectLanguage => 'Selecionar idioma';

  @override
  String get searchLanguages => 'Buscar idiomas...';

  @override
  String get recent => 'Recentes';

  @override
  String get allLanguages => 'Todos os idiomas';

  @override
  String get login => 'Entrar';

  @override
  String get signUp => 'Cadastrar';

  @override
  String get logIn => 'Entrar';

  @override
  String get createAccount => 'Criar conta';

  @override
  String get continueWithGoogle => 'Continuar com Google';

  @override
  String get orDivider => 'ou';

  @override
  String get emailHint => 'E-mail';

  @override
  String get passwordHint => 'Senha';

  @override
  String get nameHint => 'Seu nome';

  @override
  String get nameRequired => 'O nome é obrigatório';

  @override
  String get emailRequired => 'O e-mail é obrigatório';

  @override
  String get emailInvalid => 'Digite um e-mail válido';

  @override
  String get passwordRequired => 'A senha é obrigatória';

  @override
  String get passwordMinSix => 'Mínimo de 6 caracteres';

  @override
  String get proDeviceLimitError =>
      'Conta Pro já registrada no número máximo de dispositivos';

  @override
  String get deviceLimitError => 'Muitas contas neste dispositivo';

  @override
  String googleSignInFailed(String error) {
    return 'Falha no login com Google: $error';
  }

  @override
  String get googleNotConfigured =>
      'Login com Google não configurado (serverClientId ausente)';

  @override
  String get googleSignInNoIdToken =>
      'O login com Google não retornou idToken — verifique o serverClientId';

  @override
  String get proRequired => 'Plano Pro necessário';

  @override
  String get noTextToTranslate => 'Digite um texto primeiro';

  @override
  String get errorGeneric => 'Algo deu errado';

  @override
  String get errorSessionExpired => 'Sessão expirada — entre novamente';

  @override
  String get errorInvalidCredentials => 'E-mail ou senha incorretos';

  @override
  String get errorEmailNotVerified =>
      'Verifique seu e-mail — confira sua caixa de entrada';

  @override
  String get errorFeatureRequiresPaid =>
      'Esta funcionalidade requer um plano pago';

  @override
  String get errorDeviceLimit =>
      'Limite de dispositivos atingido — remova um dispositivo ou faça upgrade';

  @override
  String get errorMobilePlanDesktopBlocked =>
      'O plano Mobile não pode ser usado no desktop';

  @override
  String get errorTextTooLong =>
      'Texto muito longo (máximo de 5000 caracteres)';

  @override
  String get errorQuotaExceeded =>
      'Limite diário atingido — tente novamente amanhã ou faça upgrade';

  @override
  String get errorRateLimit => 'Muitas solicitações — aguarde um momento';

  @override
  String get errorMaintenance => 'O serviço está em manutenção';

  @override
  String get errorNetwork => 'Sem conexão com a internet';

  @override
  String get glossaryErrSyncFailed =>
      'Não foi possível sincronizar o glossário — verifique sua conexão';

  @override
  String glossaryErrLimitReached(int max) {
    return 'O glossário está cheio (máximo de $max entradas)';
  }

  @override
  String get glossaryErrSourceTargetRequired =>
      'Origem e destino são obrigatórios';

  @override
  String get planFree => 'Gratuito';

  @override
  String get planPro => 'Pro';

  @override
  String get planMobile => 'Mobile';

  @override
  String get planTrial => 'Avaliação';

  @override
  String usageRequests(int used, int limit) {
    return '$used/$limit solicitações';
  }

  @override
  String usageCharacters(int used, int limit) {
    return '$used/$limit caracteres';
  }

  @override
  String trialEndsInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'dias',
      one: 'dia',
    );
    return 'Avaliação termina em $days $_temp0';
  }

  @override
  String get trialEndsToday => 'Avaliação termina hoje';

  @override
  String get trialEndsTomorrow => 'Avaliação termina amanhã';

  @override
  String get trialUpgradeNow => 'Atualizar agora';

  @override
  String get trialAlreadyUsed => 'Você já usou sua avaliação gratuita';

  @override
  String get subscriptionExpiredBanner => 'Sua assinatura expirou';

  @override
  String get subscriptionExpiredRenew => 'Renovar';

  @override
  String subscriptionEndsOn(String date) {
    return 'Termina em $date';
  }

  @override
  String get planMobileSubscription => 'Assinatura Mobile';

  @override
  String get planProSubscription => 'Assinatura Pro';

  @override
  String get discountFirstMonth => '−50% no primeiro mês';

  @override
  String get accountBannedTitle => 'Conta suspensa';

  @override
  String get accountBannedBody =>
      'Sua conta TransKey foi suspensa. Entre em contato com o suporte se você acredita que isso é um engano.';

  @override
  String get accountBannedContact => 'Contatar suporte';

  @override
  String get accountBannedLogout => 'Sair';

  @override
  String get historyTitle => 'Histórico';

  @override
  String get historySearchHint => 'Buscar no histórico...';

  @override
  String get historyFilterAll => 'Tudo';

  @override
  String get historyFilterFavorites => '★ Favoritos';

  @override
  String get historyFilterLocked => '🔒 Bloqueados';

  @override
  String get historyMenuClearAll => 'Limpar tudo';

  @override
  String get historyMenuKeepFavorites => 'Manter apenas favoritos';

  @override
  String get historyClearDialogTitle => 'Limpar histórico';

  @override
  String get historyClearDialogBody =>
      'Excluir todo o histórico? As entradas bloqueadas serão mantidas.';

  @override
  String get historyKeepFavDialogBody =>
      'Excluir todas as entradas não-favoritas? As entradas bloqueadas serão mantidas.';

  @override
  String get historyDetailSourceLabel => 'Origem';

  @override
  String get historyDetailTranslationLabel => 'Tradução';

  @override
  String get historyDetailRomanizationLabel => 'Romanização';

  @override
  String get historyDetailFavoriteBadge => '★ Favorito';

  @override
  String get historyDetailLockedBadge => '🔒 Bloqueado';

  @override
  String get historyDetailCopyTranslation => 'Copiar\ntradução';

  @override
  String get historyDetailCopySource => 'Copiar\norigem';

  @override
  String get historyDetailUnfavorite => 'Desfavoritar';

  @override
  String get historyDetailFavoriteAction => 'Favoritar';

  @override
  String get historyDetailUnlock => 'Desbloquear';

  @override
  String get historyDetailLockAction => 'Bloquear';

  @override
  String get historyDetailTtsLabel => 'TTS';

  @override
  String glossaryTitle(int count, int max) {
    return 'Glossário ($count/$max)';
  }

  @override
  String get glossarySync => 'Sincronizar';

  @override
  String get glossaryDeleteTitle => 'Excluir entrada';

  @override
  String glossaryDeleteBody(String source) {
    return 'Excluir \"$source\"?';
  }

  @override
  String glossaryLimitReached(int max) {
    return 'Limite do glossário atingido ($max)';
  }

  @override
  String get glossarySourceTargetRequired =>
      'Origem e destino são obrigatórios';

  @override
  String get glossarySyncFailed => 'Falha ao sincronizar o glossário';

  @override
  String get glossaryEditTitle => 'Editar entrada';

  @override
  String get glossaryAddTitle => 'Adicionar entrada';

  @override
  String get glossarySourceLabel => 'Origem';

  @override
  String get glossarySourceHint => 'Palavra ou frase';

  @override
  String get glossaryTargetLabel => 'Destino';

  @override
  String get glossaryTargetHint => 'Tradução';

  @override
  String get glossaryNamesLabel => 'Nomes do glossário — toque para inserir';

  @override
  String get glossaryIsNameLabel => 'Este é o nome de uma pessoa';

  @override
  String get glossaryIsNameHint =>
      'Ajuda a entrada de voz a reconhecer o nome e diz à IA para preservá-lo exatamente.';

  @override
  String get upgradeScreenTitle => 'Atualizar TransKey';

  @override
  String get upgradeChooseYourPlan => 'Escolha seu plano';

  @override
  String get upgradeUnlockFullPower => 'Desbloqueie todo o poder do TransKey';

  @override
  String get upgradeCurrentLabel => 'Atual';

  @override
  String get upgradePopularBadge => 'Popular';

  @override
  String get upgradeTryFreeDays => 'Experimente grátis por 7 dias';

  @override
  String upgradeTrialActivated(String info) {
    return 'Avaliação ativada! $info';
  }

  @override
  String get upgradeTrialActivateFailed => 'Falha ao ativar a avaliação';

  @override
  String get upgradeCheckoutFailed => 'Falha ao abrir o checkout';

  @override
  String get upgradeMobileSubtitle => 'Todos os recursos, apenas mobile';

  @override
  String get upgradeProSubtitle => 'Todos os recursos, todas as plataformas';

  @override
  String get upgradeFreeFeat1 => 'Traduzir';

  @override
  String get upgradeFreeFeat2 => '20 solicitações/dia';

  @override
  String get upgradeFreeFeat3 => '2000 caracteres/dia';

  @override
  String get upgradeFreeFeat4 => 'Glossário';

  @override
  String get upgradeMobileFeat1 => 'Todos os recursos';

  @override
  String get upgradeMobileFeat2 => 'iOS e Android';

  @override
  String get upgradeMobileFeat3 => 'Ilimitado';

  @override
  String get upgradeProFeat1 => 'Todos os recursos';

  @override
  String get upgradeProFeat2 => 'Todas as plataformas';

  @override
  String get upgradeProFeat3 => 'Desktop + Mobile';

  @override
  String get upgradeFeatureColumn => 'Recurso';

  @override
  String get upgradeMobilePrice => '📱 Mobile · \$3/mo';

  @override
  String get upgradeProPrice => '💻 Pro · \$6/mo';

  @override
  String get upgradeFooterHint =>
      '📱 Mobile: melhor custo-benefício se você só usa o celular\n💻 Pro: funciona no celular e no desktop';

  @override
  String get comparisonReplyTranslate => 'Tradução de resposta';

  @override
  String get comparisonMobileApps => '📱 iOS e Android';

  @override
  String get comparisonDesktop => '💻 Desktop';

  @override
  String nudgeUnlock(String feature) {
    return 'Desbloquear $feature';
  }

  @override
  String get nudgeMobileCopy =>
      'Atualize para o Pro para usar este recurso\nem todas as plataformas.';

  @override
  String get nudgeChoosePlan =>
      'Escolha um plano que atenda às suas necessidades.';

  @override
  String get nudgeMaybeLater => 'Talvez depois';

  @override
  String get nudgeMobileTitle => '📱 Mobile';

  @override
  String get nudgeProTitle => '💻 Pro';

  @override
  String get nudgeUpgradeToPro => 'Atualizar para Pro';

  @override
  String get nudgeUpgradeToProSubtitle =>
      'Use em todas as plataformas — desktop + mobile';

  @override
  String get nudgePriceMobile => '\$3/month';

  @override
  String get nudgePriceProMonthly => '\$6/month';

  @override
  String get onboardWelcomeTitle => 'Bem-vindo ao TransKey';

  @override
  String get onboardWelcomeSubtitle =>
      'Traduza textos em tempo real em\nmais de 20 idiomas instantaneamente.';

  @override
  String get onboardChooseTitle => 'Escolha seu idioma';

  @override
  String get onboardChooseSubtitle =>
      'Escolha seu idioma de destino preferido.\nVocê pode alterá-lo a qualquer momento nas configurações.';

  @override
  String get onboardStartedTitle => 'Começar';

  @override
  String get onboardStartedSubtitle =>
      'Entre ou crie uma conta gratuita\npara começar a traduzir agora.';

  @override
  String get onboardGetStarted => 'Começar';

  @override
  String get setupTitle => 'Configurar teclado';

  @override
  String get setupOpenSettings => 'Abrir configurações';

  @override
  String get setupOpenPermissions => 'Abrir permissões';

  @override
  String get setupStep1TitleIOS => 'Adicionar o teclado TransKey';

  @override
  String get setupStep1TitleAndroid => 'Ativar botão flutuante';

  @override
  String get setupStep1DescIOS =>
      'Acesse as Configurações e adicione o TransKey como teclado personalizado para traduzir diretamente enquanto digita.';

  @override
  String get setupStep1DescAndroid =>
      'Permita que o TransKey seja exibido sobre outros aplicativos para que o botão flutuante apareça quando você precisar.';

  @override
  String get setupStep2Title => 'Permitir acesso completo';

  @override
  String get setupStep2DescIOS =>
      'Toque em TransKey na lista de teclados e ative \"Permitir acesso completo\". Isso é necessário para conectar-se à internet para as traduções.';

  @override
  String get setupStep2DescAndroid =>
      'A permissão de sobreposição permite que o TransKey mostre um botão flutuante sobre outros aplicativos para traduções rápidas.';

  @override
  String get setupStep3Title => 'Tudo pronto!';

  @override
  String get setupStep3DescIOS =>
      'Ao digitar em qualquer app, pressione e segure a tecla do globo 🌐 para mudar para o TransKey. Toque em \"Responder\" para traduzir sua mensagem instantaneamente.';

  @override
  String get setupStep3DescAndroid =>
      'Selecione o texto em qualquer app e compartilhe com o TransKey, ou use o botão flutuante para traduções rápidas.';

  @override
  String get setupStep4Title => 'Traduzir de qualquer app';

  @override
  String get setupStep4DescIOS =>
      'Selecione qualquer texto → toque em \"Compartilhar\" → escolha TransKey. Ou copie o texto e abra o TransKey — ele lê sua área de transferência automaticamente.';

  @override
  String get setupStep4DescAndroid =>
      'Selecione o texto em qualquer app → toque em \"Compartilhar\" → escolha TransKey. Ou use o botão flutuante após copiar o texto.';

  @override
  String get setupStep5Title => 'Recursos inteligentes';

  @override
  String get setupStep5Desc =>
      'Traduzir, Responder, Resumir, Explicar e Aprimorar — tudo com IA. Os recursos Pro estão marcados com um ícone de cadeado.';

  @override
  String get guideTitle => 'Como usar';

  @override
  String get guideSubtitle =>
      'Todas as maneiras de capturar texto para cada recurso';

  @override
  String get guideIntroTitle =>
      'Não são necessárias permissões especiais para capturar texto.';

  @override
  String get guideIntroBody =>
      'Cada recurso lê o texto somente depois que você faz algo intencionalmente — copia o texto, escaneia a tela, escolhe uma área, usa o botão Compartilhar do sistema ou toca em TransKey no menu de seleção de texto. A configuração de Acessibilidade só é usada para que o resultado de Responder possa colar-se sozinho no campo de chat em que você está digitando.';

  @override
  String get guideFeatureTranslate => 'Traduzir';

  @override
  String get guideFeatureTranslateSubtitle =>
      'Idioma de origem → idioma de destino';

  @override
  String get guideFeatureSummary => 'Resumo';

  @override
  String get guideFeatureSummarySubtitle =>
      'Reduz conteúdos longos a alguns tópicos';

  @override
  String get guideFeatureRefine => 'Aprimorar';

  @override
  String get guideFeatureRefineSubtitle =>
      'Melhora a gramática / clareza do seu próprio texto';

  @override
  String get guideFeatureExplain => 'Explicar';

  @override
  String get guideFeatureExplainSubtitle =>
      'Receba uma explicação simples de textos difíceis';

  @override
  String get guideFeatureReply => 'Responder';

  @override
  String get guideFeatureReplySubtitle =>
      'Gera uma sugestão de resposta no idioma de destino';

  @override
  String get guideInputCopyTitle => 'Copie o texto, depois toque no botão';

  @override
  String get guideInputCopyDesc =>
      'Copie qualquer texto em qualquer app, depois toque no botão flutuante e escolha a ação.';

  @override
  String get guideInputOcrTitle => 'Escanear a tela inteira';

  @override
  String get guideInputOcrDesc =>
      'Toque no botão → Escanear tela. O TransKey faz uma captura de tela e lê o texto nela.';

  @override
  String get guideInputRegionTitle => 'Escanear parte da tela';

  @override
  String get guideInputRegionDesc =>
      'Toque no botão → Escanear área. Arraste uma caixa em volta apenas da parte que você quer traduzir.';

  @override
  String get guideInputShareTitle => 'Pelo botão Compartilhar';

  @override
  String get guideInputShareDesc =>
      'Dentro de qualquer app, selecione o texto → toque em Compartilhar → escolha TransKey.';

  @override
  String guideInputMenuTitle(String feature) {
    return 'Pelo menu de seleção de texto → TransKey: $feature';
  }

  @override
  String guideInputMenuDesc(String feature) {
    return 'Selecione o texto em qualquer app — o popup com Copiar/Compartilhar aparece. Toque em ⋮ para mais opções e escolha TransKey: $feature.';
  }

  @override
  String get guideReplyA11yTitle =>
      'Acessibilidade — opcional, apenas para colagem automática';

  @override
  String get guideReplyA11yBody =>
      'Se a Acessibilidade estiver ativada para o TransKey, sua resposta é colada direto no campo de chat em que você está digitando. Sem etapa extra.\n\nSe preferir não ativar, a resposta é copiada para você — basta pressionar e segurar o campo de chat e tocar em Colar.';

  @override
  String get appPermissions => 'Permissões do app';

  @override
  String get permissionsAllSet => 'Tudo configurado — toque para revisar';

  @override
  String get permissionsNeedSetup =>
      'Toque para conceder as permissões necessárias';

  @override
  String get setupTransKey => 'Configurar TransKey';

  @override
  String get setupTransKeyBody =>
      'Conceda a permissão do botão flutuante para começar. A Acessibilidade é opcional e só é necessária para colar respostas com um toque.';

  @override
  String get permFloatingBubble => 'Botão flutuante';

  @override
  String get permFloatingBubbleBody =>
      'Mostrar o TransKey sobre outros aplicativos. Obrigatório para que o botão apareça.';

  @override
  String get permRestrictedSettings => 'Permitir configurações restritas';

  @override
  String get permRestrictedSettingsBody =>
      'O Android 13+ bloqueia apps instalados por fora da loja em Acessibilidade por padrão. Toque em ⋮ no canto superior direito → \"Permitir configurações restritas\".';

  @override
  String get permAccessibility => 'Acessibilidade (opcional)';

  @override
  String get permAccessibilityBody =>
      'Permite que o TransKey cole sugestões de resposta direto no campo de texto focado. Pule se você não se importar em colar você mesmo.';

  @override
  String get permEnabled => 'Ativado';

  @override
  String get permEnable => 'Ativar';

  @override
  String get permDone => 'Concluído';

  @override
  String get permOpenAppDetails => 'Abrir detalhes do app';

  @override
  String get permSkipHint =>
      'A Acessibilidade é opcional. Sem ela, as sugestões de resposta vão para a área de transferência e você precisa colá-las.';

  @override
  String get permSkipForNow => 'Pular por enquanto';

  @override
  String get permFinishedCheck => 'Terminei — verificar';

  @override
  String get voiceTooltip => 'Falar para digitar';

  @override
  String get voiceListening => 'Ouvindo…';

  @override
  String get voiceNeedsLang =>
      'Defina um idioma de origem específico para usar a voz';

  @override
  String get voicePermDenied => 'Permissão de microfone negada';

  @override
  String get voiceUnsupported =>
      'Entrada de voz não disponível neste dispositivo';

  @override
  String get voicePickSourceLang =>
      'A entrada de voz precisa de um idioma específico. Escolha um idioma de origem e toque no microfone novamente.';

  @override
  String get paywallTitle => 'Limite diário atingido';

  @override
  String get paywallBody =>
      'Você usou a cota gratuita de hoje de 20 solicitações / 2.000 caracteres. Assista a um anúncio curto para continuar ou faça upgrade para uso ilimitado. Sua cota gratuita é redefinida à meia-noite.';

  @override
  String get paywallWatchAdCta => 'Assistir anúncio para continuar';

  @override
  String get paywallWatchAdSub =>
      'Ganhe solicitações e caracteres extras a cada anúncio. Sem limite de anúncios por dia.';

  @override
  String get paywallUpgradeCta => 'Atualizar — ilimitado, sem anúncios';

  @override
  String get paywallUpgradeSub =>
      'A partir de \$3/month. Cancele a qualquer momento.';

  @override
  String get paywallDismiss => 'Talvez depois';

  @override
  String get paywallLoading => 'Carregando…';

  @override
  String get paywallAdNotComplete =>
      'O anúncio não foi concluído — tente novamente para ganhar a recompensa.';

  @override
  String get paywallCreditFailed =>
      'Não foi possível creditar a recompensa. Tente novamente em um momento.';

  @override
  String get quotaWatchAd => '+ Assistir anúncio';

  @override
  String get quotaRewardGranted => 'Recompensa creditada na cota de hoje';

  @override
  String get historyEmpty => 'Ainda não há histórico de tradução';

  @override
  String get glossaryEmpty => 'Glossário vazio';

  @override
  String get glossaryEmptyAddCta => 'Adicionar entrada';

  @override
  String get captureKeepaliveTitle => 'Janela de re-escaneamento rápido';

  @override
  String get captureKeepaliveHint => 'toque duplo no botão = re-escanear';

  @override
  String get captureKeepaliveExplain =>
      'Após escanear a tela, mantenha a permissão de captura pronta para que você possa tocar duas vezes no botão (ou escolher Escanear tela novamente) sem o aviso de permissão do sistema. Janelas mais longas economizam toques mas mantêm o indicador de transmissão visível e aquecem levemente o dispositivo.';

  @override
  String get captureKeepaliveOff => 'Desativado';

  @override
  String get captureKeepaliveOffHint =>
      'Cada escaneamento pede permissão novamente. Melhor para privacidade / bateria.';

  @override
  String get captureKeepaliveDefaultHint =>
      'Recomendado — equilibra velocidade de re-escaneamento com bateria.';

  @override
  String get captureKeepaliveShortHint =>
      'Menos tempo de transmissão, mas mais avisos de permissão frequentes.';

  @override
  String get captureKeepaliveLongHint =>
      'Velocidade máxima de re-escaneamento. O indicador de transmissão fica ativo por mais tempo.';

  @override
  String captureKeepaliveMinutes(int count) {
    return '$count min';
  }
}
