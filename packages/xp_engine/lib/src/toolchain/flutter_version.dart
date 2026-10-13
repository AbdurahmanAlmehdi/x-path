final _exactVersion = RegExp(r'^\d+\.\d+\.\d+([-+][\w.]+)?$');
final _pinName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]*$');

/// Whether [version] is an exact Flutter release such as `3.47.6`, the only
/// kind XPath downloads: a channel name builds differently from one day to
/// the next.
///
/// It is also safe to use as a folder name and as a `git` argument.
bool isExactFlutterVersion(String version) => _exactVersion.hasMatch(version);

/// Whether [pin] can be handed to fvm: an exact version or a channel name.
///
/// It starts with a letter or a digit, so it is never read as an option, and
/// has no slash, so it never leaves the folder it names.
bool isFlutterPinName(String pin) => _pinName.hasMatch(pin);
