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
  String get bannerLocalStopped => 'The engine on this Mac isn\'t running.';

  @override
  String get bannerLocalStarting => 'Starting the engine on this Mac…';

  @override
  String get bannerSecretsLockedSteps =>
      'Sign in to that Mac, or unlock its login keychain in Keychain Access; jobs start again by themselves.';

  @override
  String get bannerShowLog => 'Show log in Finder';

  @override
  String get bannerSetUpAgain => 'Set up this Mac again';

  @override
  String get localEngineStart => 'Start engine';

  @override
  String get localEngineNoEngine =>
      'This copy of XPath has no engine macOS can start. Open XPath from Applications, or install it again.';

  @override
  String get localEngineNeedsApproval =>
      'macOS is waiting for you. Allow XPath in System Settings ▸ General ▸ Login Items, then start the engine.';

  @override
  String get localEngineUnsupported =>
      'Running the engine needs macOS 13 or later.';

  @override
  String localEngineRefused(String message) {
    return 'macOS did not start the engine: $message';
  }

  @override
  String get localEngineTimedOut =>
      'The engine did not answer within 30 seconds. Its log is in ~/Library/Application Support/XPath/service-logs/xpd.log.';

  @override
  String localEngineToken(String message) {
    return 'The engine runs, but XPath could not make a new token for this app: $message';
  }

  @override
  String get localEngineRunning => 'Running';

  @override
  String get localEngineNotRunning => 'Not running';

  @override
  String get localEngineStarting => 'Starting…';

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
  String enginesRemoveTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String enginesRemoveForget(String name) {
    return 'This Mac forgets $name and its token.';
  }

  @override
  String get enginesRemoveKeeps =>
      'The engine keeps running, with its projects and releases. Adding it again needs a new token.';

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
      'The Keychain of this Mac has no token for this engine, or it could not be read. Try again once the Keychain is unlocked, or remove the engine and add it again.';

  @override
  String get engineNoTokenRetry => 'Try again';

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
  String cliElsewhere(String path, String pointsTo) {
    return '$path links to another copy of XPath ($pointsTo). Link xp again to use this one.';
  }

  @override
  String get cliNotLinked => 'xp is not linked, so a terminal cannot find it.';

  @override
  String get cliChecking => 'Looking for xp…';

  @override
  String get cliRelink => 'Link xp again';

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
  String addProjectRemoveTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String get addProjectRemoveForget =>
      'The engine forgets the project and what its scan found.';

  @override
  String get addProjectRemoveKeeps =>
      'Nothing in the folder or on GitHub changes.';

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
      'Shared by every project on this engine. Checked every day and before each build; the secrets stay on the engine machine.';

  @override
  String get credentialsNoProject =>
      'Add a project to give its flavors credentials.';

  @override
  String get credentialsEmpty =>
      'No credentials yet. Add one, then assign it to the flavors that need it.';

  @override
  String get credentialsAdd => 'Add credential…';

  @override
  String get credentialsVerify => 'Check now';

  @override
  String get credentialsReplace => 'Replace secret…';

  @override
  String get credentialsDelete => 'Delete…';

  @override
  String get credentialsRename => 'Rename…';

  @override
  String get credentialsColumnName => 'Name';

  @override
  String get credentialsColumnUsedBy => 'Used by';

  @override
  String get credentialsColumnAssigned => 'Credentials';

  @override
  String credentialsUsedBy(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count flavors',
      one: '1 flavor',
      zero: 'Not used',
    );
    return '$_temp0';
  }

  @override
  String get credentialsFlavorsTitle => 'Flavors';

  @override
  String get credentialsFlavorsHelp =>
      'Each flavor uses at most one credential of each kind. Several flavors, of any project, can share one.';

  @override
  String get credentialsNoneAssigned => 'None assigned';

  @override
  String get credentialsManage => 'Manage…';

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
  String credentialFormReplaceTitle(String name) {
    return 'Replace the secret of $name';
  }

  @override
  String get credentialFormReplaceHelp =>
      'Its name and the flavors that use it stay. The engine checks the new secret first; nothing changes if the check fails. The old secret is not shown.';

  @override
  String get fieldCredentialName => 'Name';

  @override
  String get fieldCredentialNameHint => 'Team App Store key';

  @override
  String get fieldKeyKind => 'Key type';

  @override
  String get keyKindTeam => 'Team key';

  @override
  String get keyKindIndividual => 'Individual key';

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
  String fieldFileChosen(String name, String size) {
    return '$name · $size';
  }

  @override
  String get credentialFormSave => 'Check and save';

  @override
  String get credentialFormCancel => 'Cancel';

  @override
  String renameCredentialTitle(String name) {
    return 'Rename $name';
  }

  @override
  String get renameCredentialHelp =>
      'Its secret and the flavors that use it stay.';

  @override
  String get renameCredentialConfirm => 'Rename';

  @override
  String deleteCredentialTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get deleteCredentialSecret =>
      'Its secret is deleted from the engine machine.';

  @override
  String get deleteCredentialUnused => 'No flavor uses it.';

  @override
  String deleteCredentialUsed(int count, String kind) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count flavors use it. They will have no $kind until you assign another:',
      one: '1 flavor uses it. It will have no $kind until you assign another:',
    );
    return '$_temp0';
  }

  @override
  String get deleteCredentialKeep => 'Keep it';

  @override
  String get deleteCredentialConfirm => 'Delete';

  @override
  String get deleteCredentialConfirmInUse => 'Unassign and delete';

  @override
  String flavorCredentialsTitle(String flavor) {
    return 'Credentials of $flavor';
  }

  @override
  String get flavorCredentialsHelp =>
      'The credential this flavor uses for each kind, with what the last checks found: does it work, and can it reach this flavor\'s app.';

  @override
  String get flavorStoreIds => 'Store ids';

  @override
  String get flavorStoreIdsHelp =>
      'The built-in workflows upload this flavor\'s builds to these apps when a dispatch names none. The scan fills in the Firebase ids its files name.';

  @override
  String get flavorFirebaseAndroid => 'Firebase app id · Android';

  @override
  String get flavorFirebaseIos => 'Firebase app id · iOS';

  @override
  String flavorFirebaseHint(String platform) {
    return '1:123456789012:$platform:abc123';
  }

  @override
  String get flavorAppleAppId => 'App Store Connect app id';

  @override
  String get flavorAppleAppIdHint => '1234567890';

  @override
  String get flavorStoreIdsSave => 'Save ids';

  @override
  String get flavorStoreIdsSaved =>
      'Saved. The next dispatch uploads to these apps.';

  @override
  String get scanSetStoreId => 'Set the id…';

  @override
  String get flavorCredentialsNotAssigned => 'Not assigned';

  @override
  String get flavorCredentialsAssign => 'Assign…';

  @override
  String get flavorCredentialsChange => 'Change…';

  @override
  String get flavorCredentialsRemove => 'Remove from this flavor';

  @override
  String get flavorCredentialsCredential => 'Credential';

  @override
  String get flavorCredentialsAddNew => 'Add new…';

  @override
  String get flavorCredentialsUseFor => 'Use for';

  @override
  String get flavorCredentialsThisFlavor => 'This flavor';

  @override
  String flavorCredentialsEveryFlavor(String app) {
    return 'Every flavor of $app';
  }

  @override
  String get flavorCredentialsReplace => 'Replace existing';

  @override
  String flavorCredentialsReplaceOff(String kind) {
    return 'Flavors that have their own $kind keep it.';
  }

  @override
  String flavorCredentialsReplaceOn(String kind) {
    return 'Every flavor of the app uses this $kind, even those that have their own.';
  }

  @override
  String get flavorCredentialsConfirm => 'Assign';

  @override
  String get flavorCredentialsCreate => 'Check, save and assign';

  @override
  String flavorCredentialsKept(int count, String flavors) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$flavors kept their own credentials. Tick “Replace existing” to change them too.',
      one:
          '$flavors kept its own credential. Tick “Replace existing” to change it too.',
    );
    return '$_temp0';
  }

  @override
  String get statusQueued => 'Queued';

  @override
  String get statusRunning => 'Running';

  @override
  String get statusSucceeded => 'Succeeded';

  @override
  String get statusFailed => 'Failed';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get statusSkipped => 'Skipped · already done';

  @override
  String get statusInterrupted => 'Interrupted';

  @override
  String get statusWaitingForResume => 'Waiting for a resume';

  @override
  String get statusWaitingForApproval => 'Waiting for approval';

  @override
  String get releaseDraft => 'Draft';

  @override
  String get releaseBuilding => 'Building';

  @override
  String get releaseUploaded => 'Uploaded';

  @override
  String get releaseInReview => 'In review';

  @override
  String get releaseRejected => 'Rejected';

  @override
  String get releaseApproved => 'Approved';

  @override
  String get releaseLive => 'Live';

  @override
  String get releaseMerged => 'Merged';

  @override
  String get releaseAbandoned => 'Abandoned';

  @override
  String get storeNotUploaded => 'Not uploaded';

  @override
  String get storeUploaded => 'Uploaded';

  @override
  String get storeInReview => 'In review';

  @override
  String get storeRejected => 'Rejected';

  @override
  String get storeNotApproved => 'Not approved';

  @override
  String get storePendingRelease => 'Pending developer release';

  @override
  String get storeApprovedUnpublished => 'Approved · not published';

  @override
  String get storeReadyForSale => 'Ready for sale';

  @override
  String get storePublished => 'Published';

  @override
  String get storeAppStore => 'App Store';

  @override
  String get storeGooglePlay => 'Google Play';

  @override
  String get platformIos => 'iOS';

  @override
  String get platformAndroid => 'Android';

  @override
  String get stepGitCheckout => 'Check out';

  @override
  String get stepGuard => 'Checks';

  @override
  String get stepVersionBump => 'Bump version';

  @override
  String get stepBuildAndroid => 'Build Android';

  @override
  String get stepBuildIos => 'Build iOS';

  @override
  String get stepVerifyConfig => 'Verify compiled config';

  @override
  String get stepStripIpa => 'Strip and re-export IPA';

  @override
  String get stepShorebirdRelease => 'Shorebird release';

  @override
  String get stepShorebirdPatch => 'Shorebird patch';

  @override
  String get stepSymbols => 'Archive symbols';

  @override
  String get stepTest => 'Tests';

  @override
  String get stepAnalyze => 'Analyze';

  @override
  String get stepUploadAppStore => 'Upload to App Store';

  @override
  String get stepUploadPlay => 'Upload to Google Play';

  @override
  String get stepUploadFirebase => 'Upload to Firebase';

  @override
  String get stepGitTag => 'Tag';

  @override
  String get stepGitPush => 'Push';

  @override
  String get stepReleaseBranch => 'Cut the release branch';

  @override
  String get stepCreatePr => 'Open the release PR';

  @override
  String get stepMergePr => 'Merge the release PR';

  @override
  String get stepManifest => 'Record the manifest';

  @override
  String get stepGate => 'Approval';

  @override
  String get stepCommand => 'Command';

  @override
  String get gateProdRelease => 'production release';

  @override
  String get gateProdPatch => 'production patch';

  @override
  String get gateStoreSubmission => 'store submission';

  @override
  String get gatePush => 'push';

  @override
  String get gateMerge => 'merge';

  @override
  String get gateDelete => 'delete';

  @override
  String get jobTitle => 'Job';

  @override
  String get jobEngine => 'Engine';

  @override
  String jobStage(int number) {
    return 'Stage $number';
  }

  @override
  String jobStep(int number) {
    return 'Step $number';
  }

  @override
  String get jobNeedsYou => 'needs you';

  @override
  String jobRunningCount(int count) {
    return '$count running';
  }

  @override
  String get jobRestart => 'Restart job';

  @override
  String jobResumeFrom(String step) {
    return 'Resume from $step';
  }

  @override
  String get jobCancel => 'Cancel';

  @override
  String jobFailedAt(String step) {
    return 'Failed at $step';
  }

  @override
  String jobElapsed(String duration, String time) {
    return 'elapsed $duration · started $time';
  }

  @override
  String jobRan(String duration, String time) {
    return 'ran $duration · started $time';
  }

  @override
  String jobArtifacts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count artifacts',
      one: '1 artifact',
    );
    return '$_temp0';
  }

  @override
  String get jobArtifactsLabel => 'Artifacts';

  @override
  String jobStepsOf(String job, String runner) {
    return '$job · $runner · steps';
  }

  @override
  String get jobResumePlan => 'Resume plan';

  @override
  String jobResumeKept(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'First $count steps',
      one: 'First step',
    );
    return '$_temp0';
  }

  @override
  String get jobAlreadyDone => 'already done';

  @override
  String jobResumeRuns(String step) {
    return '$step and after';
  }

  @override
  String get jobInterruptedBody =>
      'The engine stopped while this job ran. Finished steps are kept; resume runs the interrupted step again from its start.';

  @override
  String jobWaitingForResumeBody(String step) {
    return 'The engine stopped during $step, which changes something outside the engine, so it never runs again by itself. Check, then resume.';
  }

  @override
  String jobWaitReason(String reason) {
    return 'Waiting: $reason';
  }

  @override
  String get jobNothingChanged => 'Nothing outside the engine was changed.';

  @override
  String cancelRunTitle(String run) {
    return 'Cancel $run?';
  }

  @override
  String cancelRunStops(String job, String runner, String duration) {
    return '$job stops now on $runner ($duration in). Its partial output is discarded.';
  }

  @override
  String cancelRunKept(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'The $count finished jobs keep their artifacts; Resume can reuse them.',
      one: 'The finished job keeps its artifacts; Resume can reuse them.',
    );
    return '$_temp0';
  }

  @override
  String cancelRunNeverStarts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count jobs that have not started will not run.',
      one: '1 job that has not started will not run.',
    );
    return '$_temp0';
  }

  @override
  String get cancelRunKeep => 'Keep running';

  @override
  String get cancelRunConfirm => 'Cancel run';

  @override
  String get logEmpty => 'No output yet';

  @override
  String get logFilter => 'Filter log';

  @override
  String get logJumpToError => 'Jump to error';

  @override
  String get logWrap => 'Wrap lines';

  @override
  String get logTimestamps => 'Timestamps';

  @override
  String get logFollow => 'Follow';

  @override
  String logLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lines',
      one: '1 line',
    );
    return '$_temp0';
  }

  @override
  String get dispatchTitle => 'Dispatch';

  @override
  String get dispatchWorkflow => 'Workflow';

  @override
  String get dispatchNoWorkflows => 'The project has no workflow.';

  @override
  String get dispatchBuiltin => 'built-in';

  @override
  String get dispatchGated => 'gated';

  @override
  String get dispatchApp => 'App';

  @override
  String get dispatchFlavors => 'Flavors';

  @override
  String get dispatchPlatforms => 'Platforms';

  @override
  String get dispatchRef => 'Ref';

  @override
  String get dispatchBranch => 'Branch';

  @override
  String get dispatchTag => 'Tag';

  @override
  String get dispatchVersion => 'Version';

  @override
  String get bumpKeep => 'Keep';

  @override
  String get bumpPatch => 'Patch';

  @override
  String get bumpMinor => 'Minor';

  @override
  String get bumpMajor => 'Major';

  @override
  String dispatchFromPubspec(String version) {
    return 'from $version in the pubspec of the commit';
  }

  @override
  String get dispatchVersionHint => 'or x.y.z';

  @override
  String get dispatchInputs => 'Inputs';

  @override
  String get dispatchYes => 'Yes';

  @override
  String get dispatchNo => 'No';

  @override
  String get dispatchJsonInvalid => 'Not valid JSON.';

  @override
  String get dispatchNoReleases =>
      'No releases yet: this workflow needs a release that reached a store.';

  @override
  String dispatchRelease(String version, String flavor) {
    return '$version · $flavor';
  }

  @override
  String dispatchWillRun(int jobs, int stages) {
    String _temp0 = intl.Intl.pluralLogic(
      jobs,
      locale: localeName,
      other: '$jobs jobs',
      one: '1 job',
    );
    String _temp1 = intl.Intl.pluralLogic(
      stages,
      locale: localeName,
      other: '$stages stages',
      one: '1 stage',
    );
    return 'Will run · $_temp0 in $_temp1';
  }

  @override
  String get dispatchNothing =>
      'Nothing would run for these flavors and platforms.';

  @override
  String dispatchOnEngine(int count, String engine) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count jobs',
      one: '1 job',
    );
    return '$_temp0 on $engine';
  }

  @override
  String dispatchOnRunner(String engine, String runner) {
    return '$engine first, else $runner';
  }

  @override
  String dispatchSkipped(String reason) {
    return 'skipped, $reason';
  }

  @override
  String dispatchBlocked(String reason) {
    return 'cannot run: $reason';
  }

  @override
  String dispatchBuildNumber(int build) {
    return 'build $build';
  }

  @override
  String dispatchGateTitle(String stage) {
    return '$stage approval';
  }

  @override
  String dispatchGates(String gates) {
    return 'waits for your approval: $gates';
  }

  @override
  String get dispatchReturnHint => 'Return does not dispatch';

  @override
  String get dispatchCancel => 'Cancel';

  @override
  String dispatchButton(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dispatch $count jobs',
      one: 'Dispatch 1 job',
    );
    return '$_temp0';
  }

  @override
  String get overviewAll => 'All';

  @override
  String get overviewQuiet => 'Nothing running · nothing needs you';

  @override
  String overviewNeedsYou(int count) {
    return '$count needs you';
  }

  @override
  String get overviewDispatch => 'Dispatch…';

  @override
  String get overviewOpenJob => 'Open job';

  @override
  String overviewStarted(String time) {
    return 'started $time';
  }

  @override
  String overviewInStores(String version) {
    return 'In the stores · $version';
  }

  @override
  String get overviewNoRelease => 'No release yet';

  @override
  String get overviewLiveBoth => 'Live on both stores';

  @override
  String overviewLiveIn(String store) {
    return 'Live on $store';
  }

  @override
  String get overviewNothingInFlight => 'No release in flight';

  @override
  String get overviewScan => 'Scan';

  @override
  String get overviewScanTitle => 'Scan';

  @override
  String get overviewClose => 'Close';

  @override
  String get ledgerFlavor => 'Flavor';

  @override
  String ledgerLocal(String branch) {
    return 'Local · $branch';
  }

  @override
  String get ledgerTesting => 'Testing';

  @override
  String ledgerLive(String store) {
    return 'Live · $store';
  }

  @override
  String get ledgerCredentials => 'Credentials';

  @override
  String get ledgerPubspec => 'pubspec';

  @override
  String get ledgerNoVersion => 'No version';

  @override
  String get ledgerNoRelease => '—';

  @override
  String get ledgerNoReleaseHint => 'no release yet';

  @override
  String get ledgerUpToDate => 'Up to date';

  @override
  String get ledgerNothingNewer => 'Nothing newer than live';

  @override
  String get ledgerNotUploaded => 'Not uploaded';

  @override
  String ledgerWaitsFor(String version) {
    return '$version building';
  }

  @override
  String get ledgerNotOnStore => 'Not on store';

  @override
  String get ledgerNoLiveRelease => 'no live release';

  @override
  String get ledgerNotProd => 'not a production flavor';

  @override
  String get ledgerCredentialsNone => 'None';

  @override
  String get ledgerCredentialsAssign => 'Assign…';

  @override
  String get ledgerCredentialsManage => 'Manage the credentials of this flavor';

  @override
  String get ledgerNoFlavors => 'No flavor to show.';

  @override
  String get consoleTitle => 'Console';

  @override
  String consoleLast(String job) {
    return '· last: $job';
  }

  @override
  String get sidebarOverview => 'Overview';

  @override
  String get sidebarReleases => 'Releases';

  @override
  String get sidebarApprovals => 'Approvals';

  @override
  String get overviewOpenRelease => 'Open release';

  @override
  String get needsYou => 'Needs you';

  @override
  String needsYouMeta(String sha, String left) {
    return '$sha · expires in $left';
  }

  @override
  String needsYouMore(int count) {
    return '+$count more';
  }

  @override
  String get approvalPending => 'Pending';

  @override
  String get approvalApproved => 'Approved';

  @override
  String get approvalDenied => 'Denied';

  @override
  String get approvalExpired => 'Expired';

  @override
  String approvalTitleRelease(String version) {
    return 'Release $version to the stores';
  }

  @override
  String approvalTitlePatch(String version) {
    return 'Patch $version';
  }

  @override
  String approvalTitleSubmit(String version) {
    return 'Submit $version to the stores';
  }

  @override
  String approvalTitlePush(String version) {
    return 'Push $version to GitHub';
  }

  @override
  String approvalTitleMerge(String version) {
    return 'Merge the release PR of $version';
  }

  @override
  String approvalTitleOther(String action, String version) {
    return 'Approve the $action of $version';
  }

  @override
  String approvalTitleBare(String action) {
    return 'Approve the $action';
  }

  @override
  String get approvalIfYouApprove => 'If you approve';

  @override
  String approvalIfRelease(String version, String sha) {
    return 'XPath builds $version from $sha and releases it to the stores.';
  }

  @override
  String approvalIfPatch(String version, String sha) {
    return 'XPath publishes a Shorebird patch of $version built from $sha.';
  }

  @override
  String approvalIfSubmit(String version, String sha) {
    return 'XPath uploads the builds made from $sha and submits $version for store review.';
  }

  @override
  String approvalIfPush(String version, String sha) {
    return 'XPath pushes the release commit $sha and the tag of $version to GitHub.';
  }

  @override
  String approvalIfMerge(String version, String branch) {
    return 'XPath merges the release pull request of $version into $branch with a merge commit.';
  }

  @override
  String approvalIfDelete(String sha) {
    return 'XPath deletes what the job asks to delete, on $sha.';
  }

  @override
  String approvalIfOther(String action) {
    return 'The job goes on with its $action.';
  }

  @override
  String approvalIfTarget(String target) {
    return 'It goes out as $target.';
  }

  @override
  String get approvalVoid =>
      'If the commit, version or flavor change before then, this approval is void.';

  @override
  String get approvalBaseBranch => 'the base branch';

  @override
  String approvalExpiresIn(String left, String asked) {
    return 'expires in $left · $asked';
  }

  @override
  String approvalExpiresShort(String left) {
    return 'expires in $left';
  }

  @override
  String approvalExpiredAt(String at) {
    return 'expired $at';
  }

  @override
  String approvalDecidedBy(String who, String at) {
    return 'by $who · $at';
  }

  @override
  String get approvalSomeone => 'another device';

  @override
  String approvalAskedAt(String time) {
    return 'asked at $time';
  }

  @override
  String get approvalProject => 'Project';

  @override
  String get approvalFlavor => 'Flavor';

  @override
  String get approvalVersion => 'Version';

  @override
  String get approvalCommit => 'Commit';

  @override
  String get approvalJob => 'Job';

  @override
  String get approvalGate => 'Gate';

  @override
  String get approvalReason => 'Reason';

  @override
  String approvalGateName(String action) {
    return 'Project gate “$action”';
  }

  @override
  String approvalWaits(String step) {
    return '$step waits for this';
  }

  @override
  String get approvalReview => 'Review…';

  @override
  String get approvalApprove => 'Approve';

  @override
  String get approvalApproveEllipsis => 'Approve…';

  @override
  String get approvalDenyEllipsis => 'Deny…';

  @override
  String get approvalDeny => 'Deny';

  @override
  String get approvalBack => 'Back';

  @override
  String get approvalCancel => 'Cancel';

  @override
  String get approvalClose => 'Close';

  @override
  String get approvalDenyReason => 'Reason (optional)';

  @override
  String get approvalDenyReasonHint => 'Why, for the record';

  @override
  String get approvalReturnHint => 'Return never approves. ⌘↩ approves.';

  @override
  String get approvalArming => 'Approve arms in a moment';

  @override
  String approvalDecidedElsewhere(String state, String who) {
    return 'Already $state by $who. The first decision counts; nothing to do here.';
  }

  @override
  String get approvalExpiredElsewhere =>
      'This approval expired: it counts as denied. Dispatch again to ask anew.';

  @override
  String get approvalGone => 'This approval cannot be read on this engine.';

  @override
  String get approvalsTitle => 'Approvals';

  @override
  String approvalsSubtitle(String engine, int count) {
    return '$engine · $count pending';
  }

  @override
  String get approvalsPending => 'Pending';

  @override
  String get approvalsDecided => 'Decided';

  @override
  String get approvalsExpired => 'Expired';

  @override
  String get approvalsNothingWaits => 'Nothing is waiting';

  @override
  String get approvalsNone => 'Nothing here';

  @override
  String notificationBody(String where, String left) {
    return '$where · expires in $left';
  }

  @override
  String get notificationLater => 'Later';

  @override
  String menuBarTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'XPath: $count need you',
      one: 'XPath: 1 needs you',
    );
    return '$_temp0';
  }

  @override
  String menuBarNeedsYou(int count) {
    return 'Needs you · $count';
  }

  @override
  String get menuBarNothing => 'Nothing needs you';

  @override
  String menuBarReview(String title) {
    return 'Review: $title…';
  }

  @override
  String menuBarLeft(String where, String left) {
    return '$where · $left left';
  }

  @override
  String get menuBarOpen => 'Open XPath';

  @override
  String get releasesTitle => 'Releases';

  @override
  String get releasesEmpty =>
      'A production release dispatched from the overview shows up here.';

  @override
  String get releasesDispatchProd => 'Dispatch Prod release…';

  @override
  String releaseTitle(String version) {
    return 'Release $version';
  }

  @override
  String get releaseRefresh => 'Refresh';

  @override
  String get releaseRefreshHint =>
      'Ask the stores now instead of waiting up to ten minutes';

  @override
  String releaseRejectedBy(String store) {
    return 'Rejected by $store';
  }

  @override
  String get releaseRejectedByBoth => 'Rejected by both stores';

  @override
  String get lanesTitle => 'Store lanes';

  @override
  String get storeApproved => 'Approved';

  @override
  String get storeUnknown => 'Unknown';

  @override
  String get storeWaitingForReview => 'Waiting for review';

  @override
  String get storesBoth => 'App Store and Google Play';

  @override
  String get listAnd => ' and ';

  @override
  String laneSince(String time) {
    return 'since $time';
  }

  @override
  String get laneNoApiKey => 'no API key';

  @override
  String get laneNoServiceAccount => 'no service account';

  @override
  String laneNotTargeted(String store) {
    return 'This release does not go to $store.';
  }

  @override
  String get laneNewBuild => 'New build, same version…';

  @override
  String laneNewBuildCaption(String version) {
    return '$version → a new build number';
  }

  @override
  String laneReplacedToo(String build) {
    return 'A new build replaces $build here too, so both stores ship the same build.';
  }

  @override
  String get laneMarkApproved => 'Mark approved';

  @override
  String get laneMarkLive => 'Mark live';

  @override
  String laneMarkTitle(String version, String state) {
    return 'Mark $version $state?';
  }

  @override
  String get laneMarkManual =>
      'The engine cannot read this store, so it records your mark as manual, at this time.';

  @override
  String get laneMarkFinal =>
      'The release moves on from it; a mark cannot be taken back.';

  @override
  String get laneAddApiKey => 'Add API key…';

  @override
  String get laneAddServiceAccount => 'Add service account…';

  @override
  String get laneManualApple =>
      'No App Store Connect API key for this flavor: the engine cannot read the review, and each mark is recorded as manual';

  @override
  String get laneManualPlay =>
      'No Google Play service account for this flavor: the engine cannot read the review, and each mark is recorded as manual';

  @override
  String laneLiveNow(String version) {
    return 'Live now $version';
  }

  @override
  String laneReplaced(String version) {
    return 'Replaced $version';
  }

  @override
  String newBuildTitle(String version) {
    return 'Build $version again?';
  }

  @override
  String newBuildBody(String build) {
    return 'The production workflow runs again on the release branch with the same version and the next free build number; $build is never reused. It asks for your approval like any release.';
  }

  @override
  String get newBuildConfirm => 'Start new build';

  @override
  String mergeInto(String branch) {
    return 'Merge into $branch';
  }

  @override
  String get mergeReady => 'Both stores live';

  @override
  String mergeReadyBranch(String branch, String base) {
    return '$branch → $base · both stores live';
  }

  @override
  String mergeDone(String sha) {
    return 'Merged · $sha';
  }

  @override
  String get mergeAbandoned => 'The release was abandoned';

  @override
  String get mergeRequested => 'Merge requested';

  @override
  String get mergeWaitsApproval => 'Merge requested · waits for your approval';

  @override
  String mergeRejected(String stores) {
    return '$stores rejected this build';
  }

  @override
  String get mergeNoPr => 'The release has no pull request yet';

  @override
  String get mergeWaitsBoth => 'Waits for both stores to go live';

  @override
  String mergeWaitsStore(String store) {
    return 'Waits for $store to go live';
  }

  @override
  String mergeMark(String store) {
    return 'Mark $store live';
  }

  @override
  String mergeMust(String store) {
    return '$store must go live';
  }

  @override
  String get timelineTitle => 'Timeline';

  @override
  String get timelineNewestFirst => 'newest first';

  @override
  String get timelineDispatched => 'Release dispatched';

  @override
  String timelineBuild(String build) {
    return 'Build $build started';
  }

  @override
  String timelineStore(String store, String state) {
    return '$store: $state';
  }

  @override
  String timelineApprovalAsked(String title) {
    return 'Approval requested: $title';
  }

  @override
  String timelineApprovalSettled(String title, String state) {
    return '$title: $state';
  }

  @override
  String timelineMerged(String branch) {
    return 'Merged into $branch';
  }

  @override
  String get sourceUpload => 'Upload step';

  @override
  String get sourceAppStoreConnect => 'App Store Connect API';

  @override
  String get sourcePlayApi => 'Google Play API';

  @override
  String get sourceLookup => 'iTunes lookup';

  @override
  String get sourceManual => 'Marked by hand';

  @override
  String get notesTitle => 'Release notes';

  @override
  String notesCommits(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count commits',
      one: '1 commit',
    );
    return '$_temp0';
  }

  @override
  String notesSince(String tag, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count commits',
      one: '1 commit',
    );
    return 'since $tag · $_temp0';
  }

  @override
  String get notesUntagged => 'The notes are ready once the release is tagged.';

  @override
  String get notesNothing => 'Nothing changed since the release before.';

  @override
  String get notesCopySlack => 'Copy for Slack';

  @override
  String get notesCopyWhatsApp => 'Copy for WhatsApp';

  @override
  String get copied => 'Copied';

  @override
  String get confirmKeep => 'Keep';

  @override
  String get confirmRemove => 'Remove';

  @override
  String copyHint(String text) {
    return '$text · click to copy';
  }

  @override
  String get minVersionTitle => 'Forced update';

  @override
  String get minVersionReminder => 'Reminder';

  @override
  String minVersionLater(String variables, String version) {
    return 'If this release is a forced update, raise $variables to $version once the stores have it live. Raising it earlier locks out users who have nothing to update to.';
  }

  @override
  String minVersionNow(String stores, String variables, String version) {
    return '$stores live: if this release is a forced update, raise $variables to $version in Firebase Remote Config now.';
  }

  @override
  String minVersionRest(String variables, String stores) {
    return 'Raise $variables once $stores is live.';
  }

  @override
  String minVersionBanner(String variables, String version) {
    return 'If this release is a forced update, raise $variables to $version: every store has it live.';
  }

  @override
  String get minVersionNoStores => 'This release goes to no store.';

  @override
  String get prTitle => 'Release PR';

  @override
  String get prNone =>
      'No pull request yet: the release opens one once it is tagged.';

  @override
  String prTagged(String tag) {
    return 'Merging adds no tag: $tag was tagged when the build was recorded.';
  }

  @override
  String get prUntagged => 'The release is tagged when its build is recorded.';

  @override
  String prMerged(String sha) {
    return 'Merged with a merge commit · $sha';
  }

  @override
  String get prCopyLink => 'Copy link';

  @override
  String get prOpenMergeJob => 'Open merge job';

  @override
  String get sidebarTests => 'Tests';

  @override
  String get sidebarRunners => 'Runners';

  @override
  String sidebarRunnersBusy(int count) {
    return '$count busy';
  }

  @override
  String get sidebarStorage => 'Storage';

  @override
  String sidebarStorageFreeable(String size) {
    return '$size free-able';
  }

  @override
  String get jobTestResults => 'Test results';

  @override
  String get timeJustNow => 'just now';

  @override
  String timeAgo(String duration) {
    return '$duration ago';
  }

  @override
  String timeYesterday(String time) {
    return 'Yesterday $time';
  }

  @override
  String get testsTitle => 'Tests';

  @override
  String get testsRunThisSession => 'just ended';

  @override
  String get testsBaselineTag => 'baseline';

  @override
  String get testsEmptyTitle => 'No test runs yet';

  @override
  String get testsEmptyBody =>
      'Run the Tests workflow. Its runs on the base branch become the baseline that later runs are compared with; a run\'s results also open from its job.';

  @override
  String get testsRun => 'Run Tests…';

  @override
  String testsIsBaseline(String branch) {
    return 'This run is the baseline of $branch';
  }

  @override
  String get testsNoBaseline =>
      'No baseline yet, so every failure counts as new';

  @override
  String testsComparedToJob(String job) {
    return 'Compared with the baseline run of $job';
  }

  @override
  String testsComparedTo(String branch, String when) {
    return 'Compared with the baseline of $branch from $when';
  }

  @override
  String get testsNoNewFailures => 'No new failures';

  @override
  String testsNewFailures(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new failures',
      one: '1 new failure',
    );
    return '$_temp0';
  }

  @override
  String get testsStatNew => 'new failures';

  @override
  String get testsStatInBaseline => 'in baseline';

  @override
  String get testsStatFixed => 'fixed';

  @override
  String get testsStatPassed => 'passed';

  @override
  String get testsStatFailed => 'failed';

  @override
  String get testsStatErrored => 'errored';

  @override
  String get testsStatSkipped => 'skipped';

  @override
  String get testsStatMissing => 'missing';

  @override
  String get testsFailed => 'Failed';

  @override
  String get testsErrored => 'Errored';

  @override
  String get testsFixed => 'Fixed';

  @override
  String get testsMissing => 'Not reported';

  @override
  String get testsNewFailuresTitle => 'New failures';

  @override
  String get testsStillFailingTitle => 'Failing in the baseline too';

  @override
  String get testsFixedTitle => 'Fixed since the baseline';

  @override
  String get testsMissingTitle => 'In the baseline, not in this run';

  @override
  String testsTruncated(String shown, String total) {
    return 'Showing $shown of $total failing tests.';
  }

  @override
  String get testsAllPassed =>
      'Every test passed and nothing changed against the baseline.';

  @override
  String get testsBaselinesTitle => 'Baselines';

  @override
  String get testsColumnApp => 'App';

  @override
  String get testsColumnBranch => 'Branch';

  @override
  String get testsColumnWhen => 'When';

  @override
  String get testsShowRun => 'Show';

  @override
  String get runnersTitle => 'Runners';

  @override
  String runnersSubtitle(int count, int busy) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count runners',
      one: '1 runner',
    );
    return '$_temp0 · $busy busy';
  }

  @override
  String get runnersPair => 'Pair runner…';

  @override
  String get runnersEmptyTitle => 'No runners yet';

  @override
  String get runnersEmptyBody =>
      'Pair a Mac or a Linux machine and the engine sends it the jobs that fit its capabilities.';

  @override
  String get runnersColumnRunner => 'Runner';

  @override
  String get runnersColumnStatus => 'Status';

  @override
  String get runnersColumnCapabilities => 'Capabilities';

  @override
  String get runnersColumnSlots => 'Slots';

  @override
  String get runnersColumnJobs => 'Jobs';

  @override
  String get runnersColumnLastHeard => 'Last heard';

  @override
  String get runnersRevokedTitle => 'Revoked';

  @override
  String get runnerIdle => 'Online · idle';

  @override
  String runnerBusy(int used, int slots) {
    return 'Online · busy $used/$slots';
  }

  @override
  String get runnerDraining => 'Draining';

  @override
  String get runnerLost => 'Lost mid-job';

  @override
  String get runnerOffline => 'Offline';

  @override
  String get runnerRevoked => 'Revoked';

  @override
  String runnerRevokedAt(String when) {
    return 'Revoked $when';
  }

  @override
  String runnerCores(int count) {
    return '$count cores';
  }

  @override
  String get runnerNotProbed => 'Not probed yet';

  @override
  String runnerMissingCapability(String capability, String explanation) {
    return 'No $capability: $explanation';
  }

  @override
  String get runnerNeverHeard => 'Never';

  @override
  String get runnerRevoke => 'Revoke…';

  @override
  String revokeRunnerTitle(String name) {
    return 'Revoke $name?';
  }

  @override
  String get revokeRunnerCredential =>
      'Its credential stops working and its connection closes.';

  @override
  String revokeRunnerJobs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'The $count jobs it holds are queued again, or wait for a resume if they had a step with side effects.',
      one: 'The job it holds is queued again, or waits for a resume if it had a step with side effects.',
    );
    return '$_temp0';
  }

  @override
  String revokeRunnerName(String name) {
    return 'The name $name stays taken: pair the machine again under a new name.';
  }

  @override
  String get revokeRunnerKeep => 'Keep';

  @override
  String get revokeRunnerConfirm => 'Revoke';

  @override
  String get pairRunnerTitle => 'Pair a runner';

  @override
  String get pairRunnerBody =>
      'XPath makes a pairing token for the name. It works once, for 15 minutes, and is shown only now.';

  @override
  String get pairRunnerName => 'Name';

  @override
  String get pairRunnerCreate => 'Create pairing token';

  @override
  String get pairRunnerCancel => 'Cancel';

  @override
  String get pairRunnerDone => 'Done';

  @override
  String pairRunnerToken(String name) {
    return 'Pairing token for $name';
  }

  @override
  String get pairRunnerCopyToken => 'Copy token';

  @override
  String get pairRunnerCommand => 'On the runner, run';

  @override
  String get pairRunnerCopyCommand => 'Copy command';

  @override
  String pairRunnerExpires(String left, String at) {
    return 'Works once; expires in $left ($at).';
  }

  @override
  String get pairRunnerExpired => 'Expired before it was used.';

  @override
  String get pairRunnerNewToken => 'New token';

  @override
  String get pairRunnerLoopback =>
      'This address only works on this Mac. Set the address runners reach the engine at; pairing commands carry it.';

  @override
  String get storageTitle => 'Storage';

  @override
  String storageChecked(String when) {
    return 'Measured $when';
  }

  @override
  String get storageRefresh => 'Measure again';

  @override
  String get storageFreeUp => 'Free up space…';

  @override
  String storageHero(String reclaimable, String used) {
    return '$reclaimable of $used reclaimable';
  }

  @override
  String get storageHeroBody =>
      'Pinned artifacts, releases not over yet and the newest builds of each flavor are always kept.';

  @override
  String storageFreed(String size) {
    return 'Freed $size';
  }

  @override
  String storageFreedPart(String category, int count) {
    return '$category $count';
  }

  @override
  String get storageCategoriesTitle => 'What the engine keeps';

  @override
  String get storageFlavorsTitle => 'Artifacts by app and flavor';

  @override
  String get storageColumnCategory => 'Category';

  @override
  String get storageColumnItems => 'Items';

  @override
  String get storageColumnUsed => 'Used';

  @override
  String get storageColumnReclaimable => 'Reclaimable';

  @override
  String get storageColumnProject => 'Project';

  @override
  String get storageColumnApp => 'App';

  @override
  String get storageColumnFlavor => 'Flavor';

  @override
  String get storageColumnBuilds => 'Builds';

  @override
  String storageBuilds(int builds, int artifacts) {
    String _temp0 = intl.Intl.pluralLogic(
      builds,
      locale: localeName,
      other: '$builds builds',
      one: '1 build',
    );
    return '$_temp0 · $artifacts files';
  }

  @override
  String get storageArtifacts => 'Artifacts';

  @override
  String get storageLogs => 'Logs';

  @override
  String get storageWorktrees => 'Worktrees';

  @override
  String get storageMirrors => 'Mirrors';

  @override
  String get storageFlutter => 'Flutter SDKs';

  @override
  String storageArtifactsRule(int keep) {
    return 'Builds past the newest $keep of each flavor';
  }

  @override
  String storageLogsRule(int days) {
    return 'Logs of jobs older than $days days';
  }

  @override
  String get storageWorktreesRule => 'Worktrees of finished jobs';

  @override
  String get storageMirrorsRule =>
      'Mirrors of repositories that are no longer projects';

  @override
  String get storageFlutterRule =>
      'SDKs in XPath\'s cache that no project pins';

  @override
  String get storageRetentionTitle => 'Retention';

  @override
  String get storageRetentionBody =>
      'Logs past their days go every night; artifacts only with Free up space.';

  @override
  String get storageKeepPerFlavor => 'Builds kept per flavor';

  @override
  String get storageLogDays => 'Days of logs';

  @override
  String get storageSaveRetention => 'Save';

  @override
  String get storageRetentionInvalid =>
      'Both need a whole number of at least 1.';

  @override
  String get freeSpaceTitle => 'Free up space';

  @override
  String get freeSpaceBody =>
      'XPath deletes what retention gives back in the categories you pick. It cannot be undone.';

  @override
  String get freeSpaceKeep => 'Keep everything';

  @override
  String freeSpaceConfirm(String size) {
    return 'Free $size';
  }

  @override
  String get sidebarWorkflows => 'Workflows';

  @override
  String get workflowsTitle => 'Workflows';

  @override
  String workflowsVersion(int version) {
    return 'Version $version';
  }

  @override
  String get workflowsBuiltin => 'Built-in';

  @override
  String get workflowsDraft => 'Not saved yet';

  @override
  String get workflowsUnsaved => 'Unsaved changes';

  @override
  String get workflowsPick => 'Workflow';

  @override
  String get workflowsNew => 'New';

  @override
  String get workflowsImport => 'Import…';

  @override
  String get workflowsRun => 'Run…';

  @override
  String get workflowsExport => 'Export…';

  @override
  String get workflowsSave => 'Save';

  @override
  String get workflowsSaveAs => 'Save as…';

  @override
  String get workflowsBuiltinHint =>
      'Built-in workflows cannot be changed. Save as… keeps your edits as a workflow of your own.';

  @override
  String workflowsSaved(String name, int version) {
    return 'Saved $name, version $version.';
  }

  @override
  String workflowsExported(String path) {
    return 'Exported to $path.';
  }

  @override
  String get workflowsPipeline => 'Pipeline';

  @override
  String get workflowsYaml => 'YAML';

  @override
  String get workflowsIssuesLabel => 'Issues';

  @override
  String get workflowsChecking => 'Checking…';

  @override
  String get workflowsValid => 'Valid';

  @override
  String workflowsIssues(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count issues',
      one: '1 issue',
    );
    return '$_temp0';
  }

  @override
  String get workflowsUnchecked => 'Not checked · engine away';

  @override
  String get workflowsShapeLocked =>
      'The visual editor waits until the YAML reads as a workflow. Fix the issues in the YAML.';

  @override
  String get workflowsAddStage => 'Add stage';

  @override
  String workflowsNewStage(int number) {
    return 'stage-$number';
  }

  @override
  String get workflowsAddJob => 'Add job';

  @override
  String get workflowsWorkflow => 'Workflow';

  @override
  String workflowsSteps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count steps',
      one: '1 step',
      zero: 'No steps',
    );
    return '$_temp0';
  }

  @override
  String get workflowsName => 'Name';

  @override
  String get workflowsDescription => 'Description';

  @override
  String get workflowsLock => 'One run at a time per project';

  @override
  String get workflowsLockHint =>
      'It also makes the production flavors the default when a dispatch names none.';

  @override
  String get workflowsInputs => 'Inputs';

  @override
  String get workflowsInputsHint =>
      'A dispatch sets them; the steps read them as inputs.<name>.';

  @override
  String get workflowsNoInputs => 'No inputs';

  @override
  String workflowsStage(int number) {
    return 'Stage $number';
  }

  @override
  String get workflowsStageName => 'Stage name';

  @override
  String get workflowsMoveEarlier => 'Move earlier';

  @override
  String get workflowsMoveLater => 'Move later';

  @override
  String get workflowsRemoveStage => 'Remove stage';

  @override
  String get workflowsRemoveJob => 'Remove job';

  @override
  String get workflowsRemoveStep => 'Remove step';

  @override
  String get workflowsJob => 'Job';

  @override
  String get workflowsJobId => 'Job id';

  @override
  String get workflowsJobName => 'Job name';

  @override
  String get workflowsJobNameHint => 'The id with the matrix values by default';

  @override
  String get workflowsCondition => 'If';

  @override
  String get workflowsConditionHint => 'platform == \'ios\'';

  @override
  String get workflowsMatrix => 'Matrix';

  @override
  String get workflowsAxisNone => 'None';

  @override
  String get workflowsAxisDispatch => 'From dispatch';

  @override
  String get workflowsAxisList => 'Listed';

  @override
  String get workflowsAxisValuesHint => 'prod, dev';

  @override
  String get workflowsCapabilities => 'Capabilities';

  @override
  String get workflowsStepsLabel => 'Steps';

  @override
  String get workflowsAddStep => 'Add step';

  @override
  String get workflowsStepKind => 'Step type';

  @override
  String get workflowsGate => 'Gate';

  @override
  String get workflowsNoGate => 'No gate';

  @override
  String get workflowsWith => 'With';

  @override
  String get workflowsWithHint => 'YAML value';

  @override
  String get toastDismiss => 'Dismiss';

  @override
  String get toastUndo => 'Undo';

  @override
  String workflowsRemovedStage(String name) {
    return 'Removed stage $name';
  }

  @override
  String workflowsRemovedJob(String id) {
    return 'Removed job $id';
  }

  @override
  String workflowsRemovedStep(String kind) {
    return 'Removed step $kind';
  }

  @override
  String get workflowsAddInput => 'Add input';

  @override
  String get workflowsRemoveInput => 'Remove input';

  @override
  String workflowsRemovedInput(String name) {
    return 'Removed input $name';
  }

  @override
  String get workflowsInputName => 'Name';

  @override
  String get workflowsInputNameInvalid =>
      'Letters, digits and _, starting with a letter or _.';

  @override
  String get workflowsInputType => 'Type';

  @override
  String get workflowsInputTypeAny => 'Any';

  @override
  String get workflowsInputTypeString => 'Text';

  @override
  String get workflowsInputTypeBoolean => 'On or off';

  @override
  String get workflowsInputTypeChoice => 'Choice';

  @override
  String get workflowsInputTypeJson => 'JSON';

  @override
  String get workflowsInputTypeRelease => 'Release';

  @override
  String get workflowsInputRequired => 'Required';

  @override
  String get workflowsInputDescription => 'Description';

  @override
  String get workflowsInputOptions => 'Options';

  @override
  String get workflowsInputOptionsHint => 'internal, beta, production';

  @override
  String get workflowsInputDefault => 'Default';

  @override
  String get workflowsInputNoDefault => 'None';

  @override
  String get workflowsMore => 'More';

  @override
  String get workflowsVersions => 'Versions…';

  @override
  String get workflowsRename => 'Rename…';

  @override
  String get workflowsRenameTitle => 'Rename the workflow';

  @override
  String get workflowsArchive => 'Archive';

  @override
  String get workflowsUnarchive => 'Unarchive';

  @override
  String workflowsArchivedToast(String name) {
    return 'Archived $name';
  }

  @override
  String get workflowsArchivedNote =>
      'Archived: kept with its versions and runs, and not offered to dispatch.';

  @override
  String workflowsArchivedName(String name) {
    return '$name (archived)';
  }

  @override
  String get workflowsDelete => 'Delete…';

  @override
  String workflowsDeleteTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get workflowsDeleteVersions => 'Its versions go with it.';

  @override
  String get workflowsDeleteRan =>
      'A workflow that ran cannot be deleted; archive it instead.';

  @override
  String get workflowsDeleteConfirm => 'Delete';

  @override
  String workflowsDeleted(String name) {
    return 'Deleted $name.';
  }

  @override
  String workflowsRestored(int from, int version, String name) {
    return 'Saved version $from again as version $version of $name.';
  }

  @override
  String workflowsVersionsTitle(String name) {
    return 'Versions of $name';
  }

  @override
  String workflowsVersionLabel(int version, String time) {
    return 'Version $version · $time';
  }

  @override
  String get workflowsVersionFrom => 'From';

  @override
  String get workflowsVersionTo => 'to';

  @override
  String workflowsRestoreVersion(int version) {
    return 'Restore version $version';
  }

  @override
  String get workflowsNoChanges => 'No changes.';

  @override
  String get workflowsClose => 'Close';

  @override
  String workflowsBuiltinUpdated(String builtin, int latest, int base) {
    return 'The built-in $builtin has a newer version ($latest); this copy is based on version $base.';
  }

  @override
  String get workflowsCompare => 'Compare';

  @override
  String workflowsCompareTitle(String builtin) {
    return 'Compare with $builtin';
  }

  @override
  String workflowsBuiltinChanged(String builtin, int base, int latest) {
    return 'What $builtin changed, version $base to $latest';
  }

  @override
  String workflowsYouChanged(int base) {
    return 'What this copy changed since version $base';
  }

  @override
  String get workflowsMarkUpToDate => 'Mark as up to date';

  @override
  String get workflowsTemplateTitle => 'Start a new workflow';

  @override
  String get workflowsUndo => 'Undo';

  @override
  String get workflowsRedo => 'Redo';

  @override
  String get workflowsAddStepUnavailable =>
      'The engine cannot be reached, so its step types are not known. Edit the YAML for now, or try again once it answers.';

  @override
  String get workflowsStepPickerTitle => 'Add a step';

  @override
  String get workflowsStepSearchHint => 'Search step types';

  @override
  String get workflowsStepNoMatch => 'No step type matches.';

  @override
  String get workflowsKeyNeeded => 'Needed';

  @override
  String get workflowsKeyDefault => 'Default';

  @override
  String workflowsKeyDefaultValue(String value) {
    return 'Default ($value)';
  }

  @override
  String get workflowsOn => 'On';

  @override
  String get workflowsOff => 'Off';

  @override
  String get workflowsSelectJob =>
      'Select a job in the pipeline to edit its matrix and steps.';

  @override
  String get workflowsNameTitle => 'Save as a new workflow';

  @override
  String get workflowsNameBody =>
      'Letters, digits, dots, dashes and underscores; unique in the project.';

  @override
  String get workflowsNameInvalid =>
      'Start with a letter or digit; then letters, digits, dots, dashes and underscores, 64 at most.';

  @override
  String workflowsNameTaken(String name) {
    return 'The project already has a workflow called $name.';
  }

  @override
  String get workflowsCancel => 'Cancel';

  @override
  String get workflowsDiscardTitle => 'Discard unsaved changes?';

  @override
  String workflowsDiscardBody(String name) {
    return 'The changes to $name are not saved.';
  }

  @override
  String get workflowsKeepEditing => 'Keep editing';

  @override
  String get workflowsDiscard => 'Discard';

  @override
  String get sidebarSettings => 'Settings';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSubtitle => 'XPath on this Mac and the engine it shows.';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsAppVersion => 'App';

  @override
  String get settingsEngine => 'Engine';

  @override
  String get settingsEngineVersion => 'Engine version';

  @override
  String settingsEngineVersionValue(String version, String api) {
    return '$version (API v$api)';
  }

  @override
  String get settingsConnection => 'Connection';

  @override
  String get settingsLoginItem => 'Engine on this Mac';

  @override
  String get settingsAgentEnabled => 'Runs at login';

  @override
  String get settingsAgentNotRegistered => 'Not running';

  @override
  String get settingsAgentRequiresApproval => 'Waiting for you in Login Items';

  @override
  String get settingsAgentNotFound => 'Not in this build';

  @override
  String get settingsAgentUnsupported => 'Needs macOS 13';

  @override
  String get settingsUnknown => 'Unknown';

  @override
  String get settingsRunners => 'Runners';

  @override
  String get settingsRunnerUrl => 'Runner URL';

  @override
  String get settingsRunnerUrlBody =>
      'The address runners on other machines reach this engine at, for example a Tailscale name. Every pairing command carries it.';

  @override
  String get settingsRunnerUrlUnset =>
      'No runner URL is set: pairing commands use the address this app reaches the engine at.';

  @override
  String settingsRunnerUrlSet(String url) {
    return 'Runners reach the engine at $url.';
  }

  @override
  String get settingsRunnerUrlNote =>
      'Runners paired already keep their address; pair them again to move them. See docs/guide/runners.md, Reaching the engine.';

  @override
  String get settingsRunnerUrlSave => 'Save';

  @override
  String get settingsRunnerUrlClear => 'Clear';

  @override
  String get settingsGitHub => 'GitHub';

  @override
  String get settingsGitHubBody =>
      'The engine adds projects, keeps its copies and pushes with one GitHub token, shared by every project. The token stays on the engine machine and is checked with GitHub before it is saved.';

  @override
  String get settingsGitHubMissing =>
      'The engine has no GitHub token, so it cannot add projects.';

  @override
  String settingsGitHubConnected(String login) {
    return 'Connected to GitHub as $login.';
  }

  @override
  String get settingsGitHubConnectedNoLogin => 'Connected to GitHub.';

  @override
  String settingsGitHubRejected(String message) {
    return 'GitHub refused the engine\'s token: $message';
  }

  @override
  String settingsGitHubUnreachable(String message) {
    return 'GitHub could not check the engine\'s token: $message';
  }

  @override
  String get settingsGitHubChecking => 'Asking GitHub…';

  @override
  String get settingsGitHubToken => 'Token';

  @override
  String get settingsGitHubTokenHint =>
      'ghp_… or github_pat_… with the repo scope';

  @override
  String get settingsGitHubSave => 'Check and save';

  @override
  String get settingsGitHubImport => 'Import from GitHub CLI';

  @override
  String get settingsGitHubImportNote =>
      'Import runs gh auth token on the engine machine; log in there with gh auth login first.';

  @override
  String get settingsGitHubRemove => 'Remove token';

  @override
  String get settingsGitHubRemoveTitle => 'Remove the GitHub token?';

  @override
  String get settingsGitHubRemoveStops =>
      'The engine can no longer clone, tag or open pull requests, so jobs that need GitHub fail.';

  @override
  String get settingsGitHubRemoveKeeps =>
      'The token stays valid on GitHub; revoke it there if it leaked.';

  @override
  String settingsGitHubFailed(String message) {
    return 'Not saved: $message';
  }

  @override
  String get settingsCli => 'Command line tool';

  @override
  String get settingsRemove => 'Remove XPath';

  @override
  String get settingsRemoveBody =>
      'Stops the engine on this Mac, revokes its runners and removes the xp link. Your repositories are never touched.';

  @override
  String get settingsRemoveButton => 'Remove XPath…';

  @override
  String get removeTitle => 'Remove XPath from this Mac?';

  @override
  String get removeBody =>
      'XPath revokes every runner of the engine on this Mac while it still runs, stops the engine and takes it off the login items, and removes the xp link it made. Your repositories are not touched.';

  @override
  String get removeDeleteData => 'Also delete engine data';

  @override
  String removeDeleteDataNote(String folders) {
    return 'The database, builds, logs and copies in $folders.';
  }

  @override
  String get removeDeleteKeychain => 'Also delete Keychain items';

  @override
  String get removeDeleteKeychainNote =>
      'The engine\'s secrets and credentials and the app\'s engine tokens (Keychain services ly.abdurahman.xpath…).';

  @override
  String get removeKeep => 'Keep XPath';

  @override
  String get removeConfirm => 'Remove XPath';

  @override
  String get removeStepRunners => 'Revoke runners';

  @override
  String get removeStepEngine => 'Stop the engine';

  @override
  String get removeStepCli => 'Remove the xp link';

  @override
  String get removeStepData => 'Delete engine data';

  @override
  String get removeStepKeychain => 'Delete Keychain items';

  @override
  String removeRunnersRevoked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count runners revoked',
      one: '1 runner revoked',
      zero: 'No runners to revoke',
    );
    return '$_temp0';
  }

  @override
  String removeKeychainDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items deleted',
      one: '1 item deleted',
      zero: 'No items',
    );
    return '$_temp0';
  }

  @override
  String get removeEngineStillRunning => 'The engine did not stop in time.';

  @override
  String get removeDataKept => 'Kept: the engine did not stop.';

  @override
  String get removeDoneTitle => 'XPath is removed from this Mac';

  @override
  String get removeDoneBody => 'Move XPath to the Trash to finish.';

  @override
  String get removeTrashAndQuit => 'Move to Trash and quit';

  @override
  String get removeTrashFailed =>
      'XPath could not move itself to the Trash. Quit, then drag XPath from Applications to the Trash.';

  @override
  String get removeQuit => 'Quit XPath';

  @override
  String get addProjectNoGitHub =>
      'The engine has no GitHub token, so it cannot add a project. Connect GitHub below first.';

  @override
  String get addProjectGitHubRejected =>
      'GitHub refuses the engine\'s token, so it cannot add a project. Save a new one below.';
}
