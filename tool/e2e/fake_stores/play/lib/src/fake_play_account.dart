/// A service account the fake server accepts assertions of.
class FakePlayAccount {
  /// Creates an account whose assertions verify with [publicKeyPem].
  const new({required this.clientEmail, required this.publicKeyPem});

  /// The `iss` of its assertions.
  final String clientEmail;

  /// The public key, as a `-----BEGIN PUBLIC KEY-----` block.
  final String publicKeyPem;
}

/// The email of the test service account.
const fakePlayClientEmail = 'xpath-test@xpath-test.iam.gserviceaccount.com';

/// The key id of the test service account.
const fakePlayPrivateKeyId = 'testkey0001';

/// A 2048-bit RSA key made for tests with
/// `openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048` and
/// `openssl pkcs8 -topk8 -nocrypt`. It signs nothing real: only the fake
/// server trusts it.
const fakePlayPrivateKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC3y2gfqPyPMaKG
ks7CYjQucWjAZojz4eYiZdF418BPNLCLehjXZ7POSR3hUj4R71GGGO7dPOOPEEIZ
LdVR79VpYMjY0vgoy8/GZ8AB+FqCD2vF/ivXVLy1UIJZ4fXEnXDzKFGg9REg9VXD
UpLgsbC1tPXtnW+H68DI7W79wf5q1ZDXi3yoSIj0MW/poJTxKpNj55EYbqDj5Tkd
EDxEsCfSGooeX1TgcOU2m7+E2hUTBqKMo1hVBqWeSfBbQfbJ6iDYFSjIktmD95S4
PmVotwypFq3VjhFzt+RwH5VjGr+euz/hSNn5dSvOhU4YnDmvbFY29oZzX0kuOSVS
FisM6p2lAgMBAAECggEAQN9O1T30Ryah0xYmXH4FJQ9qhd6rIEnvzNxbX2fnvQ0/
8zsZYY587KbqIQnCVto90DMkvHotZ+W5LuH6lX0tupAq1D1C0kN+Bu2/2/IpIBcJ
V00rdEm4gdb063zSHp/jqi/lAAcAEL4Hk3Wl2iFd2gUReNlE8JjJ5yHHN1It1s8J
golm/kDJE+KEyel6cAI0aIN+UDiGJNKk7saGD87k7f9DVw3F8crZkLFvOBQn8VgB
5wRiVUriVprYaDP/rLrrD6ybpV0Xm1gqla/9xKFlaM/7vnpDvI3Bd9bdaOqs2y5m
NK+/4nj9E/ckvFyojv3/Qx3HAXfQP4yHHicjJ4E2UQKBgQDlCEshRw/HKU+H8IhU
3FWMjd/CoGfYaJtAyj2HFlsE/gqlGI8vi8U4TJIWHYAuxIL//YjpOzbA5u8o5DMI
i+PoB2OKrkxYSf2GzGHc9S3KuAFT39eXiMjFQ519MWu/+rsiNbKf2mvWHZF+JKuV
OJbFA868n2pZUaesD+xG0hzezwKBgQDNb4MvKQETXtRaT8o/LfgVBBHpm6zCwZPK
APpoFcw1O94feYQ3OD3xZsA4/ceYPwVkVFWxhy8eBsH6YijUHcTL7qqs0mu5Ibh4
+/2bZBiS4gRYsW4HobLlNbZRCUQpO1DM76Yc4UX8hoqf4jeuj6Pft+cW/rArlfPl
Pe7pmeL5SwKBgQDaLmxj5y5ArDn3Zkx5iux0WTMwVV6X6g78Sa0TY1iSCPBbFmpR
APWADHGeX7wc0Vd6RiyHAsHGQjjS25FCMwGJqIBLPH++G75JC6qus2JMG74oCLV4
xfV89kyxVsMuv8xFaqIfZhQUhVZ0tLpADQiT5myrg7HsJL12TDTpwn9+QQKBgQCo
rCNIqGESt2yhThvfbe3fy3ytkrzxFyEx3UW8ChGlr6b7rrkI4auyNcwjvvKPJUdX
Dgth/H2KKMBBxTCCoIKBck8+IHKECZS9+SBL4o5uoxYwgFW3/GK24Tf1JyeItwPr
j+SSl7/vy8Or7IANWjCRshwR/EFHOBKNqSEtOcVrKwKBgFgJTvurnwU0TCXc84hv
A2OibEVPXxWniNUk5/CdxNE9H1egB67IA6e6jIxr1oztE9T99m0mVzZkxs2AsINn
hvsODX5qQbj7opEsYunvxJVRWgCcQXUwyRBMboLjZRakSHBtV/dgfhna+VtMEmu0
BgU7NENupJ1xI+L1VR7Z2ITv
-----END PRIVATE KEY-----
''';

/// The public half of [fakePlayPrivateKeyPem], from `openssl rsa -pubout`.
const fakePlayPublicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAt8toH6j8jzGihpLOwmI0
LnFowGaI8+HmImXReNfATzSwi3oY12ezzkkd4VI+Ee9Rhhju3TzjjxBCGS3VUe/V
aWDI2NL4KMvPxmfAAfhagg9rxf4r11S8tVCCWeH1xJ1w8yhRoPURIPVVw1KS4LGw
tbT17Z1vh+vAyO1u/cH+atWQ14t8qEiI9DFv6aCU8SqTY+eRGG6g4+U5HRA8RLAn
0hqKHl9U4HDlNpu/hNoVEwaijKNYVQalnknwW0H2yeog2BUoyJLZg/eUuD5laLcM
qRat1Y4Rc7fkcB+VYxq/nrs/4UjZ+XUrzoVOGJw5r2xWNvaGc19JLjklUhYrDOqd
pQIDAQAB
-----END PUBLIC KEY-----
''';

