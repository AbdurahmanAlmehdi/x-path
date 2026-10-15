import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';

const _definition = ServiceDefinition(
  label: 'ly.abdurahman.xpath.xpd',
  unitName: 'xpd',
  description: 'XPath engine (xpd)',
  executable: '/opt/xpath/bin/xpd',
  arguments: ['serve', '--data-dir', '/data/x path'],
  path: '/opt/homebrew/bin:/usr/bin',
  logName: 'xpd',
  environment: {'XP_MODE': 'a&b'},
  logDirectory: '/data/service-logs',
  workingDirectory: '/data',
);

void main() {
  group('defaultServicePath', () {
    test('starts with Homebrew on a Mac and ends with the system', () {
      expect(
        defaultServicePath(home: '/Users/me', operatingSystem: 'macos'),
        '/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:'
        '/Users/me/.shorebird/bin:/Users/me/.pub-cache/bin:'
        '/Users/me/fvm/default/bin:/usr/bin:/bin:/usr/sbin:/sbin',
      );
    });

    test('has Linuxbrew where there is no /opt/homebrew', () {
      final path = defaultServicePath(
        home: '/home/me',
        operatingSystem: 'linux',
      );

      expect(path, startsWith('/home/linuxbrew/.linuxbrew/bin:/usr/local/bin'));
      expect(path, isNot(contains('/opt/homebrew')));
      expect(path, contains('/home/me/.shorebird/bin'));
    });
  });

  group('renderLaunchAgentPlist', () {
    test('runs the program at load and keeps it running after a failure', () {
      expect(renderLaunchAgentPlist(_definition), '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>ly.abdurahman.xpath.xpd</string>
  <key>ProgramArguments</key>
  <array>
    <string>/opt/xpath/bin/xpd</string>
    <string>serve</string>
    <string>--data-dir</string>
    <string>/data/x path</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>ThrottleInterval</key>
  <integer>10</integer>
  <key>ExitTimeOut</key>
  <integer>30</integer>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/bin</string>
    <key>XP_MODE</key>
    <string>a&amp;b</string>
  </dict>
  <key>WorkingDirectory</key>
  <string>/data</string>
  <key>StandardOutPath</key>
  <string>/data/service-logs/xpd.out.log</string>
  <key>StandardErrorPath</key>
  <string>/data/service-logs/xpd.err.log</string>
</dict>
</plist>
''');
    });

    test(
      'leaves out the working directory and the logs when there are none',
      () {
        const bare = ServiceDefinition(
          label: 'l',
          unitName: 'u',
          description: 'd',
          executable: '/bin/x',
          arguments: [],
          path: '/bin',
          logName: 'x',
        );

        final plist = renderLaunchAgentPlist(bare);

        expect(plist, isNot(contains('WorkingDirectory')));
        expect(plist, isNot(contains('StandardOutPath')));
      },
    );

    test('writes out the characters XML reads as markup', () {
      const odd = ServiceDefinition(
        label: 'l',
        unitName: 'u',
        description: 'd',
        executable: '/bin/<x>',
        arguments: ['"a"', "it's"],
        path: '/bin',
        logName: 'x',
      );

      final plist = renderLaunchAgentPlist(odd);

      expect(plist, contains('<string>/bin/&lt;x&gt;</string>'));
      expect(plist, contains('<string>&quot;a&quot;</string>'));
      expect(plist, contains('<string>it&apos;s</string>'));
    });
  });

  group('renderSystemdUnit', () {
    test('renders a user unit', () {
      expect(renderSystemdUnit(_definition, scope: ServiceScope.user), '''
[Unit]
Description=XPath engine (xpd)
Documentation=https://xpath.abdurahman.ly
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/xpath/bin/xpd serve --data-dir "/data/x path"
Environment=PATH=/opt/homebrew/bin:/usr/bin
Environment=XP_MODE=a&b
WorkingDirectory=/data
Restart=on-failure
RestartSec=5
KillMode=mixed
TimeoutStopSec=30

[Install]
WantedBy=default.target
''');
    });

    test('renders a system unit that runs as a user of its own', () {
      const system = ServiceDefinition(
        label: 'l',
        unitName: 'xp-runner',
        description: 'Runner',
        executable: '/opt/xp',
        arguments: ['runner', 'start'],
        path: '/usr/bin',
        logName: 'runner',
        runAs: 'xpath',
        stopTimeoutSeconds: 600,
        noRestartExitCodes: [77, 78],
        credential: ServiceCredential(
          name: 'xpath-master-key',
          path: '/etc/xpath/master.cred',
          encrypted: true,
        ),
      );

      final unit = renderSystemdUnit(system, scope: ServiceScope.system);

      expect(unit, contains('User=xpath\n'));
      expect(
        unit,
        contains(
          'LoadCredentialEncrypted=xpath-master-key:/etc/xpath/master.cred\n',
        ),
      );
      expect(unit, contains('RestartPreventExitStatus=77 78\n'));
      expect(unit, contains('TimeoutStopSec=600\n'));
      expect(unit, endsWith('WantedBy=multi-user.target\n'));
    });

    test(
      'a user unit has no User= and a plain credential is LoadCredential',
      () {
        const plain = ServiceDefinition(
          label: 'l',
          unitName: 'u',
          description: 'd',
          executable: '/bin/x',
          arguments: [],
          path: '/bin',
          logName: 'x',
          runAs: 'xpath',
          credential: ServiceCredential(
            name: 'xpath-master-key',
            path: '/k',
            encrypted: false,
          ),
        );

        final unit = renderSystemdUnit(plain, scope: ServiceScope.user);

        expect(unit, isNot(contains('User=')));
        expect(unit, contains('LoadCredential=xpath-master-key:/k\n'));
        expect(unit, isNot(contains('LoadCredentialEncrypted')));
        expect(unit, isNot(contains('RestartPreventExitStatus')));
      },
    );

    test('quotes what systemd would split or read as an escape', () {
      const odd = ServiceDefinition(
        label: 'l',
        unitName: 'u',
        description: 'd',
        executable: '/bin/x',
        arguments: ['', r'a\b', 'say "hi"'],
        path: '/bin',
        logName: 'x',
      );

      final unit = renderSystemdUnit(odd, scope: ServiceScope.user);

      expect(unit, contains(r'ExecStart=/bin/x "" "a\\b" "say \"hi\""'));
    });
  });

  group('escapedForSystemd', () {
    test(r'doubles % and $ in every value that reaches the unit', () {
      const raw = ServiceDefinition(
        label: 'l',
        unitName: 'u',
        description: 'd',
        executable: '/opt/100%/xp',
        arguments: [r'--home=$HOME', 'plain'],
        path: r'/a%h:$PATH',
        logName: 'x',
        environment: {'K': '50%'},
        workingDirectory: '/w%',
        credential: ServiceCredential(
          name: 'xpath-master-key',
          path: '/k%',
          encrypted: true,
        ),
        runAs: 'me',
        noRestartExitCodes: [77],
      );

      final escaped = raw.escapedForSystemd();

      expect(escaped.executable, '/opt/100%%/xp');
      expect(escaped.arguments, [r'--home=$$HOME', 'plain']);
      expect(escaped.path, r'/a%%h:$$PATH');
      expect(escaped.environment, {'K': '50%%'});
      expect(escaped.workingDirectory, '/w%%');
      expect(escaped.credential!.path, '/k%%');
      expect(escaped.credential!.name, 'xpath-master-key');
      expect(escaped.credential!.encrypted, isTrue);
      expect(escaped.runAs, 'me');
      expect(escaped.noRestartExitCodes, [77]);
      expect(escaped.label, 'l');
    });

    test('keeps a definition without a working directory or credential', () {
      final escaped = _definition.escapedForSystemd();

      expect(escaped.credential, isNull);
      expect(escaped.environment, {'XP_MODE': 'a&b'});
    });

    test('has no working directory when there was none', () {
      const bare = ServiceDefinition(
        label: 'l',
        unitName: 'u',
        description: 'd',
        executable: '/bin/x',
        arguments: [],
        path: '/bin',
        logName: 'x',
      );

      expect(bare.escapedForSystemd().workingDirectory, isNull);
    });
  });
}
