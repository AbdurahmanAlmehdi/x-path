// Readers for the stored JSON of step inputs; all fail with a
// [FormatException] that names the field.

/// The non-empty string at [field], or a [FormatException].
String requiredString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('"$field" must be a non-empty string.');
}

/// The string at [field], or `null` if it is absent.
String? optionalString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('"$field" must be a string.');
}

/// The list of strings at [field]; empty if it is absent.
List<String> stringList(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) return const [];
  if (value is List && value.every((item) => item is String)) {
    return value.cast<String>();
  }
  throw FormatException('"$field" must be a list of strings.');
}

/// The map from strings to strings at [field]; empty if it is absent.
Map<String, String> stringMap(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) return const {};
  if (value is Map && value.values.every((item) => item is String)) {
    return value.cast<String, String>();
  }
  throw FormatException('"$field" must be an object of strings.');
}

/// The boolean at [field]; `false` if it is absent.
bool optionalFlag(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) return false;
  if (value is bool) return value;
  throw FormatException('"$field" must be a boolean.');
}

/// The object at [field], or a [FormatException].
Map<String, dynamic> requiredObject(Map<String, dynamic> json, String field) =>
    optionalObject(json, field) ??
    (throw FormatException('"$field" must be an object.'));

/// The object at [field], or `null` if it is absent.
Map<String, dynamic>? optionalObject(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) return null;
  if (value is Map<String, dynamic>) return value;
  throw FormatException('"$field" must be an object.');
}
