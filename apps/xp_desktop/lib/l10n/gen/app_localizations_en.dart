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
  String get jobRerunAll => 'Re-run all';

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
    return 'from $version in the pubspec at the last scan';
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
  String dispatchOnRunner(String engine, String runner, int slot, int slots) {
    return '$engine first, else $runner · slot $slot of $slots';
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
  String get ledgerNoFlavors => 'No flavor to show.';

  @override
  String get consoleTitle => 'Console';

  @override
  String consoleLast(String job) {
    return '· last: $job';
  }
}
