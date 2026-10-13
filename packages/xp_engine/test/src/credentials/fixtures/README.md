# Credential check fixtures

- `keytool_*.txt` was captured from `keytool` of OpenJDK 11.0.24 (Corretto) on 2026-10-13 with
  `keytool -list -keystore <file> -storepass:env VAR -alias <alias>` on a keystore made for the
  purpose (a throwaway JKS with the alias `upload`, nothing real). `keytool_list_ok_stdout.txt` is
  what it prints on standard output, `keytool_list_ok.txt` what goes to standard error.
- `altool_list_providers_*.txt` are reconstructed from the markers the reference scripts grep for and
  the messages of altool 27.0.5 (`altool_authentication_failed.txt` in the Apple fixtures was
  captured with wrong arguments). No call was made to Apple: `xcrun altool --list-providers` would
  need a real Apple ID.
- `shorebird_account_whoami_*.json` are reconstructed from the `--json` envelope the Shorebird CLI
  documents (`{"status": "success", "data": ...}`); the fields of `data` are not documented, so the
  parser only reads `email` when it is there.
