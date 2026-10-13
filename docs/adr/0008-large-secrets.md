# ADR 0008: Large secrets

- **Status:** Accepted
- **Date:** 2026-10-13
- **Phase:** Follow-up to Phase 4 (supersedes its oversize refusal)

## Context

ADR 0004 stores every macOS secret in the Keychain through `security -i`. That interface reads
one command line of at most 4094 bytes, and Phase 4 refuses a value that does not fit. The
value is base64 (a raw newline would end the command), so the largest secret is about 3 KB.

That is too small for Android keystores (`.jks`, `.keystore`): they are binary, often 2 to 10 KB
or more, and base64 adds a third. The `SecretStore` interface was also text only, so a caller had
to base64 a keystore itself.

## Decision

1. **Large secrets are files.** On macOS a secret whose base64 form is longer than 2,048
   characters (more than 1,536 bytes) is kept in `secrets.enc` in the engine's data directory:
   the same XChaCha20-Poly1305 file that Linux uses (`EncryptedFileSecretStore`). The 2 KB line is
   safely below the 4094-byte limit, which also has to hold the command, the service name, the
   key and the keychain path (the real-Keychain test writes a 1,536-byte value under a 200
   character key).
2. **The file key is in the Keychain.** A `KeychainMasterKeySource` (a `MasterKeySource`, like the
   key file and systemd credential sources on Linux) keeps 32 random bytes as a Keychain item,
   service `ly.abdurahman.xpath.master`, account `secrets-file-key` (ADR 0005). It is created the
   first time a large secret is written. It is never replaced while `secrets.enc` exists: a
   missing key next to a sealed file means secrets locked.
3. **Small secrets stay in the Keychain**, service `ly.abdurahman.xpath.credentials`, as before.
4. **One composite store.** `createSecretStore` returns a `SizeRoutedSecretStore` on macOS:
   - `writeBytes` routes by size, writes the target store, then deletes the key from the other
     one, so a key lives in one place and a secret that grows or shrinks moves;
   - `readBytes` asks the Keychain first, then the file. A key is in both only after a crash
     between the write and the delete of a move; the next write or delete repairs it;
   - `delete` removes the key from both;
   - every operation runs after the previous one, so a move is never seen half done;
   - a Keychain that is locked locks the whole store, because the file key is in it. The store's
     `status` follows either backend's `SecretsLockedException`.
5. **Bytes API.** `SecretStore` gains `readBytes` and `writeBytes`. Text and bytes share one key
   space: `write` stores the UTF-8 bytes, `read` decodes them (and is a `SecretStoreException` for
   a value that is not UTF-8). The Keychain stores base64 of the bytes, which is what it stored
   for text already. The encrypted file keeps a text value as a JSON string and a value that is
   not valid UTF-8 as `{"base64": "..."}`, so files written before this ADR still open.

## Consequences

- Keystores and other binary credentials can be stored without callers encoding them.
- Supersedes the oversize refusal of Phase 4 for the composite store. `KeychainSecretStore` on its
  own still refuses a line over 4094 bytes; the composite never sends it one.
- On macOS the data directory now holds `secrets.enc` when a large secret exists. Backing up the
  data directory without the Keychain does not make the file readable, and resetting the Keychain
  makes the large secrets unrecoverable (they must be entered again).
- A very long key name (over about 1.5 KB) can still exceed the line limit in the Keychain; key
  names are short identifiers, so this is not handled.
