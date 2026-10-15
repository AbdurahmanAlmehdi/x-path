import 'package:equatable/equatable.dart';

/// The id of the engine on this Mac.
const localEngineId = 'local';

/// The address of the engine on this Mac: `xpd serve` listens on loopback,
/// port 7480, unless told otherwise (and the LaunchAgent the app registers
/// does not tell it otherwise).
final Uri localEngineUrl = Uri.parse('http://127.0.0.1:7480');

/// An engine the app knows: the local one ("This Mac") or a remote one
/// added by URL and token. The token is not part of it: it lives in a
/// `TokenVault`.
class EngineProfile extends Equatable {
  /// Creates a profile.
  const new({required this.id, required this.name, required this.url});

  /// Reads a profile from its JSON form.
  factory fromJson(Map<String, dynamic> json) => EngineProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    url: Uri.parse(json['url'] as String),
  );

  /// The id, [localEngineId] for the engine on this Mac.
  final String id;

  /// What the owner calls it, for example "This Mac" or "mac-mini".
  final String name;

  /// Where it listens, for example `http://127.0.0.1:7480`.
  final Uri url;

  /// Whether this is the engine on this Mac.
  bool get isLocal => id == localEngineId;

  /// The JSON form.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url.toString(),
  };

  @override
  List<Object?> get props => [id, name, url];
}
