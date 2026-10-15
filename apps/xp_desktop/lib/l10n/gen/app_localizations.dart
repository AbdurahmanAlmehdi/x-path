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
  /// **'The Keychain of this Mac has no token for this engine, or it could not be read. Remove the engine and add it again.'**
  String get engineNoTokenBody;

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
  /// **'Checked every day and before each build. The secrets stay on the engine machine.'**
  String get credentialsSubtitle;

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'Add a project first: credentials belong to its flavors.'**
  String get credentialsNoProject;

  /// Empty state.
  ///
  /// In en, this message translates to:
  /// **'No credentials yet.'**
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

  /// Opens the form for the same flavor and kind.
  ///
  /// In en, this message translates to:
  /// **'Replace…'**
  String get credentialsReplace;

  /// Deletes a credential.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get credentialsDelete;

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

  /// Field label.
  ///
  /// In en, this message translates to:
  /// **'Flavor'**
  String get fieldFlavor;

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
  /// **'{name} · {bytes} bytes'**
  String fieldFileChosen(String name, int bytes);

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
