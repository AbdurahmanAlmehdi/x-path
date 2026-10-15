// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'XPath';

  @override
  String get statusConnecting => 'Connecting';

  @override
  String get statusConnected => 'Connected';

  @override
  String get statusReconnecting => 'Reconnecting';

  @override
  String get statusUnreachable => 'Unreachable · cached';

  @override
  String get statusSecretsLocked => 'Secrets locked';

  @override
  String get statusRejected => 'Token refused';

  @override
  String bannerReconnecting(String engine) {
    return '$engine stopped answering. XPath keeps trying; what you see may be out of date.';
  }

  @override
  String bannerUnreachable(String engine) {
    return '$engine is unreachable. Showing what was cached, read-only, until it is back.';
  }

  @override
  String bannerSecretsLocked(String engine) {
    return 'The Keychain on $engine is locked. Jobs queue until it is unlocked.';
  }

  @override
  String bannerRejected(String engine) {
    return '$engine refused the token of this Mac. Add the engine again with a new token.';
  }

  @override
  String get bannerRetry => 'Retry';

  @override
  String get bannerEngines => 'Engines…';

  @override
  String get readOnlyHint => 'Read-only while the engine is away';

  @override
  String get sidebarProjects => 'Projects';

  @override
  String get sidebarEngine => 'Engine';

  @override
  String get sidebarCredentials => 'Credentials';

  @override
  String get sidebarEngines => 'Engines';

  @override
  String get sidebarAddProject => 'Add project…';

  @override
  String get sidebarNoProjects => 'No projects yet';

  @override
  String projectApps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count apps',
      one: '1 app',
    );
    return '$_temp0';
  }

  @override
  String projectErrors(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count errors',
      one: '1 error',
    );
    return '$_temp0';
  }

  @override
  String projectWarnings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count warnings',
      one: '1 warning',
    );
    return '$_temp0';
  }

  @override
  String get engineMenuManage => 'Manage engines…';

  @override
  String get enginesTitle => 'Engines';

  @override
  String get enginesSubtitle =>
      'Where XPath runs your builds. The app shows one engine at a time.';

  @override
  String get enginesLocalName => 'This Mac';

  @override
  String get enginesActive => 'Showing';

  @override
  String get enginesUse => 'Show';

  @override
  String get enginesRemove => 'Remove';

  @override
  String get enginesSetUpLocal => 'Set up this Mac…';

  @override
  String get enginesAddTitle => 'Add a remote engine';

  @override
  String enginesAddHelp(String device) {
    return 'On the engine machine, run xpd token create --name \"$device\" --kind app and paste the token here. It is kept in the Keychain of this Mac.';
  }

  @override
  String get enginesAddButton => 'Add engine';

  @override
  String get enginesChecking => 'Checking…';

  @override
  String get fieldName => 'Name';

  @override
  String get fieldNameHint => 'mac-mini';

  @override
  String get fieldUrl => 'URL';

  @override
  String get fieldUrlHint => 'http://mac-mini.local:7480';

  @override
  String get fieldToken => 'Token';

  @override
  String get engineCheckInvalidUrl =>
      'Enter an http(s) URL with a host, like http://mac-mini.local:7480.';

  @override
  String get engineCheckUnreachable =>
      'Nothing answered at that URL. Is xpd serve running there, and can this Mac reach it?';

  @override
  String get engineCheckNotAnEngine =>
      'Something answered at that URL, but it is not an XPath engine.';

  @override
  String get engineCheckApiMismatch =>
      'The engine speaks another version of the API. Update the one that is behind.';

  @override
  String get engineCheckTokenRejected =>
      'The engine refused this token. Make a new one with xpd token create --kind app.';

  @override
  String engineNoTokenTitle(String engine) {
    return 'No token for $engine';
  }

  @override
  String get engineNoTokenBody =>
      'The Keychain of this Mac has no token for this engine, or it could not be read. Remove the engine and add it again.';

  @override
  String get onboardingTitle => 'Set up XPath on this Mac';

  @override
  String get onboardingSubtitle =>
      'XPath runs a small engine in the background that does the builds, signing and uploads. Three steps; nothing leaves this Mac.';

  @override
  String get onboardingEngineTitle => 'Start the engine';

  @override
  String get onboardingEngineBody =>
      'Registers the engine as a login item, so it runs now and at every login, and connects this app to it.';

  @override
  String get onboardingEngineButton => 'Start engine';

  @override
  String get onboardingEngineEnabled =>
      'The engine runs and this app is connected to it.';

  @override
  String get onboardingEngineApproval =>
      'Allow XPath in System Settings ▸ General ▸ Login Items, then start the engine again.';

  @override
  String get onboardingOpenLoginItems => 'Open Login Items…';

  @override
  String get onboardingEngineNotFound =>
      'This build has no engine inside it. Use an engine by URL instead.';

  @override
  String get onboardingEngineUnsupported =>
      'Running the engine as a login item needs macOS 13 or later.';

  @override
  String onboardingEngineFailed(String message) {
    return 'macOS did not register the engine: $message';
  }

  @override
  String onboardingTokenFailed(String message) {
    return 'The engine runs, but XPath could not make a token for this app: $message';
  }

  @override
  String onboardingAppTokenName(String device) {
    return 'XPath app on $device';
  }

  @override
  String get onboardingCliTitle => 'Add xp to your PATH';

  @override
  String get onboardingCliBody =>
      'Links the xp command line tool inside this app, so you and your agents can use it in a terminal. No password needed.';

  @override
  String get onboardingCliButton => 'Link xp';

  @override
  String cliLinked(String path) {
    return 'Linked at $path.';
  }

  @override
  String cliLinkedFallback(String path) {
    return 'Linked at $path. Writing /usr/local/bin needs an administrator password, so XPath used ~/.local/bin instead; add it to your PATH if your shell does not have it.';
  }

  @override
  String get cliMissing => 'This build has no xp inside it.';

  @override
  String cliConflict(String path) {
    return '$path is another xp. XPath left it alone.';
  }

  @override
  String cliFailed(String detail) {
    return 'Could not link xp: $detail';
  }

  @override
  String get onboardingToolsTitle => 'Check the tools';

  @override
  String get onboardingToolsBody =>
      'The engine builds with the tools of this Mac. Xcode and git are needed; the others only when you use them.';

  @override
  String get onboardingToolsButton => 'Check tools';

  @override
  String get toolXcode => 'Xcode';

  @override
  String get toolGit => 'git';

  @override
  String get toolFvm => 'fvm';

  @override
  String get toolGh => 'GitHub CLI';

  @override
  String get toolShorebird => 'Shorebird';

  @override
  String get toolFound => 'Found';

  @override
  String get toolMissing => 'Missing';

  @override
  String get toolOptional => 'Optional';

  @override
  String get toolXcodeHint =>
      'Install Xcode from the App Store and open it once.';

  @override
  String get toolGitHint =>
      'Comes with the developer tools: xcode-select --install.';

  @override
  String get toolFvmHint =>
      'Without fvm the engine downloads the Flutter each project pins.';

  @override
  String get toolGhHint =>
      'Lets the engine use your GitHub login: brew install gh.';

  @override
  String get toolShorebirdHint => 'Only for over-the-air patches.';

  @override
  String get onboardingDone => 'Open XPath';

  @override
  String get onboardingRemote => 'Use a remote engine instead…';

  @override
  String get onboardingBack => 'Back';

  @override
  String get stepDone => 'Done';

  @override
  String get stepWorking => 'Working…';

  @override
  String get addProjectTitle => 'Add project';

  @override
  String get addProjectBody =>
      'Pick the folder of a git repository. XPath reads it and never writes to it; builds run from the engine\'s own copy.';

  @override
  String addProjectRemoteNote(String engine) {
    return 'The folder has to be on $engine, the machine the engine runs on.';
  }

  @override
  String get addProjectFolder => 'Folder';

  @override
  String get addProjectFolderHint => '/Users/you/src/app';

  @override
  String get addProjectChoose => 'Choose folder…';

  @override
  String get addProjectAdd => 'Add and scan';

  @override
  String get addProjectScanning => 'Scanning…';

  @override
  String addProjectFailed(String message) {
    return 'The engine could not add this folder: $message';
  }

  @override
  String addProjectReviewTitle(String name) {
    return 'Review the scan of $name';
  }

  @override
  String get addProjectReviewBody =>
      'This is what XPath found. Fix errors in the repository and scan again; warnings and notes can wait.';

  @override
  String get addProjectKeep => 'Done';

  @override
  String get addProjectDiscard => 'Remove project';

  @override
  String get scanAgain => 'Scan again';

  @override
  String get scanFindings => 'Findings';

  @override
  String get scanNoFindings => 'Nothing to fix.';

  @override
  String scanFix(String fix) {
    return 'Fix: $fix';
  }

  @override
  String get scanNoApps => 'No Flutter app found.';

  @override
  String scanAppMeta(String path, String version, String country) {
    return 'path $path · Flutter $version · store country $country';
  }

  @override
  String get scanUnpinned => 'not pinned';

  @override
  String get scanColumnFlavor => 'Flavor';

  @override
  String get scanColumnIos => 'iOS bundle ID';

  @override
  String get scanColumnAndroid => 'Android application ID';

  @override
  String get scanColumnShorebird => 'Shorebird';

  @override
  String get scanShorebirdOn => 'on';

  @override
  String get scanShorebirdOff => 'off';

  @override
  String get scanProd => 'prod';

  @override
  String get scanError => 'Error';

  @override
  String get scanWarning => 'Warning';

  @override
  String get scanInfo => 'Info';

  @override
  String projectSubtitle(String branch, String apps) {
    return '$branch · $apps';
  }

  @override
  String get projectEmptyTitle => 'No projects yet';

  @override
  String get projectEmptyBody =>
      'Add the folder of a Flutter app\'s repository to start.';

  @override
  String get projectGone => 'This project is no longer on the engine.';

  @override
  String get credentialsTitle => 'Credentials';

  @override
  String get credentialsSubtitle =>
      'Checked every day and before each build. The secrets stay on the engine machine.';

  @override
  String get credentialsNoProject =>
      'Add a project first: credentials belong to its flavors.';

  @override
  String get credentialsEmpty => 'No credentials yet.';

  @override
  String get credentialsAdd => 'Add credential…';

  @override
  String get credentialsVerify => 'Check now';

  @override
  String get credentialsReplace => 'Replace…';

  @override
  String get credentialsDelete => 'Delete';

  @override
  String get credentialsColumnFlavor => 'Flavor';

  @override
  String get credentialsColumnKind => 'Kind';

  @override
  String get credentialsColumnAccount => 'Account';

  @override
  String get credentialsColumnStatus => 'Status';

  @override
  String get credentialVerified => 'Verified';

  @override
  String get credentialRejected => 'Rejected';

  @override
  String get credentialUnchecked => 'Not checked';

  @override
  String credentialFailed(String message) {
    return 'Not saved: $message';
  }

  @override
  String get kindAscKey => 'App Store Connect API key';

  @override
  String get kindAppleId => 'Apple ID';

  @override
  String get kindPlaySa => 'Google Play service account';

  @override
  String get kindFirebaseSa => 'Firebase service account';

  @override
  String get kindKeystore => 'Android keystore';

  @override
  String get kindShorebird => 'Shorebird API key';

  @override
  String get kindGithub => 'GitHub token';

  @override
  String get kindSlack => 'Slack webhook';

  @override
  String get credentialFormTitle => 'Add a credential';

  @override
  String get credentialFormHelp =>
      'The engine checks it with the place it is for before it keeps it. Nothing is stored if the check fails.';

  @override
  String get fieldFlavor => 'Flavor';

  @override
  String get fieldKind => 'Kind';

  @override
  String get fieldKeyId => 'Key ID';

  @override
  String get fieldIssuerId => 'Issuer ID';

  @override
  String get fieldPrivateKey => 'Private key (.p8)';

  @override
  String get fieldAppleId => 'Apple ID';

  @override
  String get fieldAppPassword => 'App-specific password';

  @override
  String get fieldServiceAccount => 'Service account key (JSON)';

  @override
  String get fieldKeystore => 'Keystore';

  @override
  String get fieldStorePassword => 'Store password';

  @override
  String get fieldKeyAlias => 'Key alias';

  @override
  String get fieldKeyPassword => 'Key password (if not the store password)';

  @override
  String get fieldWebhookUrl => 'Webhook URL';

  @override
  String get fieldChooseFile => 'Choose file…';

  @override
  String fieldFileChosen(String name, int bytes) {
    return '$name · $bytes bytes';
  }

  @override
  String get credentialFormSave => 'Check and save';

  @override
  String get credentialFormCancel => 'Cancel';
}
