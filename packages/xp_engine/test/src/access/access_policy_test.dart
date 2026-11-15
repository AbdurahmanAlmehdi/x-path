import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/approval_harness.dart';

const DeviceTokenKind _app = DeviceTokenKind.app;
const DeviceTokenKind _cli = DeviceTokenKind.cli;
const DeviceTokenKind _mcp = DeviceTokenKind.mcp;
const DeviceTokenKind _web = DeviceTokenKind.web;

/// The role matrix of ADR 0017, written out: for each permission and role,
/// the kinds of token that have it. A runner token never has any.
const _matrix = <Permission, Map<PersonRole, Set<DeviceTokenKind>>>{
  Permission.develop: {
    PersonRole.viewer: {},
    PersonRole.developer: {_app, _cli, _mcp, _web},
    PersonRole.releaser: {_app, _cli, _mcp, _web},
    PersonRole.admin: {_app, _cli, _mcp, _web},
  },
  Permission.decideApproval: {
    PersonRole.viewer: {},
    PersonRole.developer: {},
    PersonRole.releaser: {_app, _cli, _web},
    PersonRole.admin: {_app, _cli, _web},
  },
  Permission.release: {
    PersonRole.viewer: {},
    PersonRole.developer: {},
    PersonRole.releaser: {_app, _cli, _web},
    PersonRole.admin: {_app, _cli, _web},
  },
  Permission.administer: {
    PersonRole.viewer: {},
    PersonRole.developer: {},
    PersonRole.releaser: {},
    PersonRole.admin: {_app, _cli, _web},
  },
};

/// A token of [kind] whose person has [role], even a runner token, which
/// never has one in practice: the kind alone must refuse it.
DeviceToken _token(DeviceTokenKind kind, PersonRole role) =>
    DeviceToken(
      id: 'tok_1',
      name: 'n',
      kind: kind,
      hash: 'h',
      createdAt: DateTime.utc(2026),
      personId: 'per_1',
    ).withPerson(
      Person(id: 'per_1', name: 'n', role: role, createdAt: DateTime.utc(2026)),
    );

