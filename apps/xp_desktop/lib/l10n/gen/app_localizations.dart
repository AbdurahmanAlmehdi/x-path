import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// The name of the app.
  ///
  /// In en, this message translates to:
  /// **'XPath'**
  String get appTitle;

  /// Engine status: the first check has not answered.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get statusConnecting;

  /// Engine status.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get statusConnected;

  /// Engine status.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting'**
  String get statusReconnecting;

  /// Engine status: the app shows cached data.
  ///
  /// In en, this message translates to:
  /// **'Unreachable · cached'**
  String get statusUnreachable;

  /// Engine status: the engine's Keychain is locked.
  ///
  /// In en, this message translates to:
  /// **'Secrets locked'**
  String get statusSecretsLocked;

  /// Engine status: the engine refuses this app's token.
  ///
  /// In en, this message translates to:
  /// **'Token refused'**
  String get statusRejected;

  /// No description provided for @bannerReconnecting.
  ///
  /// In en, this message translates to:
  /// **'{engine} stopped answering. XPath keeps trying; what you see may be out of date.'**
  String bannerReconnecting(String engine);

  /// No description provided for @bannerUnreachable.
  ///
  /// In en, this message translates to:
  /// **'{engine} is unreachable. Showing what was cached, read-only, until it is back.'**
  String bannerUnreachable(String engine);

  /// No description provided for @bannerSecretsLocked.
  ///
  /// In en, this message translates to:
  /// **'The Keychain on {engine} is locked. Jobs queue until it is unlocked.'**
  String bannerSecretsLocked(String engine);

  /// No description provided for @bannerRejected.
  ///
  /// In en, this message translates to:
  /// **'{engine} refused the token of this Mac. Add the engine again with a new token.'**
  String bannerRejected(String engine);

  /// Toast: a store's state was marked by hand.
  ///
  /// In en, this message translates to:
  /// **'Store status saved'**
  String get releaseMarkedToast;

  /// Toast: the release branch was merged back.
  ///
  /// In en, this message translates to:
  /// **'Release branch merged'**
  String get releaseMergedToast;

  /// Toast: the jobs of the run that had not ended were cancelled.
  ///
  /// In en, this message translates to:
  /// **'Run cancelled'**
  String get jobCancelledToast;

  /// Loads what could not be loaded again.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// What a screen reader says for the placeholder of a page that loads.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get loading;

  /// Toolbar chip: the page shows what was cached; the engine was not heard in this session.
  ///
  /// In en, this message translates to:
  /// **'Cached'**
  String get cached;

  /// Toolbar chip: the page shows what was cached when the engine was last heard.
  ///
  /// In en, this message translates to:
  /// **'Cached · {time}'**
  String cachedSince(String time);

  /// Checks the engine now.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get bannerRetry;

  /// Opens the engine list.
  ///
  /// In en, this message translates to:
  /// **'Engines…'**
  String get bannerEngines;

  /// Banner: the local engine does not answer.
  ///
  /// In en, this message translates to:
  /// **'The engine on this Mac isn\'t running.'**
  String get bannerLocalStopped;

  /// Banner: the app brings the local engine back.
  ///
  /// In en, this message translates to:
  /// **'Starting the engine on this Mac…'**
  String get bannerLocalStarting;

  /// Banner while the engine's Keychain is locked: how to unlock it.
  ///
  /// In en, this message translates to:
  /// **'Sign in to that Mac, or unlock its login keychain in Keychain Access; jobs start again by themselves.'**
  String get bannerSecretsLockedSteps;

  /// Banner: reveals the log of the engine on this Mac.
  ///
  /// In en, this message translates to:
  /// **'Show log in Finder'**
  String get bannerShowLog;

  /// Banner: the engine on this Mac refused the app's token; runs the setup again.
  ///
  /// In en, this message translates to:
  /// **'Set up this Mac again'**
  String get bannerSetUpAgain;

  /// Starts the engine on this Mac again (banner, Settings).
  ///
  /// In en, this message translates to:
  /// **'Start engine'**
  String get localEngineStart;

  /// Start engine failed: no engine in the bundle, or macOS cannot find its login item.
  ///
  /// In en, this message translates to:
  /// **'This copy of XPath has no engine macOS can start. Open XPath from Applications, or install it again.'**
  String get localEngineNoEngine;

  /// Start engine failed: the login item needs the owner's OK.
  ///
  /// In en, this message translates to:
  /// **'macOS is waiting for you. Allow XPath in System Settings ▸ General ▸ Login Items, then start the engine.'**
  String get localEngineNeedsApproval;

  /// Start engine failed.
  ///
  /// In en, this message translates to:
  /// **'Running the engine needs macOS 13 or later.'**
  String get localEngineUnsupported;

  /// Start engine failed.
  ///
  /// In en, this message translates to:
  /// **'macOS did not start the engine: {message}'**
  String localEngineRefused(String message);

  /// Start engine failed: no answer in time.
  ///
  /// In en, this message translates to:
  /// **'The engine did not answer within 30 seconds. Its log is in ~/Library/Application Support/XPath/service-logs/xpd.log.'**
  String get localEngineTimedOut;

  /// Start engine failed.
  ///
  /// In en, this message translates to:
  /// **'The engine runs, but XPath could not make a new token for this app: {message}'**
  String localEngineToken(String message);

  /// Settings: the engine on this Mac answers.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get localEngineRunning;

  /// Settings: the engine on this Mac does not answer.
  ///
  /// In en, this message translates to:
  /// **'Not running'**
  String get localEngineNotRunning;

  /// Settings: the engine on this Mac is being started.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get localEngineStarting;

  /// Tooltip of a command disabled because the engine cannot be reached.
  ///
  /// In en, this message translates to:
  /// **'Read-only while the engine is away'**
  String get readOnlyHint;

  /// Sidebar section label.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get sidebarProjects;

  /// Sidebar section label.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get sidebarEngine;

  /// Sidebar row.
  ///
  /// In en, this message translates to:
  /// **'Credentials'**
  String get sidebarCredentials;

  /// Sidebar row.
  ///
  /// In en, this message translates to:
  /// **'Engines'**
  String get sidebarEngines;

  /// Sidebar row that opens Add project.
  ///
  /// In en, this message translates to:
  /// **'Add project…'**
  String get sidebarAddProject;

  /// Sidebar, when the engine has no project.
  ///
  /// In en, this message translates to:
  /// **'No projects yet'**
  String get sidebarNoProjects;

  /// No description provided for @projectApps.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 app} other{{count} apps}}'**
  String projectApps(int count);

  /// No description provided for @projectErrors.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 error} other{{count} errors}}'**
  String projectErrors(int count);

  /// No description provided for @projectWarnings.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 warning} other{{count} warnings}}'**
  String projectWarnings(int count);

  /// Last item of the engine switcher menu.
  ///
  /// In en, this message translates to:
  /// **'Manage engines…'**
  String get engineMenuManage;

  /// Title of the engine list.
  ///
  /// In en, this message translates to:
  /// **'Engines'**
  String get enginesTitle;

  /// Subtitle of the engine list.
  ///
  /// In en, this message translates to:
  /// **'Where XPath runs your builds. The app shows one engine at a time.'**
  String get enginesSubtitle;

  /// The name of the engine on this Mac.
  ///
  /// In en, this message translates to:
  /// **'This Mac'**
  String get enginesLocalName;

  /// Tag of the engine the app shows.
  ///
  /// In en, this message translates to:
  /// **'Showing'**
  String get enginesActive;

  /// Switches the app to this engine.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get enginesUse;

  /// Forgets this engine and its token.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get enginesRemove;

  /// No description provided for @enginesRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String enginesRemoveTitle(String name);

  /// No description provided for @enginesRemoveForget.
  ///
  /// In en, this message translates to:
  /// **'This Mac forgets {name} and its token.'**
  String enginesRemoveForget(String name);

  /// Remove engine confirmation.
  ///
  /// In en, this message translates to:
  /// **'The engine keeps running, with its projects and releases. Adding it again needs a new token.'**
  String get enginesRemoveKeeps;

  /// Opens onboarding to run the engine on this Mac.
  ///
  /// In en, this message translates to:
  /// **'Set up this Mac…'**
  String get enginesSetUpLocal;

  /// Title of the add-engine form.
  ///
  /// In en, this message translates to:
  /// **'Add a remote engine'**
  String get enginesAddTitle;

  /// No description provided for @enginesAddHelp.
  ///
  /// In en, this message translates to:
  /// **'On the engine machine, run xpd token create --name \"{device}\" --kind app and paste the token here. It is kept in the Keychain of this Mac.'**
  String enginesAddHelp(String device);

  /// Checks and saves the engine.
  ///
  /// In en, this message translates to:
  /// **'Add engine'**
  String get enginesAddButton;

  /// While the engine is checked.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get enginesChecking;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get fieldName;

  /// Example engine name.
  ///
  /// In en, this message translates to:
  /// **'mac-mini'**
  String get fieldNameHint;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get fieldUrl;

  /// Example engine URL.
  ///
  /// In en, this message translates to:
  /// **'http://mac-mini.local:7480'**
  String get fieldUrlHint;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Token'**
  String get fieldToken;

  /// Add engine error.
  ///
  /// In en, this message translates to:
  /// **'Enter an http(s) URL with a host, like http://mac-mini.local:7480.'**
  String get engineCheckInvalidUrl;

  /// Add engine error.
  ///
  /// In en, this message translates to:
  /// **'Nothing answered at that URL. Is xpd serve running there, and can this Mac reach it?'**
  String get engineCheckUnreachable;

  /// Add engine error.
  ///
  /// In en, this message translates to:
  /// **'Something answered at that URL, but it is not an XPath engine.'**
  String get engineCheckNotAnEngine;

  /// Add engine error.
  ///
  /// In en, this message translates to:
  /// **'The engine speaks another version of the API. Update the one that is behind.'**
  String get engineCheckApiMismatch;

  /// Add engine error.
  ///
  /// In en, this message translates to:
  /// **'The engine refused this token. Make a new one with xpd token create --kind app.'**
  String get engineCheckTokenRejected;

  /// No description provided for @engineNoTokenTitle.
  ///
  /// In en, this message translates to:
  /// **'No token for {engine}'**
  String engineNoTokenTitle(String engine);

  /// Shown when the token of the active engine is missing.
  ///
  /// In en, this message translates to:
  /// **'The Keychain of this Mac has no token for this engine, or it could not be read. Try again once the Keychain is unlocked, or remove the engine and add it again.'**
  String get engineNoTokenBody;

  /// Reads the engine's token from the Keychain again.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get engineNoTokenRetry;

  /// Onboarding headline.
  ///
  /// In en, this message translates to:
  /// **'Set up XPath on this Mac'**
  String get onboardingTitle;

  /// Onboarding lead.
  ///
  /// In en, this message translates to:
  /// **'XPath runs a small engine in the background that does the builds, signing and uploads. Three steps; nothing leaves this Mac.'**
  String get onboardingSubtitle;

  /// Onboarding step.
  ///
  /// In en, this message translates to:
  /// **'Start the engine'**
  String get onboardingEngineTitle;

  /// Onboarding step.
  ///
  /// In en, this message translates to:
  /// **'Registers the engine as a login item, so it runs now and at every login, and connects this app to it.'**
  String get onboardingEngineBody;

  /// Onboarding step action.
  ///
  /// In en, this message translates to:
  /// **'Start engine'**
  String get onboardingEngineButton;

  /// Onboarding step result.
  ///
  /// In en, this message translates to:
  /// **'The engine runs and this app is connected to it.'**
  String get onboardingEngineEnabled;

  /// Onboarding step result.
  ///
  /// In en, this message translates to:
  /// **'Allow XPath in System Settings ▸ General ▸ Login Items, then start the engine again.'**
  String get onboardingEngineApproval;

  /// Opens System Settings.
  ///
  /// In en, this message translates to:
  /// **'Open Login Items…'**
  String get onboardingOpenLoginItems;

  /// Onboarding step result.
  ///
  /// In en, this message translates to:
  /// **'This build has no engine inside it. Use an engine by URL instead.'**
  String get onboardingEngineNotFound;

  /// Onboarding step result.
  ///
  /// In en, this message translates to:
  /// **'Running the engine as a login item needs macOS 13 or later.'**
  String get onboardingEngineUnsupported;

  /// No description provided for @onboardingEngineFailed.
  ///
  /// In en, this message translates to:
  /// **'macOS did not register the engine: {message}'**
  String onboardingEngineFailed(String message);

  /// No description provided for @onboardingTokenFailed.
  ///
  /// In en, this message translates to:
  /// **'The engine runs, but XPath could not make a token for this app: {message}'**
  String onboardingTokenFailed(String message);

  /// No description provided for @onboardingAppTokenName.
  ///
  /// In en, this message translates to:
  /// **'XPath app on {device}'**
  String onboardingAppTokenName(String device);

  /// Onboarding step.
  ///
  /// In en, this message translates to:
  /// **'Add xp to your PATH'**
  String get onboardingCliTitle;

  /// Onboarding step.
  ///
  /// In en, this message translates to:
  /// **'Links the xp command line tool inside this app, so you and your agents can use it in a terminal. No password needed.'**
  String get onboardingCliBody;

  /// Onboarding step action.
  ///
  /// In en, this message translates to:
  /// **'Link xp'**
  String get onboardingCliButton;

  /// No description provided for @cliLinked.
  ///
  /// In en, this message translates to:
  /// **'Linked at {path}.'**
  String cliLinked(String path);

  /// No description provided for @cliLinkedFallback.
  ///
  /// In en, this message translates to:
  /// **'Linked at {path}. Writing /usr/local/bin needs an administrator password, so XPath used ~/.local/bin instead; add it to your PATH if your shell does not have it.'**
  String cliLinkedFallback(String path);

  /// No description provided for @cliElsewhere.
  ///
  /// In en, this message translates to:
  /// **'{path} links to another copy of XPath ({pointsTo}). Link xp again to use this one.'**
  String cliElsewhere(String path, String pointsTo);

  /// Link status in the settings.
  ///
  /// In en, this message translates to:
  /// **'xp is not linked, so a terminal cannot find it.'**
  String get cliNotLinked;

  /// Link status while it is read.
  ///
  /// In en, this message translates to:
  /// **'Looking for xp…'**
  String get cliChecking;

  /// Replaces a link into another copy of XPath.
  ///
  /// In en, this message translates to:
  /// **'Link xp again'**
  String get cliRelink;

  /// Link result.
  ///
  /// In en, this message translates to:
  /// **'This build has no xp inside it.'**
  String get cliMissing;

  /// No description provided for @cliConflict.
  ///
  /// In en, this message translates to:
  /// **'{path} is another xp. XPath left it alone.'**
  String cliConflict(String path);

  /// No description provided for @cliFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not link xp: {detail}'**
  String cliFailed(String detail);

  /// Onboarding step.
  ///
  /// In en, this message translates to:
  /// **'Check the tools'**
  String get onboardingToolsTitle;

  /// Onboarding step.
  ///
  /// In en, this message translates to:
  /// **'The engine builds with the tools of this Mac. Xcode and git are needed; the others only when you use them.'**
  String get onboardingToolsBody;

  /// Onboarding step action.
  ///
  /// In en, this message translates to:
  /// **'Check tools'**
  String get onboardingToolsButton;

  /// Tool name.
  ///
  /// In en, this message translates to:
  /// **'Xcode'**
  String get toolXcode;

  /// Tool name.
  ///
  /// In en, this message translates to:
  /// **'git'**
  String get toolGit;

  /// Tool name.
  ///
  /// In en, this message translates to:
  /// **'fvm'**
  String get toolFvm;

  /// Tool name.
  ///
  /// In en, this message translates to:
  /// **'GitHub CLI'**
  String get toolGh;

  /// Tool name.
  ///
  /// In en, this message translates to:
  /// **'Shorebird'**
  String get toolShorebird;

  /// Tool status.
  ///
  /// In en, this message translates to:
  /// **'Found'**
  String get toolFound;

  /// Tool status.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get toolMissing;

  /// Tool status of a missing optional tool.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get toolOptional;

  /// How to get the tool.
  ///
  /// In en, this message translates to:
  /// **'Install Xcode from the App Store and open it once.'**
  String get toolXcodeHint;

  /// How to get the tool.
  ///
  /// In en, this message translates to:
  /// **'Comes with the developer tools: xcode-select --install.'**
  String get toolGitHint;

  /// How to get the tool.
  ///
  /// In en, this message translates to:
  /// **'Without fvm the engine downloads the Flutter each project pins.'**
  String get toolFvmHint;

  /// How to get the tool.
  ///
  /// In en, this message translates to:
  /// **'Lets the engine use your GitHub login: brew install gh.'**
  String get toolGhHint;

  /// How to get the tool.
  ///
  /// In en, this message translates to:
  /// **'Only for over-the-air patches.'**
  String get toolShorebirdHint;

  /// Ends onboarding.
  ///
  /// In en, this message translates to:
  /// **'Open XPath'**
  String get onboardingDone;

  /// Switches onboarding to the add-engine form.
  ///
  /// In en, this message translates to:
  /// **'Use a remote engine instead…'**
  String get onboardingRemote;

  /// Goes back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get onboardingBack;

  /// Label of a finished onboarding step.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get stepDone;

  /// Label of a running onboarding step.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get stepWorking;

  /// Title.
  ///
  /// In en, this message translates to:
  /// **'Add project'**
  String get addProjectTitle;

  /// Lead.
  ///
  /// In en, this message translates to:
  /// **'Pick the folder of a git repository. XPath reads it and never writes to it; builds run from the engine\'s own copy.'**
  String get addProjectBody;

  /// No description provided for @addProjectRemoteNote.
  ///
  /// In en, this message translates to:
  /// **'The folder has to be on {engine}, the machine the engine runs on.'**
  String addProjectRemoteNote(String engine);

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get addProjectFolder;

  /// Example folder.
  ///
  /// In en, this message translates to:
  /// **'/Users/you/src/app'**
  String get addProjectFolderHint;

  /// Opens the folder picker.
  ///
  /// In en, this message translates to:
  /// **'Choose folder…'**
  String get addProjectChoose;

  /// Adds the project.
  ///
  /// In en, this message translates to:
  /// **'Add and scan'**
  String get addProjectAdd;

  /// While the engine scans.
  ///
  /// In en, this message translates to:
  /// **'Scanning…'**
  String get addProjectScanning;

  /// No description provided for @addProjectFailed.
  ///
  /// In en, this message translates to:
  /// **'The engine could not add this folder: {message}'**
  String addProjectFailed(String message);

  /// Offered when the folder's origin is an HTTPS URL on a host other than GitHub.
  ///
  /// In en, this message translates to:
  /// **'XPath reads repositories outside GitHub over SSH, with the engine\'s own key. Add the folder from {sshUrl} instead? Your clone is not changed.'**
  String addProjectSshOffer(String sshUrl);

  /// Adds the folder from the offered SSH URL.
  ///
  /// In en, this message translates to:
  /// **'Use the SSH URL'**
  String get addProjectUseSsh;

  /// No description provided for @addProjectReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review the scan of {name}'**
  String addProjectReviewTitle(String name);

  /// Lead of the review.
  ///
  /// In en, this message translates to:
  /// **'This is what XPath found. Fix errors in the repository and scan again; warnings and notes can wait.'**
  String get addProjectReviewBody;

  /// Keeps the project.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get addProjectKeep;

  /// Removes the project just added.
  ///
  /// In en, this message translates to:
  /// **'Remove project'**
  String get addProjectDiscard;

  /// No description provided for @addProjectRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String addProjectRemoveTitle(String name);

  /// Remove project confirmation.
  ///
  /// In en, this message translates to:
  /// **'The engine forgets the project and what its scan found.'**
  String get addProjectRemoveForget;

  /// Remove project confirmation.
  ///
  /// In en, this message translates to:
  /// **'Nothing in the folder or on GitHub changes.'**
  String get addProjectRemoveKeeps;

  /// Scans the project again.
  ///
  /// In en, this message translates to:
  /// **'Scan again'**
  String get scanAgain;

  /// Section label.
  ///
  /// In en, this message translates to:
  /// **'Findings'**
  String get scanFindings;

  /// When the scan found nothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing to fix.'**
  String get scanNoFindings;

  /// No description provided for @scanFix.
  ///
  /// In en, this message translates to:
  /// **'Fix: {fix}'**
  String scanFix(String fix);

  /// When the scan found no app.
  ///
  /// In en, this message translates to:
  /// **'No Flutter app found.'**
  String get scanNoApps;

  /// No description provided for @scanAppMeta.
  ///
  /// In en, this message translates to:
  /// **'path {path} · Flutter {version} · store country {country}'**
  String scanAppMeta(String path, String version, String country);

  /// Flutter version when none is pinned.
  ///
  /// In en, this message translates to:
  /// **'not pinned'**
  String get scanUnpinned;

  /// Column.
  ///
  /// In en, this message translates to:
  /// **'Flavor'**
  String get scanColumnFlavor;

  /// Column.
  ///
  /// In en, this message translates to:
  /// **'iOS bundle ID'**
  String get scanColumnIos;

  /// Column.
  ///
  /// In en, this message translates to:
  /// **'Android application ID'**
  String get scanColumnAndroid;

  /// Column.
  ///
  /// In en, this message translates to:
  /// **'Shorebird'**
  String get scanColumnShorebird;

  /// Shorebird enabled.
  ///
  /// In en, this message translates to:
  /// **'on'**
  String get scanShorebirdOn;

  /// Shorebird disabled.
  ///
  /// In en, this message translates to:
  /// **'off'**
  String get scanShorebirdOff;

  /// Tag of a production flavor.
  ///
  /// In en, this message translates to:
  /// **'prod'**
  String get scanProd;

  /// Finding severity.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get scanError;

  /// Finding severity.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get scanWarning;

  /// Finding severity.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get scanInfo;

  /// No description provided for @projectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{branch} · {apps}'**
  String projectSubtitle(String branch, String apps);

  /// The host of a project whose origin is a file:// repository.
  ///
  /// In en, this message translates to:
  /// **'local repository'**
  String get projectHostLocal;

  /// Empty state headline.
  ///
  /// In en, this message translates to:
  /// **'No projects yet'**
  String get projectEmptyTitle;

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'Add the folder of a Flutter app\'s repository to start.'**
  String get projectEmptyBody;

  /// When the selected project was removed.
  ///
  /// In en, this message translates to:
  /// **'This project is no longer on the engine.'**
  String get projectGone;

  /// Title.
  ///
  /// In en, this message translates to:
  /// **'Credentials'**
  String get credentialsTitle;

  /// Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Shared by every project on this engine. Checked every day and before each build; the secrets stay on the engine machine.'**
  String get credentialsSubtitle;

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'Add a project to give its flavors credentials.'**
  String get credentialsNoProject;

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'No credentials yet. Add one, then assign it to the flavors that need it.'**
  String get credentialsEmpty;

  /// Opens the credential form.
  ///
  /// In en, this message translates to:
  /// **'Add credential…'**
  String get credentialsAdd;

  /// Checks a credential.
  ///
  /// In en, this message translates to:
  /// **'Check now'**
  String get credentialsVerify;

  /// Opens the form that replaces the secret of a credential.
  ///
  /// In en, this message translates to:
  /// **'Replace secret…'**
  String get credentialsReplace;

  /// Asks before deleting a credential.
  ///
  /// In en, this message translates to:
  /// **'Delete…'**
  String get credentialsDelete;

  /// Asks for a new name for a credential.
  ///
  /// In en, this message translates to:
  /// **'Rename…'**
  String get credentialsRename;

  /// Column.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get credentialsColumnName;

  /// Column: the flavors that use a credential.
  ///
  /// In en, this message translates to:
  /// **'Used by'**
  String get credentialsColumnUsedBy;

  /// Column: the credentials a flavor uses.
  ///
  /// In en, this message translates to:
  /// **'Credentials'**
  String get credentialsColumnAssigned;

  /// How many flavors use a credential; which ones on hover.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Not used} =1{1 flavor} other{{count} flavors}}'**
  String credentialsUsedBy(int count);

  /// Section of the flavors of a project.
  ///
  /// In en, this message translates to:
  /// **'Flavors'**
  String get credentialsFlavorsTitle;

  /// Section lead.
  ///
  /// In en, this message translates to:
  /// **'Each flavor uses at most one credential of each kind. Several flavors, of any project, can share one.'**
  String get credentialsFlavorsHelp;

  /// A flavor uses no credential.
  ///
  /// In en, this message translates to:
  /// **'None assigned'**
  String get credentialsNoneAssigned;

  /// Opens the credentials of a flavor.
  ///
  /// In en, this message translates to:
  /// **'Manage…'**
  String get credentialsManage;

  /// Column.
  ///
  /// In en, this message translates to:
  /// **'Flavor'**
  String get credentialsColumnFlavor;

  /// Column.
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get credentialsColumnKind;

  /// Column.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get credentialsColumnAccount;

  /// Column.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get credentialsColumnStatus;

  /// Credential status.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get credentialVerified;

  /// Credential status.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get credentialRejected;

  /// Credential status: never checked or the check could not be made.
  ///
  /// In en, this message translates to:
  /// **'Not checked'**
  String get credentialUnchecked;

  /// Toast: the engine checked a credential again.
  ///
  /// In en, this message translates to:
  /// **'Checked {name}: {status}'**
  String credentialCheckedToast(String name, String status);

  /// Toast: the engine checked and stored the credential.
  ///
  /// In en, this message translates to:
  /// **'Credential saved'**
  String get credentialSavedToast;

  /// No description provided for @credentialFailed.
  ///
  /// In en, this message translates to:
  /// **'Not saved: {message}'**
  String credentialFailed(String message);

  /// Credential kind.
  ///
  /// In en, this message translates to:
  /// **'App Store Connect API key'**
  String get kindAscKey;

  /// Credential kind.
  ///
  /// In en, this message translates to:
  /// **'Apple ID'**
  String get kindAppleId;

  /// Credential kind.
  ///
  /// In en, this message translates to:
  /// **'Google Play service account'**
  String get kindPlaySa;

  /// Credential kind.
  ///
  /// In en, this message translates to:
  /// **'Firebase service account'**
  String get kindFirebaseSa;

  /// Credential kind.
  ///
  /// In en, this message translates to:
  /// **'Android keystore'**
  String get kindKeystore;

  /// Credential kind.
  ///
  /// In en, this message translates to:
  /// **'Shorebird API key'**
  String get kindShorebird;

  /// Credential kind.
  ///
  /// In en, this message translates to:
  /// **'GitHub token'**
  String get kindGithub;

  /// Credential kind.
  ///
  /// In en, this message translates to:
  /// **'Slack webhook'**
  String get kindSlack;

  /// Form title.
  ///
  /// In en, this message translates to:
  /// **'Add a credential'**
  String get credentialFormTitle;

  /// Form lead.
  ///
  /// In en, this message translates to:
  /// **'The engine checks it with the place it is for before it keeps it. Nothing is stored if the check fails.'**
  String get credentialFormHelp;

  /// Form title.
  ///
  /// In en, this message translates to:
  /// **'Replace the secret of {name}'**
  String credentialFormReplaceTitle(String name);

  /// Form lead.
  ///
  /// In en, this message translates to:
  /// **'Its name and the flavors that use it stay. The engine checks the new secret first; nothing changes if the check fails. The old secret is not shown.'**
  String get credentialFormReplaceHelp;

  /// Field label: the name of a credential.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get fieldCredentialName;

  /// Example credential name.
  ///
  /// In en, this message translates to:
  /// **'Team App Store key'**
  String get fieldCredentialNameHint;

  /// Field label: team or individual App Store Connect key.
  ///
  /// In en, this message translates to:
  /// **'Key type'**
  String get fieldKeyKind;

  /// App Store Connect key type.
  ///
  /// In en, this message translates to:
  /// **'Team key'**
  String get keyKindTeam;

  /// App Store Connect key type.
  ///
  /// In en, this message translates to:
  /// **'Individual key'**
  String get keyKindIndividual;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get fieldKind;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Key ID'**
  String get fieldKeyId;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Issuer ID'**
  String get fieldIssuerId;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Private key (.p8)'**
  String get fieldPrivateKey;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Apple ID'**
  String get fieldAppleId;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'App-specific password'**
  String get fieldAppPassword;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Service account key (JSON)'**
  String get fieldServiceAccount;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Keystore'**
  String get fieldKeystore;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Store password'**
  String get fieldStorePassword;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Key alias'**
  String get fieldKeyAlias;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Key password (if not the store password)'**
  String get fieldKeyPassword;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Webhook URL'**
  String get fieldWebhookUrl;

  /// Fills a field from a file.
  ///
  /// In en, this message translates to:
  /// **'Choose file…'**
  String get fieldChooseFile;

  /// No description provided for @fieldFileChosen.
  ///
  /// In en, this message translates to:
  /// **'{name} · {size}'**
  String fieldFileChosen(String name, String size);

  /// Saves the credential.
  ///
  /// In en, this message translates to:
  /// **'Check and save'**
  String get credentialFormSave;

  /// Closes the form.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get credentialFormCancel;

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Rename {name}'**
  String renameCredentialTitle(String name);

  /// Dialog lead.
  ///
  /// In en, this message translates to:
  /// **'Its secret and the flavors that use it stay.'**
  String get renameCredentialHelp;

  /// Renames the credential.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameCredentialConfirm;

  /// Dialog title.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String deleteCredentialTitle(String name);

  /// What deleting a credential does.
  ///
  /// In en, this message translates to:
  /// **'Its secret is deleted from the engine machine.'**
  String get deleteCredentialSecret;

  /// Deleting an unused credential.
  ///
  /// In en, this message translates to:
  /// **'No flavor uses it.'**
  String get deleteCredentialUnused;

  /// Deleting a credential in use; the flavors follow.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 flavor uses it. It will have no {kind} until you assign another:} other{{count} flavors use it. They will have no {kind} until you assign another:}}'**
  String deleteCredentialUsed(int count, String kind);

  /// Closes the dialog.
  ///
  /// In en, this message translates to:
  /// **'Keep it'**
  String get deleteCredentialKeep;

  /// Deletes the credential.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteCredentialConfirm;

  /// Unassigns the credential everywhere, then deletes it.
  ///
  /// In en, this message translates to:
  /// **'Unassign and delete'**
  String get deleteCredentialConfirmInUse;

  /// Sheet title.
  ///
  /// In en, this message translates to:
  /// **'Credentials of {flavor}'**
  String flavorCredentialsTitle(String flavor);

  /// Sheet lead.
  ///
  /// In en, this message translates to:
  /// **'The credential this flavor uses for each kind, with what the last checks found: does it work, and can it reach this flavor\'s app.'**
  String get flavorCredentialsHelp;

  /// Section of the flavor sheet: the Firebase and App Store Connect app ids.
  ///
  /// In en, this message translates to:
  /// **'Store ids'**
  String get flavorStoreIds;

  /// Flavor sheet, store ids.
  ///
  /// In en, this message translates to:
  /// **'The built-in workflows upload this flavor\'s builds to these apps when a dispatch names none. The scan fills in the Firebase ids its files name.'**
  String get flavorStoreIdsHelp;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Firebase app id · Android'**
  String get flavorFirebaseAndroid;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Firebase app id · iOS'**
  String get flavorFirebaseIos;

  /// Placeholder of a Firebase app id field.
  ///
  /// In en, this message translates to:
  /// **'1:123456789012:{platform}:abc123'**
  String flavorFirebaseHint(String platform);

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'App Store Connect app id'**
  String get flavorAppleAppId;

  /// Placeholder of the App Store Connect app id field.
  ///
  /// In en, this message translates to:
  /// **'1234567890'**
  String get flavorAppleAppIdHint;

  /// Saves the store ids of the flavor.
  ///
  /// In en, this message translates to:
  /// **'Save ids'**
  String get flavorStoreIdsSave;

  /// The store ids were saved.
  ///
  /// In en, this message translates to:
  /// **'Saved. The next dispatch uploads to these apps.'**
  String get flavorStoreIdsSaved;

  /// On a finding of a missing Firebase app id: opens the flavor's store ids.
  ///
  /// In en, this message translates to:
  /// **'Set Firebase app id…'**
  String get scanSetStoreId;

  /// The flavor has no credential of a kind.
  ///
  /// In en, this message translates to:
  /// **'Not assigned'**
  String get flavorCredentialsNotAssigned;

  /// Opens the picker of a kind.
  ///
  /// In en, this message translates to:
  /// **'Assign…'**
  String get flavorCredentialsAssign;

  /// Opens the picker of a kind.
  ///
  /// In en, this message translates to:
  /// **'Change…'**
  String get flavorCredentialsChange;

  /// Unassigns the credential; it stays.
  ///
  /// In en, this message translates to:
  /// **'Remove from this flavor'**
  String get flavorCredentialsRemove;

  /// Picker field.
  ///
  /// In en, this message translates to:
  /// **'Credential'**
  String get flavorCredentialsCredential;

  /// Picker choice: a new credential.
  ///
  /// In en, this message translates to:
  /// **'Add new…'**
  String get flavorCredentialsAddNew;

  /// Picker field.
  ///
  /// In en, this message translates to:
  /// **'Use for'**
  String get flavorCredentialsUseFor;

  /// Picker scope.
  ///
  /// In en, this message translates to:
  /// **'This flavor'**
  String get flavorCredentialsThisFlavor;

  /// Picker scope.
  ///
  /// In en, this message translates to:
  /// **'Every flavor of {app}'**
  String flavorCredentialsEveryFlavor(String app);

  /// Picker option: the other flavors give up their credential.
  ///
  /// In en, this message translates to:
  /// **'Replace existing'**
  String get flavorCredentialsReplace;

  /// Picker note.
  ///
  /// In en, this message translates to:
  /// **'Flavors that have their own {kind} keep it.'**
  String flavorCredentialsReplaceOff(String kind);

  /// Picker note.
  ///
  /// In en, this message translates to:
  /// **'Every flavor of the app uses this {kind}, even those that have their own.'**
  String flavorCredentialsReplaceOn(String kind);

  /// Assigns the chosen credential.
  ///
  /// In en, this message translates to:
  /// **'Assign'**
  String get flavorCredentialsConfirm;

  /// Adds the new credential, then assigns it.
  ///
  /// In en, this message translates to:
  /// **'Check, save and assign'**
  String get flavorCredentialsCreate;

  /// After assigning to every flavor without replacing.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{flavors} kept its own credential. Tick “Replace existing” to change it too.} other{{flavors} kept their own credentials. Tick “Replace existing” to change them too.}}'**
  String flavorCredentialsKept(int count, String flavors);

  /// Job or step status.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get statusQueued;

  /// Job or step status.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get statusRunning;

  /// Job or step status.
  ///
  /// In en, this message translates to:
  /// **'Succeeded'**
  String get statusSucceeded;

  /// Job or step status.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get statusFailed;

  /// Job or step status.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelled;

  /// Job or step status.
  ///
  /// In en, this message translates to:
  /// **'Skipped · already done'**
  String get statusSkipped;

  /// Job or step status.
  ///
  /// In en, this message translates to:
  /// **'Interrupted'**
  String get statusInterrupted;

  /// Job or step status.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a resume'**
  String get statusWaitingForResume;

  /// Job or step status.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval'**
  String get statusWaitingForApproval;

  /// Release status.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get releaseDraft;

  /// Release status.
  ///
  /// In en, this message translates to:
  /// **'Building'**
  String get releaseBuilding;

  /// Release status.
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get releaseUploaded;

  /// Release status.
  ///
  /// In en, this message translates to:
  /// **'In review'**
  String get releaseInReview;

  /// Release status.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get releaseRejected;

  /// Release status.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get releaseApproved;

  /// Release status.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get releaseLive;

  /// Release status.
  ///
  /// In en, this message translates to:
  /// **'Merged'**
  String get releaseMerged;

  /// Release status.
  ///
  /// In en, this message translates to:
  /// **'Abandoned'**
  String get releaseAbandoned;

  /// Status of a release in a store.
  ///
  /// In en, this message translates to:
  /// **'Not uploaded'**
  String get storeNotUploaded;

  /// Status of a release in a store.
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get storeUploaded;

  /// Status of a release in a store.
  ///
  /// In en, this message translates to:
  /// **'In review'**
  String get storeInReview;

  /// Status of a release in a store.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get storeRejected;

  /// Status of a release in a store.
  ///
  /// In en, this message translates to:
  /// **'Not approved'**
  String get storeNotApproved;

  /// Status of a release in a store.
  ///
  /// In en, this message translates to:
  /// **'Pending developer release'**
  String get storePendingRelease;

  /// Status of a release in a store.
  ///
  /// In en, this message translates to:
  /// **'Approved · not published'**
  String get storeApprovedUnpublished;

  /// Status of a release in a store.
  ///
  /// In en, this message translates to:
  /// **'Ready for sale'**
  String get storeReadyForSale;

  /// Status of a release in a store.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get storePublished;

  /// Store name.
  ///
  /// In en, this message translates to:
  /// **'App Store'**
  String get storeAppStore;

  /// Store name.
  ///
  /// In en, this message translates to:
  /// **'Google Play'**
  String get storeGooglePlay;

  /// Platform name.
  ///
  /// In en, this message translates to:
  /// **'iOS'**
  String get platformIos;

  /// Platform name.
  ///
  /// In en, this message translates to:
  /// **'Android'**
  String get platformAndroid;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Check out'**
  String get stepGitCheckout;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Checks'**
  String get stepGuard;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Bump version'**
  String get stepVersionBump;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Build Android'**
  String get stepBuildAndroid;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Build iOS'**
  String get stepBuildIos;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Verify compiled config'**
  String get stepVerifyConfig;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Strip and re-export IPA'**
  String get stepStripIpa;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Shorebird release'**
  String get stepShorebirdRelease;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Shorebird patch'**
  String get stepShorebirdPatch;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Archive symbols'**
  String get stepSymbols;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Tests'**
  String get stepTest;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Analyze'**
  String get stepAnalyze;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Upload to App Store'**
  String get stepUploadAppStore;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Upload to Google Play'**
  String get stepUploadPlay;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Upload to Firebase'**
  String get stepUploadFirebase;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get stepGitTag;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Push'**
  String get stepGitPush;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Cut the release branch'**
  String get stepReleaseBranch;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Open the release PR'**
  String get stepCreatePr;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Merge the release PR'**
  String get stepMergePr;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Record the manifest'**
  String get stepManifest;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Approval'**
  String get stepGate;

  /// Name of a kind of step.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get stepCommand;

  /// A gated action, inside a sentence.
  ///
  /// In en, this message translates to:
  /// **'production release'**
  String get gateProdRelease;

  /// A gated action, inside a sentence.
  ///
  /// In en, this message translates to:
  /// **'production patch'**
  String get gateProdPatch;

  /// A gated action, inside a sentence.
  ///
  /// In en, this message translates to:
  /// **'store submission'**
  String get gateStoreSubmission;

  /// A gated action, inside a sentence.
  ///
  /// In en, this message translates to:
  /// **'push'**
  String get gatePush;

  /// A gated action, inside a sentence.
  ///
  /// In en, this message translates to:
  /// **'merge'**
  String get gateMerge;

  /// A gated action, inside a sentence.
  ///
  /// In en, this message translates to:
  /// **'delete'**
  String get gateDelete;

  /// Toolbar title of the job view before the workflow is known.
  ///
  /// In en, this message translates to:
  /// **'Job'**
  String get jobTitle;

  /// Where a job runs when the active engine has no name.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get jobEngine;

  /// Caption of a pipeline stage the workflow does not name.
  ///
  /// In en, this message translates to:
  /// **'Stage {number}'**
  String jobStage(int number);

  /// A step of a job the engine did not describe.
  ///
  /// In en, this message translates to:
  /// **'Step {number}'**
  String jobStep(int number);

  /// After a stage caption whose job waits for an approval.
  ///
  /// In en, this message translates to:
  /// **'needs you'**
  String get jobNeedsYou;

  /// Toolbar status.
  ///
  /// In en, this message translates to:
  /// **'{count} running'**
  String jobRunningCount(int count);

  /// Runs the selected job again from its first step.
  ///
  /// In en, this message translates to:
  /// **'Restart job'**
  String get jobRestart;

  /// Resumes the job at a step.
  ///
  /// In en, this message translates to:
  /// **'Resume from {step}'**
  String jobResumeFrom(String step);

  /// Cancels the run (asks first).
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get jobCancel;

  /// Hero of a failed run.
  ///
  /// In en, this message translates to:
  /// **'Failed at {step}'**
  String jobFailedAt(String step);

  /// Under the hero of a running run.
  ///
  /// In en, this message translates to:
  /// **'elapsed {duration} · started {time}'**
  String jobElapsed(String duration, String time);

  /// Under the hero of a run that stopped.
  ///
  /// In en, this message translates to:
  /// **'ran {duration} · started {time}'**
  String jobRan(String duration, String time);

  /// Dispatches a finished run again.
  ///
  /// In en, this message translates to:
  /// **'Run again'**
  String get jobRunAgain;

  /// No description provided for @jobRunAgainOlder.
  ///
  /// In en, this message translates to:
  /// **'Run again runs version {ran} of the workflow, the one this run ran; it has version {newest} now.'**
  String jobRunAgainOlder(int ran, int newest);

  /// Runs the failed jobs of a run again, from the steps that failed.
  ///
  /// In en, this message translates to:
  /// **'Re-run failed jobs'**
  String get jobRerunFailed;

  /// Tooltip: saves an artifact where the owner picks.
  ///
  /// In en, this message translates to:
  /// **'Download…'**
  String get jobArtifactDownload;

  /// Tooltip: shows a downloaded artifact in Finder.
  ///
  /// In en, this message translates to:
  /// **'Reveal in Finder'**
  String get jobArtifactReveal;

  /// Tooltip: copies where a downloaded artifact is.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get jobArtifactCopyPath;

  /// Toast.
  ///
  /// In en, this message translates to:
  /// **'Copied the path'**
  String get jobArtifactCopied;

  /// Run summary.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get runSummaryVersion;

  /// Run summary: the build number.
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get runSummaryBuild;

  /// Run summary.
  ///
  /// In en, this message translates to:
  /// **'Jobs'**
  String get runSummaryJobs;

  /// Run summary.
  ///
  /// In en, this message translates to:
  /// **'Tests'**
  String get runSummaryTests;

  /// No description provided for @runSummaryTestCounts.
  ///
  /// In en, this message translates to:
  /// **'{passed} passed · {failed} failed · {skipped} skipped'**
  String runSummaryTestCounts(int passed, int failed, int skipped);

  /// Run summary.
  ///
  /// In en, this message translates to:
  /// **'Flavors'**
  String get runSummaryFlavors;

  /// Run summary: links to where the stores show the build.
  ///
  /// In en, this message translates to:
  /// **'In the stores'**
  String get runSummaryStores;

  /// No description provided for @runSummaryAppStore.
  ///
  /// In en, this message translates to:
  /// **'App Store Connect · {flavor}'**
  String runSummaryAppStore(String flavor);

  /// No description provided for @runSummaryPlay.
  ///
  /// In en, this message translates to:
  /// **'Google Play · {flavor}'**
  String runSummaryPlay(String flavor);

  /// No description provided for @logCopyLine.
  ///
  /// In en, this message translates to:
  /// **'Copy line {line}'**
  String logCopyLine(int line);

  /// No description provided for @logCopiedLine.
  ///
  /// In en, this message translates to:
  /// **'Copied line {line}'**
  String logCopiedLine(int line);

  /// Artifacts of the shown job.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 artifact} other{{count} artifacts}}'**
  String jobArtifacts(int count);

  /// Section label.
  ///
  /// In en, this message translates to:
  /// **'Artifacts'**
  String get jobArtifactsLabel;

  /// Label over the step list.
  ///
  /// In en, this message translates to:
  /// **'{job} · {runner} · steps'**
  String jobStepsOf(String job, String runner);

  /// Section label.
  ///
  /// In en, this message translates to:
  /// **'Resume plan'**
  String get jobResumePlan;

  /// Resume plan: steps that do not run again.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{First step} other{First {count} steps}}'**
  String jobResumeKept(int count);

  /// Resume plan.
  ///
  /// In en, this message translates to:
  /// **'already done'**
  String get jobAlreadyDone;

  /// Resume plan: where the resume starts.
  ///
  /// In en, this message translates to:
  /// **'{step} and after'**
  String jobResumeRuns(String step);

  /// Interrupted banner.
  ///
  /// In en, this message translates to:
  /// **'The engine stopped while this job ran. Finished steps are kept; resume runs the interrupted step again from its start.'**
  String get jobInterruptedBody;

  /// Interrupted banner of a job waiting for a resume.
  ///
  /// In en, this message translates to:
  /// **'The engine stopped during {step}, which changes something outside the engine, so it never runs again by itself. Check, then resume.'**
  String jobWaitingForResumeBody(String step);

  /// Under the hero of a queued job: why it has not started.
  ///
  /// In en, this message translates to:
  /// **'Waiting: {reason}'**
  String jobWaitReason(String reason);

  /// Interrupted banner: no side-effect step succeeded.
  ///
  /// In en, this message translates to:
  /// **'Nothing outside the engine was changed.'**
  String get jobNothingChanged;

  /// Title of the cancel sheet.
  ///
  /// In en, this message translates to:
  /// **'Cancel {run}?'**
  String cancelRunTitle(String run);

  /// Cancel sheet.
  ///
  /// In en, this message translates to:
  /// **'{job} stops now on {runner} ({duration} in). Its partial output is discarded.'**
  String cancelRunStops(String job, String runner, String duration);

  /// Cancel sheet.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{The finished job keeps its artifacts; Resume can reuse them.} other{The {count} finished jobs keep their artifacts; Resume can reuse them.}}'**
  String cancelRunKept(int count);

  /// Cancel sheet.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 job that has not started will not run.} other{{count} jobs that have not started will not run.}}'**
  String cancelRunNeverStarts(int count);

  /// Closes the cancel sheet.
  ///
  /// In en, this message translates to:
  /// **'Keep running'**
  String get cancelRunKeep;

  /// Cancels the run.
  ///
  /// In en, this message translates to:
  /// **'Cancel run'**
  String get cancelRunConfirm;

  /// An empty log.
  ///
  /// In en, this message translates to:
  /// **'No output yet'**
  String get logEmpty;

  /// Placeholder of the log filter.
  ///
  /// In en, this message translates to:
  /// **'Filter log'**
  String get logFilter;

  /// Scrolls the log to the first error.
  ///
  /// In en, this message translates to:
  /// **'Jump to error'**
  String get logJumpToError;

  /// Tooltip.
  ///
  /// In en, this message translates to:
  /// **'Wrap lines'**
  String get logWrap;

  /// Tooltip.
  ///
  /// In en, this message translates to:
  /// **'Timestamps'**
  String get logTimestamps;

  /// Keeps the log at its end.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get logFollow;

  /// Lines of a collapsed step.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 line} other{{count} lines}}'**
  String logLines(int count);

  /// Title of the dispatch sheet.
  ///
  /// In en, this message translates to:
  /// **'Dispatch'**
  String get dispatchTitle;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Workflow'**
  String get dispatchWorkflow;

  /// Dispatch sheet.
  ///
  /// In en, this message translates to:
  /// **'The project has no workflow.'**
  String get dispatchNoWorkflows;

  /// Dispatch sheet: a workflow with a GitHub or push step on a project that is not on GitHub.
  ///
  /// In en, this message translates to:
  /// **'This workflow cannot run here: its {step} step works only on GitHub, and this project is on {host}. Run one without GitHub steps, such as dev-build or test.'**
  String dispatchNeedsGitHub(String step, String host);

  /// After the workflow name.
  ///
  /// In en, this message translates to:
  /// **'built-in'**
  String get dispatchBuiltin;

  /// After the workflow name: the run stops for approvals.
  ///
  /// In en, this message translates to:
  /// **'gated'**
  String get dispatchGated;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get dispatchApp;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Flavors'**
  String get dispatchFlavors;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Platforms'**
  String get dispatchPlatforms;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Ref'**
  String get dispatchRef;

  /// Ref kind.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get dispatchBranch;

  /// Ref kind.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get dispatchTag;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get dispatchVersion;

  /// Version bump.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get bumpKeep;

  /// Version bump.
  ///
  /// In en, this message translates to:
  /// **'Patch'**
  String get bumpPatch;

  /// Version bump.
  ///
  /// In en, this message translates to:
  /// **'Minor'**
  String get bumpMinor;

  /// Version bump.
  ///
  /// In en, this message translates to:
  /// **'Major'**
  String get bumpMajor;

  /// Beside the version a dispatch releases.
  ///
  /// In en, this message translates to:
  /// **'from {version} in the pubspec of the commit'**
  String dispatchFromPubspec(String version);

  /// Placeholder of the explicit version field next to the bump.
  ///
  /// In en, this message translates to:
  /// **'or x.y.z'**
  String get dispatchVersionHint;

  /// Section of the dispatch sheet: the inputs the workflow declares.
  ///
  /// In en, this message translates to:
  /// **'Inputs'**
  String get dispatchInputs;

  /// A boolean input set to true.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get dispatchYes;

  /// A boolean input set to false.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get dispatchNo;

  /// Under a JSON input whose text does not parse.
  ///
  /// In en, this message translates to:
  /// **'Not valid JSON.'**
  String get dispatchJsonInvalid;

  /// A release input when the project has no release to pick; Dispatch waits.
  ///
  /// In en, this message translates to:
  /// **'No releases yet: this workflow needs a release that reached a store.'**
  String get dispatchNoReleases;

  /// A release in the release picker.
  ///
  /// In en, this message translates to:
  /// **'{version} · {flavor}'**
  String dispatchRelease(String version, String flavor);

  /// Label over the preview.
  ///
  /// In en, this message translates to:
  /// **'Will run · {jobs, plural, =1{1 job} other{{jobs} jobs}} in {stages, plural, =1{1 stage} other{{stages} stages}}'**
  String dispatchWillRun(int jobs, int stages);

  /// Empty preview.
  ///
  /// In en, this message translates to:
  /// **'Nothing would run for these flavors and platforms.'**
  String get dispatchNothing;

  /// A stage that runs on the engine only.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 job} other{{count} jobs}} on {engine}'**
  String dispatchOnEngine(int count, String engine);

  /// Where a job that can run anywhere lands.
  ///
  /// In en, this message translates to:
  /// **'{engine} first, else {runner}'**
  String dispatchOnRunner(String engine, String runner);

  /// A job the run leaves out, and why (the engine's words).
  ///
  /// In en, this message translates to:
  /// **'skipped, {reason}'**
  String dispatchSkipped(String reason);

  /// A job the engine cannot plan, so the dispatch would be refused.
  ///
  /// In en, this message translates to:
  /// **'cannot run: {reason}'**
  String dispatchBlocked(String reason);

  /// The build number a dispatch would take.
  ///
  /// In en, this message translates to:
  /// **'build {build}'**
  String dispatchBuildNumber(int build);

  /// Row of a stage's gates.
  ///
  /// In en, this message translates to:
  /// **'{stage} approval'**
  String dispatchGateTitle(String stage);

  /// Which gates a stage hits.
  ///
  /// In en, this message translates to:
  /// **'waits for your approval: {gates}'**
  String dispatchGates(String gates);

  /// Footer of the dispatch sheet.
  ///
  /// In en, this message translates to:
  /// **'Return does not dispatch'**
  String get dispatchReturnHint;

  /// Closes the dispatch sheet.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get dispatchCancel;

  /// The dispatch button when there is no plan to count the jobs of: the engine fetches the ref first, or the workflow cannot run on this project.
  ///
  /// In en, this message translates to:
  /// **'Dispatch'**
  String get dispatchUnplanned;

  /// The dispatch button.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Dispatch 1 job} other{Dispatch {count} jobs}}'**
  String dispatchButton(int count);

  /// Ledger filter: every flavor.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get overviewAll;

  /// Toolbar status.
  ///
  /// In en, this message translates to:
  /// **'Nothing running · nothing needs you'**
  String get overviewQuiet;

  /// Toolbar status: jobs waiting for an approval.
  ///
  /// In en, this message translates to:
  /// **'{count} needs you'**
  String overviewNeedsYou(int count);

  /// Opens the dispatch sheet.
  ///
  /// In en, this message translates to:
  /// **'Dispatch…'**
  String get overviewDispatch;

  /// Opens the job view of the release in flight.
  ///
  /// In en, this message translates to:
  /// **'Open job'**
  String get overviewOpenJob;

  /// Under the hero.
  ///
  /// In en, this message translates to:
  /// **'started {time}'**
  String overviewStarted(String time);

  /// Caption of the store column.
  ///
  /// In en, this message translates to:
  /// **'In the stores · {version}'**
  String overviewInStores(String version);

  /// Hero with nothing live.
  ///
  /// In en, this message translates to:
  /// **'No release yet'**
  String get overviewNoRelease;

  /// Hero with nothing in flight.
  ///
  /// In en, this message translates to:
  /// **'Live on both stores'**
  String get overviewLiveBoth;

  /// Hero with nothing in flight.
  ///
  /// In en, this message translates to:
  /// **'Live on {store}'**
  String overviewLiveIn(String store);

  /// Beside the live versions.
  ///
  /// In en, this message translates to:
  /// **'No release in flight'**
  String get overviewNothingInFlight;

  /// Shows the scan of the project.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get overviewScan;

  /// Title of the scan sheet.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get overviewScanTitle;

  /// Closes a sheet.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get overviewClose;

  /// Ledger column.
  ///
  /// In en, this message translates to:
  /// **'Flavor'**
  String get ledgerFlavor;

  /// Ledger column.
  ///
  /// In en, this message translates to:
  /// **'Local · {branch}'**
  String ledgerLocal(String branch);

  /// Ledger column.
  ///
  /// In en, this message translates to:
  /// **'Testing'**
  String get ledgerTesting;

  /// Ledger column.
  ///
  /// In en, this message translates to:
  /// **'Live · {store}'**
  String ledgerLive(String store);

  /// Ledger column.
  ///
  /// In en, this message translates to:
  /// **'Credentials'**
  String get ledgerCredentials;

  /// Where the local version comes from.
  ///
  /// In en, this message translates to:
  /// **'pubspec'**
  String get ledgerPubspec;

  /// The pubspec has no version.
  ///
  /// In en, this message translates to:
  /// **'No version'**
  String get ledgerNoVersion;

  /// Testing column without any release.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get ledgerNoRelease;

  /// Testing column without any release.
  ///
  /// In en, this message translates to:
  /// **'no release yet'**
  String get ledgerNoReleaseHint;

  /// Testing column.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get ledgerUpToDate;

  /// Testing column.
  ///
  /// In en, this message translates to:
  /// **'Nothing newer than live'**
  String get ledgerNothingNewer;

  /// Testing column of a release that builds.
  ///
  /// In en, this message translates to:
  /// **'Not uploaded'**
  String get ledgerNotUploaded;

  /// Testing column of a release that builds.
  ///
  /// In en, this message translates to:
  /// **'{version} building'**
  String ledgerWaitsFor(String version);

  /// Live column.
  ///
  /// In en, this message translates to:
  /// **'Not on store'**
  String get ledgerNotOnStore;

  /// Live column of a production flavor.
  ///
  /// In en, this message translates to:
  /// **'no live release'**
  String get ledgerNoLiveRelease;

  /// Live column of another flavor.
  ///
  /// In en, this message translates to:
  /// **'not a production flavor'**
  String get ledgerNotProd;

  /// Credentials column.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get ledgerCredentialsNone;

  /// Credentials column of a flavor without any.
  ///
  /// In en, this message translates to:
  /// **'Assign…'**
  String get ledgerCredentialsAssign;

  /// Tooltip of the credentials column.
  ///
  /// In en, this message translates to:
  /// **'Manage the credentials of this flavor'**
  String get ledgerCredentialsManage;

  /// Ledger with every row filtered out.
  ///
  /// In en, this message translates to:
  /// **'No flavor to show.'**
  String get ledgerNoFlavors;

  /// The docked console.
  ///
  /// In en, this message translates to:
  /// **'Console'**
  String get consoleTitle;

  /// The collapsed console.
  ///
  /// In en, this message translates to:
  /// **'· last: {job}'**
  String consoleLast(String job);

  /// Sidebar row under the selected project.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get sidebarOverview;

  /// Sidebar row under the selected project.
  ///
  /// In en, this message translates to:
  /// **'Releases'**
  String get sidebarReleases;

  /// Sidebar row: the approvals inbox.
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get sidebarApprovals;

  /// Opens the release in flight.
  ///
  /// In en, this message translates to:
  /// **'Open release'**
  String get overviewOpenRelease;

  /// Lead of the needs-you bar.
  ///
  /// In en, this message translates to:
  /// **'Needs you'**
  String get needsYou;

  /// After the title on the needs-you bar.
  ///
  /// In en, this message translates to:
  /// **'{sha} · expires in {left}'**
  String needsYouMeta(String sha, String left);

  /// Opens the inbox when more than one approval waits.
  ///
  /// In en, this message translates to:
  /// **'+{count} more'**
  String needsYouMore(int count);

  /// Approval state.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get approvalPending;

  /// Approval state.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get approvalApproved;

  /// Approval state.
  ///
  /// In en, this message translates to:
  /// **'Denied'**
  String get approvalDenied;

  /// Approval state.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get approvalExpired;

  /// What a prod_release approval asks.
  ///
  /// In en, this message translates to:
  /// **'Release {version} to the stores'**
  String approvalTitleRelease(String version);

  /// What a prod_patch approval asks.
  ///
  /// In en, this message translates to:
  /// **'Patch {version}'**
  String approvalTitlePatch(String version);

  /// What a store_submission approval asks.
  ///
  /// In en, this message translates to:
  /// **'Submit {version} to the stores'**
  String approvalTitleSubmit(String version);

  /// What a push approval asks.
  ///
  /// In en, this message translates to:
  /// **'Push {version} to GitHub'**
  String approvalTitlePush(String version);

  /// What a merge approval asks.
  ///
  /// In en, this message translates to:
  /// **'Merge the release PR of {version}'**
  String approvalTitleMerge(String version);

  /// An approval of an action the app does not know.
  ///
  /// In en, this message translates to:
  /// **'Approve the {action} of {version}'**
  String approvalTitleOther(String action, String version);

  /// An approval without a version.
  ///
  /// In en, this message translates to:
  /// **'Approve the {action}'**
  String approvalTitleBare(String action);

  /// Label over what approving does.
  ///
  /// In en, this message translates to:
  /// **'If you approve'**
  String get approvalIfYouApprove;

  /// What approving a prod_release does.
  ///
  /// In en, this message translates to:
  /// **'XPath builds {version} from {sha} and releases it to the stores.'**
  String approvalIfRelease(String version, String sha);

  /// What approving a prod_patch does.
  ///
  /// In en, this message translates to:
  /// **'XPath publishes a Shorebird patch of {version} built from {sha}.'**
  String approvalIfPatch(String version, String sha);

  /// What approving a store_submission does.
  ///
  /// In en, this message translates to:
  /// **'XPath uploads the builds made from {sha} and submits {version} for store review.'**
  String approvalIfSubmit(String version, String sha);

  /// What approving a push does.
  ///
  /// In en, this message translates to:
  /// **'XPath pushes the release commit {sha} and the tag of {version} to GitHub.'**
  String approvalIfPush(String version, String sha);

  /// What approving a merge does.
  ///
  /// In en, this message translates to:
  /// **'XPath merges the release pull request of {version} into {branch} with a merge commit.'**
  String approvalIfMerge(String version, String branch);

  /// What approving a delete does.
  ///
  /// In en, this message translates to:
  /// **'XPath deletes what the job asks to delete, on {sha}.'**
  String approvalIfDelete(String sha);

  /// What approving an unknown action does.
  ///
  /// In en, this message translates to:
  /// **'The job goes on with its {action}.'**
  String approvalIfOther(String action);

  /// The flavor and bundle ID a release goes out as.
  ///
  /// In en, this message translates to:
  /// **'It goes out as {target}.'**
  String approvalIfTarget(String target);

  /// Under what approving does.
  ///
  /// In en, this message translates to:
  /// **'If the commit, version or flavor change before then, this approval is void.'**
  String get approvalVoid;

  /// A branch the engine did not name.
  ///
  /// In en, this message translates to:
  /// **'the base branch'**
  String get approvalBaseBranch;

  /// Beside the badge of a pending approval.
  ///
  /// In en, this message translates to:
  /// **'expires in {left} · {asked}'**
  String approvalExpiresIn(String left, String asked);

  /// Under a pending approval in the inbox.
  ///
  /// In en, this message translates to:
  /// **'expires in {left}'**
  String approvalExpiresShort(String left);

  /// Beside the badge of an expired approval.
  ///
  /// In en, this message translates to:
  /// **'expired {at}'**
  String approvalExpiredAt(String at);

  /// Beside the badge of a decided approval.
  ///
  /// In en, this message translates to:
  /// **'by {who} · {at}'**
  String approvalDecidedBy(String who, String at);

  /// Who decided, when the engine does not say.
  ///
  /// In en, this message translates to:
  /// **'another device'**
  String get approvalSomeone;

  /// Under the approval hero.
  ///
  /// In en, this message translates to:
  /// **'asked at {time}'**
  String approvalAskedAt(String time);

  /// Row of the approval details.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get approvalProject;

  /// Row of the approval details.
  ///
  /// In en, this message translates to:
  /// **'Flavor'**
  String get approvalFlavor;

  /// Row of the approval details.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get approvalVersion;

  /// Row of the approval details.
  ///
  /// In en, this message translates to:
  /// **'Commit'**
  String get approvalCommit;

  /// Row of the approval details.
  ///
  /// In en, this message translates to:
  /// **'Job'**
  String get approvalJob;

  /// Row of the approval details.
  ///
  /// In en, this message translates to:
  /// **'Gate'**
  String get approvalGate;

  /// Row of the approval details.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get approvalReason;

  /// The gate an approval comes from.
  ///
  /// In en, this message translates to:
  /// **'Project gate “{action}”'**
  String approvalGateName(String action);

  /// After the job of a pending approval.
  ///
  /// In en, this message translates to:
  /// **'{step} waits for this'**
  String approvalWaits(String step);

  /// Opens the confirmation sheet.
  ///
  /// In en, this message translates to:
  /// **'Review…'**
  String get approvalReview;

  /// Approves, in the confirmation sheet (⌘↩).
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approvalApprove;

  /// Opens the confirmation sheet from the inbox.
  ///
  /// In en, this message translates to:
  /// **'Approve…'**
  String get approvalApproveEllipsis;

  /// Opens the denial.
  ///
  /// In en, this message translates to:
  /// **'Deny…'**
  String get approvalDenyEllipsis;

  /// Denies, in the confirmation sheet.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get approvalDeny;

  /// Leaves the denial.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get approvalBack;

  /// Closes a sheet without doing anything.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get approvalCancel;

  /// Closes a sheet with nothing left to do.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get approvalClose;

  /// Field of the denial.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get approvalDenyReason;

  /// Placeholder of the denial reason.
  ///
  /// In en, this message translates to:
  /// **'Why, for the record'**
  String get approvalDenyReasonHint;

  /// Footer of the confirmation sheet.
  ///
  /// In en, this message translates to:
  /// **'Return never approves. ⌘↩ approves.'**
  String get approvalReturnHint;

  /// Tooltip of Approve before the arming delay is over.
  ///
  /// In en, this message translates to:
  /// **'Approve arms in a moment'**
  String get approvalArming;

  /// An approval another device decided first.
  ///
  /// In en, this message translates to:
  /// **'Already {state} by {who}. The first decision counts; nothing to do here.'**
  String approvalDecidedElsewhere(String state, String who);

  /// An approval that ran out of time.
  ///
  /// In en, this message translates to:
  /// **'This approval expired: it counts as denied. Dispatch again to ask anew.'**
  String get approvalExpiredElsewhere;

  /// An approval the engine does not know.
  ///
  /// In en, this message translates to:
  /// **'This approval cannot be read on this engine.'**
  String get approvalGone;

  /// Toolbar title of the inbox.
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get approvalsTitle;

  /// Toolbar subtitle of the inbox.
  ///
  /// In en, this message translates to:
  /// **'{engine} · {count} pending'**
  String approvalsSubtitle(String engine, int count);

  /// Inbox filter.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get approvalsPending;

  /// Inbox filter.
  ///
  /// In en, this message translates to:
  /// **'Decided'**
  String get approvalsDecided;

  /// Inbox filter.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get approvalsExpired;

  /// The inbox without a pending approval.
  ///
  /// In en, this message translates to:
  /// **'Nothing is waiting'**
  String get approvalsNothingWaits;

  /// An inbox filter without an approval.
  ///
  /// In en, this message translates to:
  /// **'Nothing here'**
  String get approvalsNone;

  /// Body of the notification of an approval.
  ///
  /// In en, this message translates to:
  /// **'{where} · expires in {left}'**
  String notificationBody(String where, String left);

  /// Dismisses the notification of an approval.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get notificationLater;

  /// Tooltip of the menu bar extra.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{XPath: 1 needs you} other{XPath: {count} need you}}'**
  String menuBarTooltip(int count);

  /// First line of the menu bar extra.
  ///
  /// In en, this message translates to:
  /// **'Needs you · {count}'**
  String menuBarNeedsYou(int count);

  /// First line of the menu bar extra when nothing waits.
  ///
  /// In en, this message translates to:
  /// **'Nothing needs you'**
  String get menuBarNothing;

  /// A pending approval in the menu bar extra.
  ///
  /// In en, this message translates to:
  /// **'Review: {title}…'**
  String menuBarReview(String title);

  /// Under a pending approval in the menu bar extra.
  ///
  /// In en, this message translates to:
  /// **'{where} · {left} left'**
  String menuBarLeft(String where, String left);

  /// Brings the window forward.
  ///
  /// In en, this message translates to:
  /// **'Open XPath'**
  String get menuBarOpen;

  /// Toolbar title of the releases.
  ///
  /// In en, this message translates to:
  /// **'Releases'**
  String get releasesTitle;

  /// The releases of a project without one.
  ///
  /// In en, this message translates to:
  /// **'A production release dispatched from the overview shows up here.'**
  String get releasesEmpty;

  /// Empty releases: opens the dispatch sheet on the prod release.
  ///
  /// In en, this message translates to:
  /// **'Dispatch Prod release…'**
  String get releasesDispatchProd;

  /// The releases of a project that is not on GitHub.
  ///
  /// In en, this message translates to:
  /// **'Production releases push and open a pull request on GitHub, so they do not run for a project on {host}. Dev builds and tests do.'**
  String releasesEmptyNoGitHub(String host);

  /// Toolbar title of a release.
  ///
  /// In en, this message translates to:
  /// **'Release {version}'**
  String releaseTitle(String version);

  /// Asks the stores about the release now.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get releaseRefresh;

  /// Tooltip of Refresh.
  ///
  /// In en, this message translates to:
  /// **'Ask the stores now instead of waiting up to ten minutes'**
  String get releaseRefreshHint;

  /// Hero of a release a store rejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected by {store}'**
  String releaseRejectedBy(String store);

  /// Hero of a release both stores rejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected by both stores'**
  String get releaseRejectedByBoth;

  /// Label over the lanes.
  ///
  /// In en, this message translates to:
  /// **'Store lanes'**
  String get lanesTitle;

  /// A step of a store lane.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get storeApproved;

  /// A store the engine cannot read.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get storeUnknown;

  /// An App Store build waiting for its review.
  ///
  /// In en, this message translates to:
  /// **'Waiting for review'**
  String get storeWaitingForReview;

  /// Both stores in a sentence.
  ///
  /// In en, this message translates to:
  /// **'App Store and Google Play'**
  String get storesBoth;

  /// Joins two items of a list.
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get listAnd;

  /// Time of the current step of a lane.
  ///
  /// In en, this message translates to:
  /// **'since {time}'**
  String laneSince(String time);

  /// The App Store lane without a key.
  ///
  /// In en, this message translates to:
  /// **'no API key'**
  String get laneNoApiKey;

  /// The Google Play lane without a service account.
  ///
  /// In en, this message translates to:
  /// **'no service account'**
  String get laneNoServiceAccount;

  /// A lane the release does not target.
  ///
  /// In en, this message translates to:
  /// **'This release does not go to {store}.'**
  String laneNotTargeted(String store);

  /// Builds a rejected version again.
  ///
  /// In en, this message translates to:
  /// **'New build, same version…'**
  String get laneNewBuild;

  /// Beside New build, same version.
  ///
  /// In en, this message translates to:
  /// **'{version} → a new build number'**
  String laneNewBuildCaption(String version);

  /// The other lane of a rejected release.
  ///
  /// In en, this message translates to:
  /// **'A new build replaces {build} here too, so both stores ship the same build.'**
  String laneReplacedToo(String build);

  /// Says by hand that Apple approved.
  ///
  /// In en, this message translates to:
  /// **'Mark approved'**
  String get laneMarkApproved;

  /// Says by hand that the store has it live.
  ///
  /// In en, this message translates to:
  /// **'Mark live'**
  String get laneMarkLive;

  /// No description provided for @laneMarkTitle.
  ///
  /// In en, this message translates to:
  /// **'Mark {version} {state}?'**
  String laneMarkTitle(String version, String state);

  /// Mark approved / live confirmation.
  ///
  /// In en, this message translates to:
  /// **'The engine cannot read this store, so it records your mark as manual, at this time.'**
  String get laneMarkManual;

  /// Mark approved / live confirmation.
  ///
  /// In en, this message translates to:
  /// **'The release moves on from it; a mark cannot be taken back.'**
  String get laneMarkFinal;

  /// Opens the credentials.
  ///
  /// In en, this message translates to:
  /// **'Add API key…'**
  String get laneAddApiKey;

  /// Opens the credentials.
  ///
  /// In en, this message translates to:
  /// **'Add service account…'**
  String get laneAddServiceAccount;

  /// The App Store lane without a key.
  ///
  /// In en, this message translates to:
  /// **'No App Store Connect API key for this flavor: the engine cannot read the review, and each mark is recorded as manual'**
  String get laneManualApple;

  /// The Google Play lane without a service account.
  ///
  /// In en, this message translates to:
  /// **'No Google Play service account for this flavor: the engine cannot read the review, and each mark is recorded as manual'**
  String get laneManualPlay;

  /// The version on sale before this release.
  ///
  /// In en, this message translates to:
  /// **'Live now {version}'**
  String laneLiveNow(String version);

  /// The version this release replaced.
  ///
  /// In en, this message translates to:
  /// **'Replaced {version}'**
  String laneReplaced(String version);

  /// Title of the New build confirmation.
  ///
  /// In en, this message translates to:
  /// **'Build {version} again?'**
  String newBuildTitle(String version);

  /// Body of the New build confirmation.
  ///
  /// In en, this message translates to:
  /// **'The production workflow runs again on the release branch with the same version and the next free build number; {build} is never reused. It asks for your approval like any release.'**
  String newBuildBody(String build);

  /// Confirms New build, same version.
  ///
  /// In en, this message translates to:
  /// **'Start new build'**
  String get newBuildConfirm;

  /// The Merge button.
  ///
  /// In en, this message translates to:
  /// **'Merge into {branch}'**
  String mergeInto(String branch);

  /// Under Merge when it is open.
  ///
  /// In en, this message translates to:
  /// **'Both stores live'**
  String get mergeReady;

  /// Under Merge when it is open.
  ///
  /// In en, this message translates to:
  /// **'{branch} → {base} · both stores live'**
  String mergeReadyBranch(String branch, String base);

  /// Under the hero of a merged release.
  ///
  /// In en, this message translates to:
  /// **'Merged · {sha}'**
  String mergeDone(String sha);

  /// Under Merge of an abandoned release.
  ///
  /// In en, this message translates to:
  /// **'The release was abandoned'**
  String get mergeAbandoned;

  /// Under Merge once it was asked for.
  ///
  /// In en, this message translates to:
  /// **'Merge requested'**
  String get mergeRequested;

  /// Under Merge while the merge waits at its gate.
  ///
  /// In en, this message translates to:
  /// **'Merge requested · waits for your approval'**
  String get mergeWaitsApproval;

  /// Under Merge of a rejected release.
  ///
  /// In en, this message translates to:
  /// **'{stores} rejected this build'**
  String mergeRejected(String stores);

  /// Under Merge without a PR.
  ///
  /// In en, this message translates to:
  /// **'The release has no pull request yet'**
  String get mergeNoPr;

  /// Under Merge.
  ///
  /// In en, this message translates to:
  /// **'Waits for both stores to go live'**
  String get mergeWaitsBoth;

  /// Under Merge.
  ///
  /// In en, this message translates to:
  /// **'Waits for {store} to go live'**
  String mergeWaitsStore(String store);

  /// Under Merge: a store marked by hand.
  ///
  /// In en, this message translates to:
  /// **'Mark {store} live'**
  String mergeMark(String store);

  /// Under Merge: a store the engine reads.
  ///
  /// In en, this message translates to:
  /// **'{store} must go live'**
  String mergeMust(String store);

  /// Label of the timeline panel.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get timelineTitle;

  /// Beside the timeline label.
  ///
  /// In en, this message translates to:
  /// **'newest first'**
  String get timelineNewestFirst;

  /// Timeline entry.
  ///
  /// In en, this message translates to:
  /// **'Release dispatched'**
  String get timelineDispatched;

  /// Timeline entry.
  ///
  /// In en, this message translates to:
  /// **'Build {build} started'**
  String timelineBuild(String build);

  /// Timeline entry.
  ///
  /// In en, this message translates to:
  /// **'{store}: {state}'**
  String timelineStore(String store, String state);

  /// Timeline entry.
  ///
  /// In en, this message translates to:
  /// **'Approval requested: {title}'**
  String timelineApprovalAsked(String title);

  /// Timeline entry.
  ///
  /// In en, this message translates to:
  /// **'{title}: {state}'**
  String timelineApprovalSettled(String title, String state);

  /// Timeline entry.
  ///
  /// In en, this message translates to:
  /// **'Merged into {branch}'**
  String timelineMerged(String branch);

  /// Where a store status came from.
  ///
  /// In en, this message translates to:
  /// **'Upload step'**
  String get sourceUpload;

  /// Where a store status came from.
  ///
  /// In en, this message translates to:
  /// **'App Store Connect API'**
  String get sourceAppStoreConnect;

  /// Where a store status came from.
  ///
  /// In en, this message translates to:
  /// **'Google Play API'**
  String get sourcePlayApi;

  /// Where a store status came from.
  ///
  /// In en, this message translates to:
  /// **'iTunes lookup'**
  String get sourceLookup;

  /// Where a store status came from.
  ///
  /// In en, this message translates to:
  /// **'Marked by hand'**
  String get sourceManual;

  /// Label of the notes panel.
  ///
  /// In en, this message translates to:
  /// **'Release notes'**
  String get notesTitle;

  /// Beside the notes label.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 commit} other{{count} commits}}'**
  String notesCommits(int count);

  /// Beside the notes label.
  ///
  /// In en, this message translates to:
  /// **'since {tag} · {count, plural, =1{1 commit} other{{count} commits}}'**
  String notesSince(String tag, int count);

  /// The notes of a release without a commit.
  ///
  /// In en, this message translates to:
  /// **'The notes are ready once the release is tagged.'**
  String get notesUntagged;

  /// Notes without a commit.
  ///
  /// In en, this message translates to:
  /// **'Nothing changed since the release before.'**
  String get notesNothing;

  /// Copies the notes.
  ///
  /// In en, this message translates to:
  /// **'Copy for Slack'**
  String get notesCopySlack;

  /// Copies the notes.
  ///
  /// In en, this message translates to:
  /// **'Copy for WhatsApp'**
  String get notesCopyWhatsApp;

  /// A copy button, for a moment after it copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// Cancel of a confirmation of a destructive action: keeps the object.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get confirmKeep;

  /// Confirms removing something.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get confirmRemove;

  /// Tooltip of something that copies itself when clicked.
  ///
  /// In en, this message translates to:
  /// **'{text} · click to copy'**
  String copyHint(String text);

  /// Label of the min_version panel.
  ///
  /// In en, this message translates to:
  /// **'Forced update'**
  String get minVersionTitle;

  /// Lead of the min_version banner.
  ///
  /// In en, this message translates to:
  /// **'Reminder'**
  String get minVersionReminder;

  /// Before any store is live.
  ///
  /// In en, this message translates to:
  /// **'If this release is a forced update, raise {variables} to {version} once the stores have it live. Raising it earlier locks out users who have nothing to update to.'**
  String minVersionLater(String variables, String version);

  /// Once a store is live.
  ///
  /// In en, this message translates to:
  /// **'{stores} live: if this release is a forced update, raise {variables} to {version} in Firebase Remote Config now.'**
  String minVersionNow(String stores, String variables, String version);

  /// The variables to raise later.
  ///
  /// In en, this message translates to:
  /// **'Raise {variables} once {stores} is live.'**
  String minVersionRest(String variables, String stores);

  /// The banner over a release live in every store.
  ///
  /// In en, this message translates to:
  /// **'If this release is a forced update, raise {variables} to {version}: every store has it live.'**
  String minVersionBanner(String variables, String version);

  /// A release without a store.
  ///
  /// In en, this message translates to:
  /// **'This release goes to no store.'**
  String get minVersionNoStores;

  /// Label of the PR panel.
  ///
  /// In en, this message translates to:
  /// **'Release PR'**
  String get prTitle;

  /// The PR panel without a PR.
  ///
  /// In en, this message translates to:
  /// **'No pull request yet: the release opens one once it is tagged.'**
  String get prNone;

  /// The PR panel.
  ///
  /// In en, this message translates to:
  /// **'Merging adds no tag: {tag} was tagged when the build was recorded.'**
  String prTagged(String tag);

  /// The PR panel.
  ///
  /// In en, this message translates to:
  /// **'The release is tagged when its build is recorded.'**
  String get prUntagged;

  /// The PR panel of a merged release.
  ///
  /// In en, this message translates to:
  /// **'Merged with a merge commit · {sha}'**
  String prMerged(String sha);

  /// Copies the PR link.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get prCopyLink;

  /// Opens the run that merges.
  ///
  /// In en, this message translates to:
  /// **'Open merge job'**
  String get prOpenMergeJob;

  /// Sidebar row under the selected project.
  ///
  /// In en, this message translates to:
  /// **'Tests'**
  String get sidebarTests;

  /// Sidebar row: the runners of the engine.
  ///
  /// In en, this message translates to:
  /// **'Runners'**
  String get sidebarRunners;

  /// No description provided for @sidebarRunnersBusy.
  ///
  /// In en, this message translates to:
  /// **'{count} busy'**
  String sidebarRunnersBusy(int count);

  /// Sidebar row: what the engine keeps on disk.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get sidebarStorage;

  /// No description provided for @sidebarStorageFreeable.
  ///
  /// In en, this message translates to:
  /// **'{size} free-able'**
  String sidebarStorageFreeable(String size);

  /// Opens the tests view at the run of the job.
  ///
  /// In en, this message translates to:
  /// **'Test results'**
  String get jobTestResults;

  /// A relative time under a minute.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get timeJustNow;

  /// No description provided for @timeAgo.
  ///
  /// In en, this message translates to:
  /// **'{duration} ago'**
  String timeAgo(String duration);

  /// No description provided for @timeYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday {time}'**
  String timeYesterday(String time);

  /// Title of the tests view.
  ///
  /// In en, this message translates to:
  /// **'Tests'**
  String get testsTitle;

  /// A run in the run picker that ended while the app watched.
  ///
  /// In en, this message translates to:
  /// **'just ended'**
  String get testsRunThisSession;

  /// Marks a baseline in the run picker.
  ///
  /// In en, this message translates to:
  /// **'baseline'**
  String get testsBaselineTag;

  /// Tests view without runs.
  ///
  /// In en, this message translates to:
  /// **'No test runs yet'**
  String get testsEmptyTitle;

  /// Tests view without runs.
  ///
  /// In en, this message translates to:
  /// **'Run the Tests workflow. Its runs on the base branch become the baseline that later runs are compared with; a run\'s results also open from its job.'**
  String get testsEmptyBody;

  /// Empty tests: opens the dispatch sheet on the Tests workflow.
  ///
  /// In en, this message translates to:
  /// **'Run Tests…'**
  String get testsRun;

  /// No description provided for @testsIsBaseline.
  ///
  /// In en, this message translates to:
  /// **'This run is the baseline of {branch}'**
  String testsIsBaseline(String branch);

  /// A run compared with nothing.
  ///
  /// In en, this message translates to:
  /// **'No baseline yet, so every failure counts as new'**
  String get testsNoBaseline;

  /// No description provided for @testsComparedToJob.
  ///
  /// In en, this message translates to:
  /// **'Compared with the baseline run of {job}'**
  String testsComparedToJob(String job);

  /// No description provided for @testsComparedTo.
  ///
  /// In en, this message translates to:
  /// **'Compared with the baseline of {branch} from {when}'**
  String testsComparedTo(String branch, String when);

  /// Hero of a run without new failures.
  ///
  /// In en, this message translates to:
  /// **'No new failures'**
  String get testsNoNewFailures;

  /// No description provided for @testsNewFailures.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 new failure} other{{count} new failures}}'**
  String testsNewFailures(int count);

  /// Under a count.
  ///
  /// In en, this message translates to:
  /// **'new failures'**
  String get testsStatNew;

  /// Under a count: tests failing as they did in the baseline.
  ///
  /// In en, this message translates to:
  /// **'in baseline'**
  String get testsStatInBaseline;

  /// Under a count.
  ///
  /// In en, this message translates to:
  /// **'fixed'**
  String get testsStatFixed;

  /// Under a count.
  ///
  /// In en, this message translates to:
  /// **'passed'**
  String get testsStatPassed;

  /// Under a count.
  ///
  /// In en, this message translates to:
  /// **'failed'**
  String get testsStatFailed;

  /// Under a count.
  ///
  /// In en, this message translates to:
  /// **'errored'**
  String get testsStatErrored;

  /// Under a count.
  ///
  /// In en, this message translates to:
  /// **'skipped'**
  String get testsStatSkipped;

  /// Under a count: baseline tests this run did not report.
  ///
  /// In en, this message translates to:
  /// **'missing'**
  String get testsStatMissing;

  /// A test whose expectation failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get testsFailed;

  /// A test that threw.
  ///
  /// In en, this message translates to:
  /// **'Errored'**
  String get testsErrored;

  /// A test that failed in the baseline and passes now.
  ///
  /// In en, this message translates to:
  /// **'Fixed'**
  String get testsFixed;

  /// A baseline test this run did not report.
  ///
  /// In en, this message translates to:
  /// **'Not reported'**
  String get testsMissing;

  /// Section label.
  ///
  /// In en, this message translates to:
  /// **'New failures'**
  String get testsNewFailuresTitle;

  /// Section label.
  ///
  /// In en, this message translates to:
  /// **'Failing in the baseline too'**
  String get testsStillFailingTitle;

  /// Section label.
  ///
  /// In en, this message translates to:
  /// **'Fixed since the baseline'**
  String get testsFixedTitle;

  /// Section label.
  ///
  /// In en, this message translates to:
  /// **'In the baseline, not in this run'**
  String get testsMissingTitle;

  /// No description provided for @testsTruncated.
  ///
  /// In en, this message translates to:
  /// **'Showing {shown} of {total} failing tests.'**
  String testsTruncated(String shown, String total);

  /// A run with nothing to list.
  ///
  /// In en, this message translates to:
  /// **'Every test passed and nothing changed against the baseline.'**
  String get testsAllPassed;

  /// Section label: one baseline per app and branch.
  ///
  /// In en, this message translates to:
  /// **'Baselines'**
  String get testsBaselinesTitle;

  /// Column label.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get testsColumnApp;

  /// Column label.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get testsColumnBranch;

  /// Column label.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get testsColumnWhen;

  /// Shows the run of a baseline.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get testsShowRun;

  /// Title of the runners view.
  ///
  /// In en, this message translates to:
  /// **'Runners'**
  String get runnersTitle;

  /// No description provided for @runnersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 runner} other{{count} runners}} · {busy} busy'**
  String runnersSubtitle(int count, int busy);

  /// Opens the pairing sheet.
  ///
  /// In en, this message translates to:
  /// **'Pair runner…'**
  String get runnersPair;

  /// Runners view without runners.
  ///
  /// In en, this message translates to:
  /// **'No runners yet'**
  String get runnersEmptyTitle;

  /// Runners view without runners.
  ///
  /// In en, this message translates to:
  /// **'Pair a Mac or a Linux machine and the engine sends it the jobs that fit its capabilities.'**
  String get runnersEmptyBody;

  /// Column label.
  ///
  /// In en, this message translates to:
  /// **'Runner'**
  String get runnersColumnRunner;

  /// Column label.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get runnersColumnStatus;

  /// Column label.
  ///
  /// In en, this message translates to:
  /// **'Capabilities'**
  String get runnersColumnCapabilities;

  /// Column label: jobs held of slots.
  ///
  /// In en, this message translates to:
  /// **'Slots'**
  String get runnersColumnSlots;

  /// Column label: the jobs a runner holds a lease for.
  ///
  /// In en, this message translates to:
  /// **'Jobs'**
  String get runnersColumnJobs;

  /// Column label: the last heartbeat.
  ///
  /// In en, this message translates to:
  /// **'Last heard'**
  String get runnersColumnLastHeard;

  /// Section label.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get runnersRevokedTitle;

  /// Runner status.
  ///
  /// In en, this message translates to:
  /// **'Online · idle'**
  String get runnerIdle;

  /// No description provided for @runnerBusy.
  ///
  /// In en, this message translates to:
  /// **'Online · busy {used}/{slots}'**
  String runnerBusy(int used, int slots);

  /// Runner status: finishing its jobs and taking no more.
  ///
  /// In en, this message translates to:
  /// **'Draining'**
  String get runnerDraining;

  /// Runner status: offline while it holds jobs.
  ///
  /// In en, this message translates to:
  /// **'Lost mid-job'**
  String get runnerLost;

  /// Runner status.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get runnerOffline;

  /// Runner status.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get runnerRevoked;

  /// No description provided for @runnerRevokedAt.
  ///
  /// In en, this message translates to:
  /// **'Revoked {when}'**
  String runnerRevokedAt(String when);

  /// No description provided for @runnerCores.
  ///
  /// In en, this message translates to:
  /// **'{count} cores'**
  String runnerCores(int count);

  /// A runner without capabilities.
  ///
  /// In en, this message translates to:
  /// **'Not probed yet'**
  String get runnerNotProbed;

  /// A capability the engine did not find on a runner; explanation is the engine's reason and fix.
  ///
  /// In en, this message translates to:
  /// **'No {capability}: {explanation}'**
  String runnerMissingCapability(String capability, String explanation);

  /// A runner that never sent a heartbeat.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get runnerNeverHeard;

  /// Opens the revoke confirmation.
  ///
  /// In en, this message translates to:
  /// **'Revoke…'**
  String get runnerRevoke;

  /// No description provided for @revokeRunnerTitle.
  ///
  /// In en, this message translates to:
  /// **'Revoke {name}?'**
  String revokeRunnerTitle(String name);

  /// Revoke confirmation.
  ///
  /// In en, this message translates to:
  /// **'Its credential stops working and its connection closes.'**
  String get revokeRunnerCredential;

  /// No description provided for @revokeRunnerJobs.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{The job it holds is queued again, or waits for a resume if it had a step with side effects.} other{The {count} jobs it holds are queued again, or wait for a resume if they had a step with side effects.}}'**
  String revokeRunnerJobs(int count);

  /// No description provided for @revokeRunnerName.
  ///
  /// In en, this message translates to:
  /// **'The name {name} stays taken: pair the machine again under a new name.'**
  String revokeRunnerName(String name);

  /// Closes the revoke confirmation.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get revokeRunnerKeep;

  /// Revokes the runner.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get revokeRunnerConfirm;

  /// Title of the pairing sheet.
  ///
  /// In en, this message translates to:
  /// **'Pair a runner'**
  String get pairRunnerTitle;

  /// Pairing sheet.
  ///
  /// In en, this message translates to:
  /// **'XPath makes a pairing token for the name. It works once, for 15 minutes, and is shown only now.'**
  String get pairRunnerBody;

  /// Field label: the runner's name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get pairRunnerName;

  /// Makes the pairing token.
  ///
  /// In en, this message translates to:
  /// **'Create pairing token'**
  String get pairRunnerCreate;

  /// Closes the pairing sheet.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get pairRunnerCancel;

  /// Closes the pairing sheet.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get pairRunnerDone;

  /// No description provided for @pairRunnerToken.
  ///
  /// In en, this message translates to:
  /// **'Pairing token for {name}'**
  String pairRunnerToken(String name);

  /// Copies the pairing token.
  ///
  /// In en, this message translates to:
  /// **'Copy token'**
  String get pairRunnerCopyToken;

  /// Label over the pairing command.
  ///
  /// In en, this message translates to:
  /// **'On the runner, run'**
  String get pairRunnerCommand;

  /// Copies the pairing command.
  ///
  /// In en, this message translates to:
  /// **'Copy command'**
  String get pairRunnerCopyCommand;

  /// No description provided for @pairRunnerExpires.
  ///
  /// In en, this message translates to:
  /// **'Works once; expires in {left} ({at}).'**
  String pairRunnerExpires(String left, String at);

  /// A pairing token past its 15 minutes.
  ///
  /// In en, this message translates to:
  /// **'Expired before it was used.'**
  String get pairRunnerExpired;

  /// Makes another pairing token for the same name once the first expired.
  ///
  /// In en, this message translates to:
  /// **'New token'**
  String get pairRunnerNewToken;

  /// The engine URL of the pairing command is loopback and no runner URL is set.
  ///
  /// In en, this message translates to:
  /// **'This address only works on this Mac. Set the address runners reach the engine at; pairing commands carry it.'**
  String get pairRunnerLoopback;

  /// Title of the storage view.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storageTitle;

  /// No description provided for @storageChecked.
  ///
  /// In en, this message translates to:
  /// **'Measured {when}'**
  String storageChecked(String when);

  /// Reads the storage report again.
  ///
  /// In en, this message translates to:
  /// **'Measure again'**
  String get storageRefresh;

  /// Opens the free-up-space sheet.
  ///
  /// In en, this message translates to:
  /// **'Free up space…'**
  String get storageFreeUp;

  /// No description provided for @storageHero.
  ///
  /// In en, this message translates to:
  /// **'{reclaimable} of {used} reclaimable'**
  String storageHero(String reclaimable, String used);

  /// Under the storage hero.
  ///
  /// In en, this message translates to:
  /// **'Pinned artifacts, releases not over yet and the newest builds of each flavor are always kept.'**
  String get storageHeroBody;

  /// No description provided for @storageFreed.
  ///
  /// In en, this message translates to:
  /// **'Freed {size}'**
  String storageFreed(String size);

  /// No description provided for @storageFreedPart.
  ///
  /// In en, this message translates to:
  /// **'{category} {count}'**
  String storageFreedPart(String category, int count);

  /// Panel title.
  ///
  /// In en, this message translates to:
  /// **'What the engine keeps'**
  String get storageCategoriesTitle;

  /// Panel title.
  ///
  /// In en, this message translates to:
  /// **'Artifacts by app and flavor'**
  String get storageFlavorsTitle;

  /// Column label.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get storageColumnCategory;

  /// Column label.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get storageColumnItems;

  /// Column label.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get storageColumnUsed;

  /// Column label.
  ///
  /// In en, this message translates to:
  /// **'Reclaimable'**
  String get storageColumnReclaimable;

  /// Column label.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get storageColumnProject;

  /// Column label.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get storageColumnApp;

  /// Column label.
  ///
  /// In en, this message translates to:
  /// **'Flavor'**
  String get storageColumnFlavor;

  /// Column label.
  ///
  /// In en, this message translates to:
  /// **'Builds'**
  String get storageColumnBuilds;

  /// No description provided for @storageBuilds.
  ///
  /// In en, this message translates to:
  /// **'{builds, plural, =1{1 build} other{{builds} builds}} · {artifacts} files'**
  String storageBuilds(int builds, int artifacts);

  /// Storage category.
  ///
  /// In en, this message translates to:
  /// **'Artifacts'**
  String get storageArtifacts;

  /// Storage category.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get storageLogs;

  /// Storage category.
  ///
  /// In en, this message translates to:
  /// **'Worktrees'**
  String get storageWorktrees;

  /// Storage category.
  ///
  /// In en, this message translates to:
  /// **'Mirrors'**
  String get storageMirrors;

  /// Storage category.
  ///
  /// In en, this message translates to:
  /// **'Flutter SDKs'**
  String get storageFlutter;

  /// No description provided for @storageArtifactsRule.
  ///
  /// In en, this message translates to:
  /// **'Builds past the newest {keep} of each flavor'**
  String storageArtifactsRule(int keep);

  /// No description provided for @storageLogsRule.
  ///
  /// In en, this message translates to:
  /// **'Logs of jobs older than {days} days'**
  String storageLogsRule(int days);

  /// What housekeeping frees.
  ///
  /// In en, this message translates to:
  /// **'Worktrees of finished jobs'**
  String get storageWorktreesRule;

  /// What housekeeping frees.
  ///
  /// In en, this message translates to:
  /// **'Mirrors of repositories that are no longer projects'**
  String get storageMirrorsRule;

  /// What housekeeping frees.
  ///
  /// In en, this message translates to:
  /// **'SDKs in XPath\'s cache that no project pins'**
  String get storageFlutterRule;

  /// Panel title.
  ///
  /// In en, this message translates to:
  /// **'Retention'**
  String get storageRetentionTitle;

  /// Retention panel.
  ///
  /// In en, this message translates to:
  /// **'Logs past their days go every night; artifacts only with Free up space.'**
  String get storageRetentionBody;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Builds kept per flavor'**
  String get storageKeepPerFlavor;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Days of logs'**
  String get storageLogDays;

  /// Saves the retention.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get storageSaveRetention;

  /// Invalid retention.
  ///
  /// In en, this message translates to:
  /// **'Both need a whole number of at least 1.'**
  String get storageRetentionInvalid;

  /// Title of the free-up-space sheet.
  ///
  /// In en, this message translates to:
  /// **'Free up space'**
  String get freeSpaceTitle;

  /// Free-up-space sheet.
  ///
  /// In en, this message translates to:
  /// **'XPath deletes what retention gives back in the categories you pick. It cannot be undone.'**
  String get freeSpaceBody;

  /// Closes the free-up-space sheet.
  ///
  /// In en, this message translates to:
  /// **'Keep everything'**
  String get freeSpaceKeep;

  /// No description provided for @freeSpaceConfirm.
  ///
  /// In en, this message translates to:
  /// **'Free {size}'**
  String freeSpaceConfirm(String size);

  /// Sidebar row under the selected project.
  ///
  /// In en, this message translates to:
  /// **'Runs'**
  String get sidebarRuns;

  /// Title of the runs page.
  ///
  /// In en, this message translates to:
  /// **'Runs'**
  String get runsTitle;

  /// Runs filter: no workflow picked.
  ///
  /// In en, this message translates to:
  /// **'All workflows'**
  String get runsAllWorkflows;

  /// Runs filter: no state picked.
  ///
  /// In en, this message translates to:
  /// **'All states'**
  String get runsAllStates;

  /// Runs page with nothing to show.
  ///
  /// In en, this message translates to:
  /// **'No run matches.'**
  String get runsNone;

  /// Recent runs of a project without runs.
  ///
  /// In en, this message translates to:
  /// **'Nothing has run yet. Dispatch a workflow to see its runs here.'**
  String get runsNoneYet;

  /// Overview section.
  ///
  /// In en, this message translates to:
  /// **'Recent runs'**
  String get runsRecent;

  /// Opens the runs page.
  ///
  /// In en, this message translates to:
  /// **'All runs'**
  String get runsAll;

  /// Sidebar row under the selected project.
  ///
  /// In en, this message translates to:
  /// **'Workflows'**
  String get sidebarWorkflows;

  /// Title of the workflow builder.
  ///
  /// In en, this message translates to:
  /// **'Workflows'**
  String get workflowsTitle;

  /// No description provided for @workflowsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String workflowsVersion(int version);

  /// Marks a workflow the engine made.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get workflowsBuiltin;

  /// Subtitle of a new workflow.
  ///
  /// In en, this message translates to:
  /// **'Not saved yet'**
  String get workflowsDraft;

  /// Subtitle part while the YAML differs from what is saved.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get workflowsUnsaved;

  /// Accessible label of the workflow picker.
  ///
  /// In en, this message translates to:
  /// **'Workflow'**
  String get workflowsPick;

  /// Starts a new workflow.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get workflowsNew;

  /// Opens a YAML file as a new workflow.
  ///
  /// In en, this message translates to:
  /// **'Import…'**
  String get workflowsImport;

  /// Opens the dispatch sheet on the open workflow.
  ///
  /// In en, this message translates to:
  /// **'Run…'**
  String get workflowsRun;

  /// Saves the YAML to a file.
  ///
  /// In en, this message translates to:
  /// **'Export…'**
  String get workflowsExport;

  /// Saves a new version of the workflow.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get workflowsSave;

  /// Saves the document as a new workflow, asking for its name.
  ///
  /// In en, this message translates to:
  /// **'Save as…'**
  String get workflowsSaveAs;

  /// Shown while a built-in workflow is open.
  ///
  /// In en, this message translates to:
  /// **'Built-in workflows cannot be changed. Save as… keeps your edits as a workflow of your own.'**
  String get workflowsBuiltinHint;

  /// No description provided for @workflowsSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved {name}, version {version}.'**
  String workflowsSaved(String name, int version);

  /// No description provided for @workflowsExported.
  ///
  /// In en, this message translates to:
  /// **'Exported to {path}.'**
  String workflowsExported(String path);

  /// Label of the visual editor's graph.
  ///
  /// In en, this message translates to:
  /// **'Pipeline'**
  String get workflowsPipeline;

  /// Label of the YAML view.
  ///
  /// In en, this message translates to:
  /// **'YAML'**
  String get workflowsYaml;

  /// Label of the issue list.
  ///
  /// In en, this message translates to:
  /// **'Issues'**
  String get workflowsIssuesLabel;

  /// The engine is checking the YAML.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get workflowsChecking;

  /// The engine found no issue.
  ///
  /// In en, this message translates to:
  /// **'Valid'**
  String get workflowsValid;

  /// No description provided for @workflowsIssues.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 issue} other{{count} issues}}'**
  String workflowsIssues(int count);

  /// The engine could not check the YAML.
  ///
  /// In en, this message translates to:
  /// **'Not checked · engine away'**
  String get workflowsUnchecked;

  /// Shown over the visual editor while the YAML cannot be read.
  ///
  /// In en, this message translates to:
  /// **'The visual editor waits until the YAML reads as a workflow. Fix the issues in the YAML.'**
  String get workflowsShapeLocked;

  /// Adds a stage at the end.
  ///
  /// In en, this message translates to:
  /// **'Add stage'**
  String get workflowsAddStage;

  /// No description provided for @workflowsNewStage.
  ///
  /// In en, this message translates to:
  /// **'stage-{number}'**
  String workflowsNewStage(int number);

  /// Adds a job to a stage.
  ///
  /// In en, this message translates to:
  /// **'Add job'**
  String get workflowsAddJob;

  /// Selects the workflow's own fields.
  ///
  /// In en, this message translates to:
  /// **'Workflow'**
  String get workflowsWorkflow;

  /// No description provided for @workflowsSteps.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No steps} =1{1 step} other{{count} steps}}'**
  String workflowsSteps(int count);

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get workflowsName;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get workflowsDescription;

  /// Chip: the workflow locks the project (lock: project).
  ///
  /// In en, this message translates to:
  /// **'One run at a time per project'**
  String get workflowsLock;

  /// Under the lock chip: what lock: project changes besides one run at a time.
  ///
  /// In en, this message translates to:
  /// **'It also makes the production flavors the default when a dispatch names none.'**
  String get workflowsLockHint;

  /// Label of the workflow's inputs.
  ///
  /// In en, this message translates to:
  /// **'Inputs'**
  String get workflowsInputs;

  /// Under the list of inputs.
  ///
  /// In en, this message translates to:
  /// **'A dispatch sets them; the steps read them as inputs.<name>.'**
  String get workflowsInputsHint;

  /// The workflow declares no input.
  ///
  /// In en, this message translates to:
  /// **'No inputs'**
  String get workflowsNoInputs;

  /// No description provided for @workflowsStage.
  ///
  /// In en, this message translates to:
  /// **'Stage {number}'**
  String workflowsStage(int number);

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Stage name'**
  String get workflowsStageName;

  /// Moves a stage, job or step one place earlier.
  ///
  /// In en, this message translates to:
  /// **'Move earlier'**
  String get workflowsMoveEarlier;

  /// Moves a stage, job or step one place later.
  ///
  /// In en, this message translates to:
  /// **'Move later'**
  String get workflowsMoveLater;

  /// Removes the selected stage.
  ///
  /// In en, this message translates to:
  /// **'Remove stage'**
  String get workflowsRemoveStage;

  /// Removes the selected job.
  ///
  /// In en, this message translates to:
  /// **'Remove job'**
  String get workflowsRemoveJob;

  /// Removes a step.
  ///
  /// In en, this message translates to:
  /// **'Remove step'**
  String get workflowsRemoveStep;

  /// Inspector label of a job.
  ///
  /// In en, this message translates to:
  /// **'Job'**
  String get workflowsJob;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Job id'**
  String get workflowsJobId;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Job name'**
  String get workflowsJobName;

  /// Placeholder of the job name field.
  ///
  /// In en, this message translates to:
  /// **'The id with the matrix values by default'**
  String get workflowsJobNameHint;

  /// Field label of an if expression.
  ///
  /// In en, this message translates to:
  /// **'If'**
  String get workflowsCondition;

  /// Placeholder of an if field.
  ///
  /// In en, this message translates to:
  /// **'platform == \'ios\''**
  String get workflowsConditionHint;

  /// Label of a job's matrix.
  ///
  /// In en, this message translates to:
  /// **'Matrix'**
  String get workflowsMatrix;

  /// Matrix axis: not repeated over.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get workflowsAxisNone;

  /// Matrix axis: values the dispatch picks.
  ///
  /// In en, this message translates to:
  /// **'From dispatch'**
  String get workflowsAxisDispatch;

  /// Matrix axis: values written out.
  ///
  /// In en, this message translates to:
  /// **'Listed'**
  String get workflowsAxisList;

  /// Placeholder of the listed flavors field.
  ///
  /// In en, this message translates to:
  /// **'prod, dev'**
  String get workflowsAxisValuesHint;

  /// Label of a job's capabilities.
  ///
  /// In en, this message translates to:
  /// **'Capabilities'**
  String get workflowsCapabilities;

  /// Label of a job's steps.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get workflowsStepsLabel;

  /// Adds a step to the job.
  ///
  /// In en, this message translates to:
  /// **'Add step'**
  String get workflowsAddStep;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Step type'**
  String get workflowsStepKind;

  /// Field label: the approval in front of a step.
  ///
  /// In en, this message translates to:
  /// **'Gate'**
  String get workflowsGate;

  /// A step without a gate.
  ///
  /// In en, this message translates to:
  /// **'No gate'**
  String get workflowsNoGate;

  /// Label of the values a step is told.
  ///
  /// In en, this message translates to:
  /// **'With'**
  String get workflowsWith;

  /// Placeholder of a with value.
  ///
  /// In en, this message translates to:
  /// **'YAML value'**
  String get workflowsWithHint;

  /// Closes a toast.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get toastDismiss;

  /// Undoes what a toast reports.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get toastUndo;

  /// No description provided for @workflowsRemovedStage.
  ///
  /// In en, this message translates to:
  /// **'Removed stage {name}'**
  String workflowsRemovedStage(String name);

  /// No description provided for @workflowsRemovedJob.
  ///
  /// In en, this message translates to:
  /// **'Removed job {id}'**
  String workflowsRemovedJob(String id);

  /// No description provided for @workflowsRemovedStep.
  ///
  /// In en, this message translates to:
  /// **'Removed step {kind}'**
  String workflowsRemovedStep(String kind);

  /// Adds an input to the workflow.
  ///
  /// In en, this message translates to:
  /// **'Add input'**
  String get workflowsAddInput;

  /// Tooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove input'**
  String get workflowsRemoveInput;

  /// No description provided for @workflowsRemovedInput.
  ///
  /// In en, this message translates to:
  /// **'Removed input {name}'**
  String workflowsRemovedInput(String name);

  /// Field label of an input.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get workflowsInputName;

  /// An input name the engine does not take.
  ///
  /// In en, this message translates to:
  /// **'Letters, digits and _, starting with a letter or _.'**
  String get workflowsInputNameInvalid;

  /// Field label of an input.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get workflowsInputType;

  /// An input without a type.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get workflowsInputTypeAny;

  /// Input type.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get workflowsInputTypeString;

  /// Input type.
  ///
  /// In en, this message translates to:
  /// **'On or off'**
  String get workflowsInputTypeBoolean;

  /// Input type.
  ///
  /// In en, this message translates to:
  /// **'Choice'**
  String get workflowsInputTypeChoice;

  /// Input type.
  ///
  /// In en, this message translates to:
  /// **'JSON'**
  String get workflowsInputTypeJson;

  /// Input type: a release of the project.
  ///
  /// In en, this message translates to:
  /// **'Release'**
  String get workflowsInputTypeRelease;

  /// A dispatch must give the input.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get workflowsInputRequired;

  /// Field label of an input.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get workflowsInputDescription;

  /// Field label: the values of a choice.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get workflowsInputOptions;

  /// Placeholder: options apart with commas.
  ///
  /// In en, this message translates to:
  /// **'internal, beta, production'**
  String get workflowsInputOptionsHint;

  /// Field label of an input.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get workflowsInputDefault;

  /// An input without a default.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get workflowsInputNoDefault;

  /// Menu of the open workflow.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get workflowsMore;

  /// Opens the versions of the workflow.
  ///
  /// In en, this message translates to:
  /// **'Versions…'**
  String get workflowsVersions;

  /// Renames the workflow.
  ///
  /// In en, this message translates to:
  /// **'Rename…'**
  String get workflowsRename;

  /// Title of the name dialog when renaming.
  ///
  /// In en, this message translates to:
  /// **'Rename the workflow'**
  String get workflowsRenameTitle;

  /// Archives the workflow.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get workflowsArchive;

  /// Unarchives the workflow.
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get workflowsUnarchive;

  /// No description provided for @workflowsArchivedToast.
  ///
  /// In en, this message translates to:
  /// **'Archived {name}'**
  String workflowsArchivedToast(String name);

  /// Banner of an archived workflow.
  ///
  /// In en, this message translates to:
  /// **'Archived: kept with its versions and runs, and not offered to dispatch.'**
  String get workflowsArchivedNote;

  /// No description provided for @workflowsArchivedName.
  ///
  /// In en, this message translates to:
  /// **'{name} (archived)'**
  String workflowsArchivedName(String name);

  /// Deletes the workflow.
  ///
  /// In en, this message translates to:
  /// **'Delete…'**
  String get workflowsDelete;

  /// No description provided for @workflowsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String workflowsDeleteTitle(String name);

  /// Delete confirmation.
  ///
  /// In en, this message translates to:
  /// **'Its versions go with it.'**
  String get workflowsDeleteVersions;

  /// Delete confirmation.
  ///
  /// In en, this message translates to:
  /// **'A workflow that ran cannot be deleted; archive it instead.'**
  String get workflowsDeleteRan;

  /// Confirms deleting a workflow.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get workflowsDeleteConfirm;

  /// No description provided for @workflowsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted {name}.'**
  String workflowsDeleted(String name);

  /// No description provided for @workflowsRestored.
  ///
  /// In en, this message translates to:
  /// **'Saved version {from} again as version {version} of {name}.'**
  String workflowsRestored(int from, int version, String name);

  /// No description provided for @workflowsVersionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Versions of {name}'**
  String workflowsVersionsTitle(String name);

  /// No description provided for @workflowsVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version {version} · {time}'**
  String workflowsVersionLabel(int version, String time);

  /// The older version of a compare.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get workflowsVersionFrom;

  /// The newer version of a compare.
  ///
  /// In en, this message translates to:
  /// **'to'**
  String get workflowsVersionTo;

  /// No description provided for @workflowsRestoreVersion.
  ///
  /// In en, this message translates to:
  /// **'Restore version {version}'**
  String workflowsRestoreVersion(int version);

  /// Two versions with the same lines.
  ///
  /// In en, this message translates to:
  /// **'No changes.'**
  String get workflowsNoChanges;

  /// Closes a dialog of the builder.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get workflowsClose;

  /// No description provided for @workflowsBuiltinUpdated.
  ///
  /// In en, this message translates to:
  /// **'The built-in {builtin} has a newer version ({latest}); this copy is based on version {base}.'**
  String workflowsBuiltinUpdated(String builtin, int latest, int base);

  /// Compares a copy with its built-in.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get workflowsCompare;

  /// No description provided for @workflowsCompareTitle.
  ///
  /// In en, this message translates to:
  /// **'Compare with {builtin}'**
  String workflowsCompareTitle(String builtin);

  /// No description provided for @workflowsBuiltinChanged.
  ///
  /// In en, this message translates to:
  /// **'What {builtin} changed, version {base} to {latest}'**
  String workflowsBuiltinChanged(String builtin, int base, int latest);

  /// No description provided for @workflowsYouChanged.
  ///
  /// In en, this message translates to:
  /// **'What this copy changed since version {base}'**
  String workflowsYouChanged(int base);

  /// The copy has taken what the built-in changed.
  ///
  /// In en, this message translates to:
  /// **'Mark as up to date'**
  String get workflowsMarkUpToDate;

  /// Title of the template picker.
  ///
  /// In en, this message translates to:
  /// **'Start a new workflow'**
  String get workflowsTemplateTitle;

  /// Tooltip: undoes the last edit (⌘Z).
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get workflowsUndo;

  /// Tooltip: redoes the edit undone (⇧⌘Z).
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get workflowsRedo;

  /// Why Add step is disabled.
  ///
  /// In en, this message translates to:
  /// **'The engine cannot be reached, so its step types are not known. Edit the YAML for now, or try again once it answers.'**
  String get workflowsAddStepUnavailable;

  /// Title of the step type picker.
  ///
  /// In en, this message translates to:
  /// **'Add a step'**
  String get workflowsStepPickerTitle;

  /// Placeholder of the step type search.
  ///
  /// In en, this message translates to:
  /// **'Search step types'**
  String get workflowsStepSearchHint;

  /// Step type picker with no result.
  ///
  /// In en, this message translates to:
  /// **'No step type matches.'**
  String get workflowsStepNoMatch;

  /// A with key the step type needs and the step does not give.
  ///
  /// In en, this message translates to:
  /// **'Needed'**
  String get workflowsKeyNeeded;

  /// A with key left to the step type's default.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get workflowsKeyDefault;

  /// No description provided for @workflowsKeyDefaultValue.
  ///
  /// In en, this message translates to:
  /// **'Default ({value})'**
  String workflowsKeyDefaultValue(String value);

  /// A true with value.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get workflowsOn;

  /// A false with value.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get workflowsOff;

  /// Inspector of a stage.
  ///
  /// In en, this message translates to:
  /// **'Select a job in the pipeline to edit its matrix and steps.'**
  String get workflowsSelectJob;

  /// Title of the name dialog.
  ///
  /// In en, this message translates to:
  /// **'Save as a new workflow'**
  String get workflowsNameTitle;

  /// Name dialog.
  ///
  /// In en, this message translates to:
  /// **'Letters, digits, dots, dashes and underscores; unique in the project.'**
  String get workflowsNameBody;

  /// Name dialog: the name is not one the engine takes.
  ///
  /// In en, this message translates to:
  /// **'Start with a letter or digit; then letters, digits, dots, dashes and underscores, 64 at most.'**
  String get workflowsNameInvalid;

  /// Name dialog: the name is taken.
  ///
  /// In en, this message translates to:
  /// **'The project already has a workflow called {name}.'**
  String workflowsNameTaken(String name);

  /// Closes a dialog.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get workflowsCancel;

  /// Title of the discard dialog.
  ///
  /// In en, this message translates to:
  /// **'Discard unsaved changes?'**
  String get workflowsDiscardTitle;

  /// No description provided for @workflowsDiscardBody.
  ///
  /// In en, this message translates to:
  /// **'The changes to {name} are not saved.'**
  String workflowsDiscardBody(String name);

  /// Closes the discard dialog.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get workflowsKeepEditing;

  /// Drops the unsaved changes.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get workflowsDiscard;

  /// Sidebar row and app menu item.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get sidebarSettings;

  /// Title.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Subtitle.
  ///
  /// In en, this message translates to:
  /// **'XPath on this Mac and the engine it shows.'**
  String get settingsSubtitle;

  /// Section label.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// Row label: the app's version.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get settingsAppVersion;

  /// Row label: the engine the app shows.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get settingsEngine;

  /// Row label.
  ///
  /// In en, this message translates to:
  /// **'Engine version'**
  String get settingsEngineVersion;

  /// The engine's version.
  ///
  /// In en, this message translates to:
  /// **'{version} (API v{api})'**
  String settingsEngineVersionValue(String version, String api);

  /// Row label.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get settingsConnection;

  /// Row label: the LaunchAgent.
  ///
  /// In en, this message translates to:
  /// **'Engine on this Mac'**
  String get settingsLoginItem;

  /// Login item status.
  ///
  /// In en, this message translates to:
  /// **'Runs at login'**
  String get settingsAgentEnabled;

  /// Login item status.
  ///
  /// In en, this message translates to:
  /// **'Not running'**
  String get settingsAgentNotRegistered;

  /// Login item status.
  ///
  /// In en, this message translates to:
  /// **'Waiting for you in Login Items'**
  String get settingsAgentRequiresApproval;

  /// Login item status.
  ///
  /// In en, this message translates to:
  /// **'Not in this build'**
  String get settingsAgentNotFound;

  /// Login item status.
  ///
  /// In en, this message translates to:
  /// **'Needs macOS 13'**
  String get settingsAgentUnsupported;

  /// A value that could not be read.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get settingsUnknown;

  /// Section label.
  ///
  /// In en, this message translates to:
  /// **'Runners'**
  String get settingsRunners;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Runner URL'**
  String get settingsRunnerUrl;

  /// Lead of the runner URL section.
  ///
  /// In en, this message translates to:
  /// **'The address runners on other machines reach this engine at, for example a Tailscale name. Every pairing command carries it.'**
  String get settingsRunnerUrlBody;

  /// No runner URL.
  ///
  /// In en, this message translates to:
  /// **'No runner URL is set: pairing commands use the address this app reaches the engine at.'**
  String get settingsRunnerUrlUnset;

  /// No description provided for @settingsRunnerUrlSet.
  ///
  /// In en, this message translates to:
  /// **'Runners reach the engine at {url}.'**
  String settingsRunnerUrlSet(String url);

  /// Under the runner URL field.
  ///
  /// In en, this message translates to:
  /// **'Runners paired already keep their address; pair them again to move them. See docs/guide/runners.md, Reaching the engine.'**
  String get settingsRunnerUrlNote;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get settingsRunnerUrlSave;

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get settingsRunnerUrlClear;

  /// Section label.
  ///
  /// In en, this message translates to:
  /// **'GitHub'**
  String get settingsGitHub;

  /// Lead of the GitHub section.
  ///
  /// In en, this message translates to:
  /// **'The engine adds projects, keeps its copies and pushes with one GitHub token, shared by every project. The token stays on the engine machine and is checked with GitHub before it is saved.'**
  String get settingsGitHubBody;

  /// Status.
  ///
  /// In en, this message translates to:
  /// **'The engine has no GitHub token, so it cannot add projects.'**
  String get settingsGitHubMissing;

  /// Status.
  ///
  /// In en, this message translates to:
  /// **'Connected to GitHub as {login}.'**
  String settingsGitHubConnected(String login);

  /// Status without a login.
  ///
  /// In en, this message translates to:
  /// **'Connected to GitHub.'**
  String get settingsGitHubConnectedNoLogin;

  /// Status.
  ///
  /// In en, this message translates to:
  /// **'GitHub refused the engine\'s token: {message}'**
  String settingsGitHubRejected(String message);

  /// Status.
  ///
  /// In en, this message translates to:
  /// **'GitHub could not check the engine\'s token: {message}'**
  String settingsGitHubUnreachable(String message);

  /// While the status loads.
  ///
  /// In en, this message translates to:
  /// **'Asking GitHub…'**
  String get settingsGitHubChecking;

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Token'**
  String get settingsGitHubToken;

  /// Field hint.
  ///
  /// In en, this message translates to:
  /// **'ghp_… or github_pat_… with the repo scope'**
  String get settingsGitHubTokenHint;

  /// Saves the pasted token.
  ///
  /// In en, this message translates to:
  /// **'Check and save'**
  String get settingsGitHubSave;

  /// Takes gh auth token on the engine machine.
  ///
  /// In en, this message translates to:
  /// **'Import from GitHub CLI'**
  String get settingsGitHubImport;

  /// Note under the buttons.
  ///
  /// In en, this message translates to:
  /// **'Import runs gh auth token on the engine machine; log in there with gh auth login first.'**
  String get settingsGitHubImportNote;

  /// Forgets the engine's token.
  ///
  /// In en, this message translates to:
  /// **'Remove token'**
  String get settingsGitHubRemove;

  /// Remove GitHub token confirmation.
  ///
  /// In en, this message translates to:
  /// **'Remove the GitHub token?'**
  String get settingsGitHubRemoveTitle;

  /// Remove GitHub token confirmation.
  ///
  /// In en, this message translates to:
  /// **'The engine can no longer clone, tag or open pull requests, so jobs that need GitHub fail.'**
  String get settingsGitHubRemoveStops;

  /// Remove GitHub token confirmation.
  ///
  /// In en, this message translates to:
  /// **'The token stays valid on GitHub; revoke it there if it leaked.'**
  String get settingsGitHubRemoveKeeps;

  /// A failed request.
  ///
  /// In en, this message translates to:
  /// **'Not saved: {message}'**
  String settingsGitHubFailed(String message);

  /// Section label.
  ///
  /// In en, this message translates to:
  /// **'Command line tool'**
  String get settingsCli;

  /// Section label and button.
  ///
  /// In en, this message translates to:
  /// **'Remove XPath'**
  String get settingsRemove;

  /// Lead of the remove section.
  ///
  /// In en, this message translates to:
  /// **'Stops the engine on this Mac, revokes its runners and removes the xp link. Your repositories are never touched.'**
  String get settingsRemoveBody;

  /// Opens the confirmation sheet.
  ///
  /// In en, this message translates to:
  /// **'Remove XPath…'**
  String get settingsRemoveButton;

  /// Title of the sheet.
  ///
  /// In en, this message translates to:
  /// **'Remove XPath from this Mac?'**
  String get removeTitle;

  /// Lead of the sheet.
  ///
  /// In en, this message translates to:
  /// **'XPath revokes every runner of the engine on this Mac while it still runs, stops the engine and takes it off the login items, and removes the xp link it made. Your repositories are not touched.'**
  String get removeBody;

  /// Option.
  ///
  /// In en, this message translates to:
  /// **'Also delete engine data'**
  String get removeDeleteData;

  /// What the option deletes.
  ///
  /// In en, this message translates to:
  /// **'The database, builds, logs and copies in {folders}.'**
  String removeDeleteDataNote(String folders);

  /// Option.
  ///
  /// In en, this message translates to:
  /// **'Also delete Keychain items'**
  String get removeDeleteKeychain;

  /// What the option deletes.
  ///
  /// In en, this message translates to:
  /// **'The engine\'s secrets and credentials and the app\'s engine tokens (Keychain services ly.abdurahman.xpath…).'**
  String get removeDeleteKeychainNote;

  /// Closes the sheet.
  ///
  /// In en, this message translates to:
  /// **'Keep XPath'**
  String get removeKeep;

  /// Starts removing.
  ///
  /// In en, this message translates to:
  /// **'Remove XPath'**
  String get removeConfirm;

  /// Step.
  ///
  /// In en, this message translates to:
  /// **'Revoke runners'**
  String get removeStepRunners;

  /// Step.
  ///
  /// In en, this message translates to:
  /// **'Stop the engine'**
  String get removeStepEngine;

  /// Step.
  ///
  /// In en, this message translates to:
  /// **'Remove the xp link'**
  String get removeStepCli;

  /// Step.
  ///
  /// In en, this message translates to:
  /// **'Delete engine data'**
  String get removeStepData;

  /// Step.
  ///
  /// In en, this message translates to:
  /// **'Delete Keychain items'**
  String get removeStepKeychain;

  /// Step result.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No runners to revoke} =1{1 runner revoked} other{{count} runners revoked}}'**
  String removeRunnersRevoked(int count);

  /// Step result.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No items} =1{1 item deleted} other{{count} items deleted}}'**
  String removeKeychainDeleted(int count);

  /// Step result.
  ///
  /// In en, this message translates to:
  /// **'The engine did not stop in time.'**
  String get removeEngineStillRunning;

  /// Step result.
  ///
  /// In en, this message translates to:
  /// **'Kept: the engine did not stop.'**
  String get removeDataKept;

  /// Title when done.
  ///
  /// In en, this message translates to:
  /// **'XPath is removed from this Mac'**
  String get removeDoneTitle;

  /// Lead when done.
  ///
  /// In en, this message translates to:
  /// **'Move XPath to the Trash to finish.'**
  String get removeDoneBody;

  /// Final button.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash and quit'**
  String get removeTrashAndQuit;

  /// When the Trash refused.
  ///
  /// In en, this message translates to:
  /// **'XPath could not move itself to the Trash. Quit, then drag XPath from Applications to the Trash.'**
  String get removeTrashFailed;

  /// Quits without the Trash.
  ///
  /// In en, this message translates to:
  /// **'Quit XPath'**
  String get removeQuit;

  /// Add project without a GitHub token.
  ///
  /// In en, this message translates to:
  /// **'The engine has no GitHub token, so it cannot add a project from GitHub. Connect GitHub below; a project on another git host needs none.'**
  String get addProjectNoGitHub;

  /// Add project with a refused token.
  ///
  /// In en, this message translates to:
  /// **'GitHub refuses the engine\'s token, so it cannot add a project from GitHub. Save a new one below.'**
  String get addProjectGitHubRejected;

  /// Onboarding: what a first release needs, up front (U5a).
  ///
  /// In en, this message translates to:
  /// **'A first release needs four things: this engine, a GitHub token for projects on GitHub, the project\'s folder, and the store credentials of each flavor. After these three steps, the app shows what is left.'**
  String get onboardingFirstRelease;

  /// Title of the setup checklist (U5a).
  ///
  /// In en, this message translates to:
  /// **'Get to a first build'**
  String get setupTitle;

  /// No description provided for @setupProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} done'**
  String setupProgress(int done, int total);

  /// Setup step: always done in the shell.
  ///
  /// In en, this message translates to:
  /// **'The engine runs'**
  String get setupEngine;

  /// Setup step.
  ///
  /// In en, this message translates to:
  /// **'Connect GitHub'**
  String get setupGitHub;

  /// Setup step body.
  ///
  /// In en, this message translates to:
  /// **'The engine reads and releases projects on GitHub with a token. A project on another git host needs none.'**
  String get setupGitHubBody;

  /// Setup step.
  ///
  /// In en, this message translates to:
  /// **'Add a project'**
  String get setupProject;

  /// Setup step body.
  ///
  /// In en, this message translates to:
  /// **'The folder of a Flutter app\'s repository. The engine scans it for apps and flavors.'**
  String get setupProjectBody;

  /// Setup step.
  ///
  /// In en, this message translates to:
  /// **'Add credentials'**
  String get setupCredentials;

  /// No description provided for @setupCredentialsBody.
  ///
  /// In en, this message translates to:
  /// **'Every flavor needs the keys that sign and upload it. {flavor} has none yet.'**
  String setupCredentialsBody(String flavor);

  /// Setup step.
  ///
  /// In en, this message translates to:
  /// **'Set the store ids'**
  String get setupStoreIds;

  /// No description provided for @setupStoreIdsBody.
  ///
  /// In en, this message translates to:
  /// **'A build is uploaded to the app id its flavor has in Firebase or App Store Connect. {flavor} is missing one.'**
  String setupStoreIdsBody(String flavor);

  /// Setup step, shown when no runner can run a build.
  ///
  /// In en, this message translates to:
  /// **'Find a machine for the builds'**
  String get setupRunners;

  /// Opens docs/guide/runners.md.
  ///
  /// In en, this message translates to:
  /// **'Runners guide'**
  String get setupRunnersGuide;

  /// Opens the runners page.
  ///
  /// In en, this message translates to:
  /// **'Runners'**
  String get setupRunnersOpen;

  /// Setup step.
  ///
  /// In en, this message translates to:
  /// **'Run a first build'**
  String get setupFirstBuild;

  /// Setup step body.
  ///
  /// In en, this message translates to:
  /// **'An unsigned build needs no credential or store id: it shows the project builds before signing is set up.'**
  String get setupFirstBuildBody;

  /// Dispatches the built-in smoke-build.
  ///
  /// In en, this message translates to:
  /// **'Try an unsigned build'**
  String get setupTrySmoke;

  /// Opens the dispatch sheet.
  ///
  /// In en, this message translates to:
  /// **'Dispatch…'**
  String get setupDispatch;

  /// Opens the GitHub token in Settings.
  ///
  /// In en, this message translates to:
  /// **'Connect…'**
  String get setupConnect;

  /// Opens Add project.
  ///
  /// In en, this message translates to:
  /// **'Add…'**
  String get setupAdd;

  /// Opens the credentials of a flavor.
  ///
  /// In en, this message translates to:
  /// **'Assign…'**
  String get setupAssign;

  /// Opens the store ids of a flavor.
  ///
  /// In en, this message translates to:
  /// **'Set ids…'**
  String get setupSetIds;

  /// On a finding a credential fixes: opens the flavor's credentials.
  ///
  /// In en, this message translates to:
  /// **'Add credential…'**
  String get scanAddCredential;

  /// On a finding with a file: copies its path.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get scanCopyPath;

  /// Toast after Copy path.
  ///
  /// In en, this message translates to:
  /// **'Path copied'**
  String get scanPathCopied;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