/// Another key, which the fake server does not know: assertions signed with
/// it fail.
const fakePlayOtherPrivateKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQCuBG3sBxS3h9eO
yEpaqYpbCbnQK3W7ghhjkJAzpze5VOEj30HXWJHYh0KOjpdfQ7WkGMbRVwZf7qV/
bU2es1Hqq6EraGM4wCb5nOYzGzLBEc/k36V6f/yzCoQKZkzA1w7v0KPaJaPH4+I/
HzUvAUMOlmoTukKa2w5m3FsldE9u0UGZrT6j4jbzgrJhhzCdc7xi2mts9KmCNVzk
4MNLipk8b74+mbzb6L6/m8j+iGQ5PXcJEQEZHttKWWsyDCl7ilZeoWPS+0ssjbRw
3xCIx50PBe1AtKcomsJGehxgFcYOvClnpTTbiqdXeO3i4fnlvW5xdmX73BPqNHlu
UGjizWiTAgMBAAECggEAECN9BkzJ0ROaHDXbH3llyXencfT14EP6exFnLkMt2dRT
ZP5Jnu0p6Yjx1ULIKx+ecu+RUMzfXHpHgv/iGPvMdxUfx2TQ/uxjMPcqKkc1d85t
F27ea/P+vaQWBtjh+Wh4jCkvaQXgoKMz0mLUjd1yGKI+iEHX94ClX0jEcz7MNxyt
62fX9sWK+oHyUbjMMTjfYDve+LLLmfq47Nn/J+/XIoSOle3yJk+M1RYbZf25cUPs
56QVqG/V/D/1CzxK28QFZZAEHZ5hnFb84vP+4M/VzUbtKlNMizlqseDz1iO0hU81
JfXPrgRPERgIxLjr1EtrFimVB/vVx/wo5ezyoi3uAQKBgQDZ66zrCciFvIfQbbrL
CLvw9VbEBsE91VzYM2FJ1iMOx/4dWeZ5f0w735DEJ9fAxIoG5ujerISocxOx0HdL
ICUBUoy54bjZPIN7XPaEbLoQIpZNNNXAFbGTRoiCNVn/7utwwydXzeRf1X/E8rK4
fR07525CbEMOCi6aSZM/c8GPEwKBgQDMbM+URWChoOmpx4a8QuC1kECMq/W+3rN/
6ONL43Y8xamZtm5aWRYE0/UYtvgYrH5GymxQDzQVhbtvSRic/FaKo+cawLenJVZo
K1+q0pEwYhYPsYw6cptvYzD2G+1HOADNUOMMfJd982VT3iuxuzX/wt1LrTaO8DL8
dG9NWyRwgQKBgQCqTsdbANBXxFmYCMmc93x5+iMPHABV5LOku7Li05meaaotIh8/
AL+BY11uD31MR81fS4Le05DxXM4df0Bb1AlXmT4l30RpciOHe8WlBJv9FCrGt+39
KncXFF6G9E8b94rFG59Zva0nQGGUd+A40n7QXDQNcTKOfGKjbbDIPB0fRQKBgQDF
BFGC+uJIo8bPJEdMhb///IjZipmLXSLuMctuRkicBXyRcmsklBtOh+D98sllLkl9
fHWrKxvtajfc5zvbgK7/azu+YuIdKzT9rF/FSK85TC8q7NjTM8VuMtDrQLsMGoNb
XYuVazat4rhTfhnqbx1545pX5xZf6EubV7Q1f5O9AQKBgQCnYwzfPdx0/1yMHL1a
8UOVGwbYfJQDdv5igbZYyJJRQ1bBrPn92II8/eZurrVSJ4P0KMh+5sKk67v0mCVf
WN8Ho22qG3J5zdxcAKTtXkjP8I9XHG0YD5lrP1PE9Cr5IYJMth0WpIUEsJAB7FL+
4L0U8P2bL2OJb5wisJCPadN/rw==
-----END PRIVATE KEY-----
''';

/// The test account.
const fakePlayTestAccount = FakePlayAccount(
  clientEmail: fakePlayClientEmail,
  publicKeyPem: fakePlayPublicKeyPem,
);