void main() {
  group('AccessPolicy.allows', () {
    for (final MapEntry(key: permission, value: roles) in _matrix.entries) {
      for (final MapEntry(key: role, value: kinds) in roles.entries) {
        for (final kind in DeviceTokenKind.values) {
          final allowed = kinds.contains(kind);
          test('${allowed ? 'lets' : 'refuses'} a ${role.name} with a '
              '${kind.name} token ${permission.name}', () {
            final token = _token(kind, role);

            expect(AccessPolicy.allows(token, permission), allowed);
            expect(
              AccessPolicy.refusal(token, permission, 'do it'),
              allowed ? isNull : isNotNull,
            );
          });
        }
      }
    }

    test('refuses a runner token, which has no person, everything', () {
      final runner = tokenOf(DeviceTokenKind.runner);

      for (final permission in Permission.values) {
        expect(AccessPolicy.allows(runner, permission), isFalse);
      }
    });

    test('refuses a token whose person was not read', () {
      final unread = DeviceToken(
        id: 'tok_1',
        name: 'n',
        kind: DeviceTokenKind.app,
        hash: 'h',
        createdAt: DateTime.utc(2026),
        personId: 'per_1',
      );

      expect(AccessPolicy.allows(unread, Permission.develop), isFalse);
      expect(
        AccessPolicy.refusal(unread, Permission.develop, 'dispatch'),
        'A token without a person cannot dispatch: it takes the developer '
        'role or higher.',
      );
    });
  });

  group('AccessPolicy.refusal', () {
    test('names the kind when the kind is the reason', () {
      expect(
        AccessPolicy.refusal(
          tokenOf(DeviceTokenKind.mcp),
          Permission.release,
          'abandon a release',
        ),
        'An mcp token cannot abandon a release: only the app, `xp` or the '
        'web dashboard do.',
      );
    });

    test('names the role that is needed when the role is the reason', () {
      expect(
        AccessPolicy.refusal(
          tokenOf(DeviceTokenKind.cli, role: PersonRole.viewer),
          Permission.decideApproval,
          'approve',
        ),
        'A viewer cannot approve: it takes the releaser role or higher.',
      );
    });
  });

  group('AccessPolicy.mayLoosenGates', () {
    for (final role in PersonRole.values) {
      for (final kind in DeviceTokenKind.values) {
        final allowed =
            role == PersonRole.admin && (kind == _app || kind == _web);
        test('is $allowed for a ${role.name} with a ${kind.name} token', () {
          expect(AccessPolicy.mayLoosenGates(_token(kind, role)), allowed);
        });
      }
    }
  });

  group('AccessPolicy.mayCreateToken', () {
    for (final role in PersonRole.values) {
      for (final kind in DeviceTokenKind.values) {
        for (final made in DeviceTokenKind.values) {
          final allowed =
              (kind == _app || kind == _web) && (made == _cli || made == _mcp);
          test('is $allowed for a ${role.name} with a ${kind.name} token '
              'making a ${made.name} token', () {
            expect(
              AccessPolicy.mayCreateToken(_token(kind, role), made),
              allowed,
            );
          });
        }
      }
    }

    test('is false for an app token whose person was not read', () {
      expect(
        AccessPolicy.mayCreateToken(
          DeviceToken(
            id: 'tok_1',
            name: 'n',
            kind: DeviceTokenKind.app,
            hash: 'h',
            createdAt: DateTime.utc(2026),
          ),
          DeviceTokenKind.cli,
        ),
        isFalse,
      );
    });
  });

  group('AccessPolicy.mayManageTokens', () {
    for (final role in PersonRole.values) {
      for (final kind in DeviceTokenKind.values) {
        final allowed = {_app, _cli, _web}.contains(kind);
        test('is $allowed for a ${role.name} with a ${kind.name} token', () {
          expect(AccessPolicy.mayManageTokens(_token(kind, role)), allowed);
        });
      }
    }

    test('is false for a cli token whose person was not read', () {
      expect(
        AccessPolicy.mayManageTokens(
          DeviceToken(
            id: 'tok_1',
            name: 'n',
            kind: DeviceTokenKind.cli,
            hash: 'h',
            createdAt: DateTime.utc(2026),
            personId: 'per_1',
          ),
        ),
        isFalse,
      );
    });
  });

  group('the kind rules of sessions and runners', () {
    for (final kind in DeviceTokenKind.values) {
      test('for a ${kind.name} token', () {
        final token = _token(kind, PersonRole.admin);

        expect(AccessPolicy.mayUseSessionCookie(token), kind == _web);
        expect(AccessPolicy.maySignOut(token), kind == _web);
        expect(AccessPolicy.isRunner(token), kind == DeviceTokenKind.runner);
        expect(AccessPolicy.hasPerson(kind), kind != DeviceTokenKind.runner);
      });
    }
  });

  group('AccessPolicy.aTokenOf', () {
    test('names a kind with its article', () {
      expect(
        [
          for (final kind in DeviceTokenKind.values)
            AccessPolicy.aTokenOf(kind),
        ],
        [
          for (final kind in DeviceTokenKind.values)
            switch (kind) {
              DeviceTokenKind.app => 'An app token',
              DeviceTokenKind.cli => 'A cli token',
              DeviceTokenKind.mcp => 'An mcp token',
              DeviceTokenKind.runner => 'A runner token',
              DeviceTokenKind.web => 'A web token',
            },
        ],
      );
    });
  });

  group('AccessPolicy.mayIssueSignInCode', () {
    for (final role in PersonRole.values) {
      for (final kind in DeviceTokenKind.values) {
        final admin =
            role == PersonRole.admin && {_app, _cli, _web}.contains(kind);
        final own = admin || kind == _app || kind == _cli;
        test('is $own for themself and $admin for others, for a '
            '${role.name} with a ${kind.name} token', () {
          final token = _token(kind, role);

          expect(AccessPolicy.mayIssueSignInCode(token, 'per_1'), own);
          expect(AccessPolicy.mayIssueSignInCode(token, 'per_2'), admin);
        });
      }
    }

    test('is false for an app token whose person was not read', () {
      expect(
        AccessPolicy.mayIssueSignInCode(
          DeviceToken(
            id: 'tok_1',
            name: 'n',
            kind: DeviceTokenKind.app,
            hash: 'h',
            createdAt: DateTime.utc(2026),
            personId: 'per_1',
          ),
          'per_1',
        ),
        isFalse,
      );
    });
  });

  group('AccessPolicy.permissionsOf', () {
    test('lists what the token may do, in order', () {
      expect(AccessPolicy.permissionsOf(_token(_web, PersonRole.admin)), [
        Permission.develop,
        Permission.decideApproval,
        Permission.release,
        Permission.administer,
      ]);
      expect(AccessPolicy.permissionsOf(_token(_mcp, PersonRole.admin)), [
        Permission.develop,
      ]);
      expect(
        AccessPolicy.permissionsOf(_token(_cli, PersonRole.viewer)),
        isEmpty,
      );
    });
  });

  test('each permission needs the role of the matrix', () {
    expect(
      {for (final p in Permission.values) p: p.minimumRole},
      {
        Permission.develop: PersonRole.developer,
        Permission.decideApproval: PersonRole.releaser,
        Permission.release: PersonRole.releaser,
        Permission.administer: PersonRole.admin,
      },
    );
  });
}
