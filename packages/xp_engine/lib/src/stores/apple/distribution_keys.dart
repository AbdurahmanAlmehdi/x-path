/// A new private key and the certificate signing request for it.
typedef DistributionKey = ({String privateKeyPem, String csrPem});

/// Makes the key of a new Apple Distribution certificate (ADR 0014, Phase
/// 4b): an RSA key, PKCS#8 PEM, and a PKCS#10 request signed with it. The key
/// is made on the engine and stays in its secret store, so no machine of the
/// owner has to have a Mac or a keychain to export one from.
///
/// `xp_adapters` has the implementation.
abstract interface class DistributionKeys {
  /// A new key, with a request whose subject is [commonName].
  Future<DistributionKey> generate(String commonName);
}
