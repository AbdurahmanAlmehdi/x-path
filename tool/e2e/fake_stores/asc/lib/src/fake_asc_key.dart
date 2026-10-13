/// Which kind of API key a fake key is.
enum FakeAscKeyKind {
  /// A team key: its token names the issuer (`iss`).
  team,

  /// An individual key: its token says `sub: user` and has no issuer.
  individual,
}

/// An API key the fake server accepts tokens of.
class FakeAscKey {
  /// Creates a key that signs with the private half of [publicKeyPem].
  const new({
    required this.keyId,
    required this.publicKeyPem,
    this.issuerId = fakeAscIssuerId,
    this.kind = FakeAscKeyKind.team,
  });

  /// The `kid` of its tokens.
  final String keyId;

  /// The public key, as a `-----BEGIN PUBLIC KEY-----` block.
  final String publicKeyPem;

  /// The issuer of a team key's tokens.
  final String issuerId;

  /// Team or individual.
  final FakeAscKeyKind kind;
}

/// The issuer id of the test key.
const fakeAscIssuerId = '69a6de70-1111-47e3-e053-5b8c7c11a4d1';

/// The key id of the test key.
const fakeAscKeyId = 'TESTKEY001';

/// A P-256 key made for tests with
/// `openssl ecparam -name prime256v1 -genkey -noout | openssl pkcs8 -topk8
/// -nocrypt`. It signs nothing real: only the fake server trusts it.
const fakeAscPrivateKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgDqwoNwrx2XcWxGNR
xlqT5PFGPmtLtlLgxyPvkxfgWdShRANCAARgUJlnazpKJ3ZSdfrFk75r9bPqDoyt
x959ND1iDCln/9nHlnUl91yIzp5nFC6w8HO4EVC3sM7OydkfpHvFxb4z
-----END PRIVATE KEY-----
''';

/// The public half of [fakeAscPrivateKeyPem], from `openssl ec -pubout`.
const fakeAscPublicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEYFCZZ2s6Sid2UnX6xZO+a/Wz6g6M
rcfefTQ9YgwpZ//Zx5Z1JfdciM6eZxQusPBzuBFQt7DOzsnZH6R7xcW+Mw==
-----END PUBLIC KEY-----
''';

/// The test key as a team key of the fake server.
const fakeAscTestKey = FakeAscKey(
  keyId: fakeAscKeyId,
  publicKeyPem: fakeAscPublicKeyPem,
);
