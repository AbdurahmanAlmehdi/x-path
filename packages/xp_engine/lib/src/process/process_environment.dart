/// The names of the environment variables every step process gets from the
/// engine's own environment.
const allowedEnvironmentNames = {
  'PATH',
  'HOME',
  'LANG',
  'TMPDIR',
  'USER',
  'SHELL',
};

/// Variables whose name starts with one of these are allowed too (`LC_ALL`,
/// `LC_CTYPE`, ...).
const allowedEnvironmentPrefixes = ['LC_'];

/// The environment of a step process: nothing but what is allowed.
///
/// A step process never sees the rest of the engine's environment, which may
/// hold tokens. The result has, in this order of precedence:
///
/// 1. [values], which the step declares itself,
/// 2. the variables of [passThrough], which the step declares it needs from
///    the engine's [host] environment (for example `ANDROID_HOME`),
/// 3. the allowed variables of [host] ([allowedEnvironmentNames] and
///    [allowedEnvironmentPrefixes]).
///
/// Secrets are added by the caller, last.
Map<String, String> allowlistedEnvironment(
  Map<String, String> host, {
  Iterable<String> passThrough = const [],
  Map<String, String> values = const {},
}) {
  final extra = passThrough.toSet();
  return {
    for (final entry in host.entries)
      if (allowedEnvironmentNames.contains(entry.key) ||
          allowedEnvironmentPrefixes.any(entry.key.startsWith) ||
          extra.contains(entry.key))
        entry.key: entry.value,
    ...values,
  };
}
