/// A pubspec as the Mataa customer app writes it.
String pubspec(String version, {String extra = ''}) =>
    '''
name: mataa_new_app
description: Mataa customer app.
publish_to: none

# Do not edit by hand: ./scripts/ship.sh version writes it.
version: $version

environment:
  sdk: ^3.5.0
dependencies:
  flutter:
    sdk: flutter
  mataa_core:
    git:
      url: https://github.com/mataa/mataa_core.git
      ref: 0123456789abcdef
      version: ignored
$extra''';

/// An `Info.plist` with literal versions, as the customer app keeps them.
String plist(String shortVersion, String build) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>Mataa</string>
	<!-- bumped by XPath -->
	<key>CFBundleShortVersionString</key>
	<string>$shortVersion</string>
	<key>CFBundleVersion</key>
	<string>$build</string>
	<key>LSRequiresIPhoneOS</key>
	<true/>
</dict>
</plist>
''';

/// The `Info.plist` Flutter generates, which follows `--build-name`.
final String flutterPlist = plist(
  r'$(FLUTTER_BUILD_NAME)',
  r'$(FLUTTER_BUILD_NUMBER)',
);
