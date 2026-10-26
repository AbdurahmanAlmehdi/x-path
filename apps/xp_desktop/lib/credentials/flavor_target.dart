import 'package:xp_api/xp_api.dart';

/// A flavor of an app of the project, as a credential assignment addresses
/// it.
typedef FlavorTarget = ({String app, String appName, String flavor});

/// The flavors of [project], `default` for an app without flavors.
List<FlavorTarget> flavorTargets(Project project) => [
  for (final app in project.profile.apps)
    if (app.flavors.isEmpty)
      (app: app.path, appName: app.name, flavor: 'default')
    else
      for (final flavor in app.flavors)
        (app: app.path, appName: app.name, flavor: flavor.name),
];
