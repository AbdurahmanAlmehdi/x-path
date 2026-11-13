import 'package:xp_api/xp_api.dart';

/// What a mutating route needs (ADR 0017).
final class RouteAccess {
  /// The route needs [permission]; refusing says the token cannot [what].
  const new needs(Permission this.permission, this.what);

  /// The route needs no permission beyond a token: it changes nothing, or
  /// its handler decides who may, for the reason [what].
  const new open(this.what) : permission = null;

  /// The permission the route needs, or `null` for an [RouteAccess.open]
  /// route.
  final Permission? permission;

  /// What the route does, as in "a viewer cannot [what]", or why it is open.
  final String what;
}

/// What a route missing from [routePermissions] needs: it is closed, as a
/// new route is to runners (ADR 0011).
const unlistedRouteAccess = RouteAccess.needs(
  Permission.administer,
  'use a route the engine does not list',
);

/// What every route that is not `GET` needs, by `METHOD /path` as the route
/// was registered (ADR 0017's role matrix).
///
/// A test walks the router and fails on a mutating route missing here; one
/// that is missing all the same needs [unlistedRouteAccess].
const routePermissions = <String, RouteAccess>{
  // Projects.
  'POST /projects': .needs(Permission.administer, 'add a project'),
  'PATCH /projects/<id>': .needs(Permission.administer, 'change a project'),
  'DELETE /projects/<id>': .needs(Permission.administer, 'remove a project'),
  'POST /projects/<id>/scan': .needs(Permission.develop, 'scan a project'),
  'PUT /projects/<id>/gates': .needs(
    Permission.release,
    'change the gates of a project',
  ),

  // Jobs, runs and artifacts.
  'POST /jobs/<id>/cancel': .needs(Permission.develop, 'cancel a job'),
  'POST /jobs/<id>/resume': .needs(Permission.develop, 'resume a job'),
  'POST /runs/<id>/cancel': .needs(Permission.develop, 'cancel a run'),
  'POST /runs/<id>/rerun-failed': .needs(
    Permission.develop,
    'run failed jobs again',
  ),
  'POST /runs/<id>/run-again': .needs(Permission.develop, 'run a run again'),
  'POST /artifacts/<id>/pin': .needs(Permission.develop, 'pin an artifact'),
  'POST /artifacts/<id>/unpin': .needs(Permission.develop, 'unpin an artifact'),

  // Workflows.
  'POST /workflows/validate': .open('it checks a document and keeps nothing'),
  'POST /projects/<id>/workflows/validate': .open(
    'it checks a document and keeps nothing',
  ),
  'POST /projects/<id>/workflows': .needs(
    Permission.develop,
    'create a workflow',
  ),
  'PUT /projects/<id>/workflows/<workflowId>': .needs(
    Permission.develop,
    'save a workflow',
  ),
  'PATCH /projects/<id>/workflows/<workflowId>': .needs(
    Permission.develop,
    'change a workflow',
  ),
  'DELETE /projects/<id>/workflows/<workflowId>': .needs(
    Permission.develop,
    'delete a workflow',
  ),
  'POST /projects/<id>/workflows/<workflowId>/dispatch': .needs(
    Permission.develop,
    'dispatch a workflow',
  ),

  // Approvals.
  'POST /approvals/<id>/approve': .needs(Permission.decideApproval, 'approve'),
  'POST /approvals/<id>/deny': .needs(Permission.decideApproval, 'deny'),

  // Releases. Asking the stores again and requesting a new build, a merge,
  // a rollout change or a patch move dispatch gated workflows, like a
  // dispatch: they need `develop`, so an agent may still ask (as `xp mcp`'s
  // `request_rollout` does), and the gate waits for a releaser's approval.
  'POST /releases/<id>/abandon': .needs(
    Permission.release,
    'abandon a release',
  ),
  'POST /releases/<id>/builds': .needs(
    Permission.develop,
    'start a new build of a release',
  ),
  'POST /releases/<id>/merge': .needs(Permission.develop, 'merge a release'),
  'POST /releases/<id>/patches/<number>/<action>': .needs(
    Permission.develop,
    'change a patch',
  ),
  'POST /releases/<id>/refresh': .needs(
    Permission.develop,
    'refresh a release',
  ),
  'POST /releases/<id>/rollout': .needs(Permission.develop, 'change a rollout'),
  'POST /releases/<id>/stores/<store>/status': .needs(
    Permission.release,
    'set the status of a store',
  ),
  'PUT /releases/<id>/texts': .needs(
    Permission.release,
    'set the texts of a release',
  ),

  // Credentials and the GitHub token.
  'POST /credentials': .needs(Permission.administer, 'add a credential'),
  'PATCH /credentials/<credentialId>': .needs(
    Permission.administer,
    'rename a credential',
  ),
  'PUT /credentials/<credentialId>': .needs(
    Permission.administer,
    'replace a credential',
  ),
  'DELETE /credentials/<credentialId>': .needs(
    Permission.administer,
    'delete a credential',
  ),
  'POST /credentials/<credentialId>/verify': .needs(
    Permission.administer,
    'check a credential',
  ),
  'PUT /projects/<id>/credentials': .needs(
    Permission.administer,
    'save a credential',
  ),
  'PUT /projects/<id>/flavors/<flavor>/credentials/<kind>': .needs(
    Permission.administer,
    'assign a credential',
  ),
  'DELETE /projects/<id>/flavors/<flavor>/credentials/<kind>': .needs(
    Permission.administer,
    'unassign a credential',
  ),
  'POST /projects/<id>/flavors/<flavor>/distribution-certificate': .needs(
    Permission.administer,
    'create a distribution certificate',
  ),
  'POST /projects/<id>/credentials/<credentialId>/verify': .needs(
    Permission.administer,
    'check a credential',
  ),
  'DELETE /projects/<id>/credentials/<credentialId>': .needs(
    Permission.administer,
    'remove a credential',
  ),
  'PUT /github-token': .needs(Permission.administer, 'set the GitHub token'),
  'POST /github-token/import': .needs(
    Permission.administer,
    'import the GitHub token',
  ),
  'DELETE /github-token': .needs(
    Permission.administer,
    'remove the GitHub token',
  ),

  // Runners and storage.
  'POST /runners/pair': .open('it needs no token: a pairing token pairs'),
  'POST /runners/pairing-tokens': .needs(
    Permission.administer,
    'pair a runner',
  ),
  'POST /runners/<id>/revoke': .needs(Permission.administer, 'revoke a runner'),
  'PUT /runners/jobs/<id>/artifacts/<name>': .open(
    'only the runner that holds the job uploads (ADR 0011)',
  ),
  'PUT /settings/runner-url': .needs(
    Permission.administer,
    'set the runner URL',
  ),
  'POST /storage/free': .open(
    'anyone sees what a dry run would free; the service lets only an admin '
    'delete',
  ),
  'PUT /storage/retention': .needs(
    Permission.administer,
    'change the retention',
  ),

  // People and tokens.
  'POST /people': .needs(Permission.administer, 'add a person'),
  'PATCH /people/<id>': .needs(Permission.administer, 'change a person'),
  'DELETE /people/<id>': .needs(Permission.administer, 'remove a person'),
  'POST /tokens': .open('any app or web token makes tokens for its person'),
  'DELETE /tokens/<id>': .open(
    "a token revokes its own person's tokens, an admin's any person's",
  ),
};
