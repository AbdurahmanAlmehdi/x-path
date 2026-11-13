import 'package:xp_api/xp_api.dart';

/// The admin that every engine has, as migration v23 makes it.
final owner = Person(
  id: 'per_owner',
  name: 'Owner',
  role: PersonRole.admin,
  createdAt: DateTime.utc(2026),
);

/// A person called after [role], who has it.
Person personWith(PersonRole role) => Person(
  id: 'per_${role.name}',
  name: role.name,
  role: role,
  createdAt: DateTime.utc(2026),
);
