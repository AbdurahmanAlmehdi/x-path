# Step catalogue from existing scripts (research, 2026-10-13)

Sources: C = mataa_new_app/scripts/ship.sh, R = mataa_new_app/scripts/lib/release.sh,
K = mataa_captain/scripts/ship.sh, O = oneavant/mobile-apps/scripts/ship.sh,
L = oneavant/mobile-apps/scripts/lib/common.sh.

## Preflight / guards
- load creds file (C:74-81, O:29-42); uses_shorebird (C:263, refuse patch on non-Shorebird flavor C:270)
- resolve flutter / version pin (C:28-37, L:650-689): fvm vs flutter, pin mismatch, non-Flutter SDK banner
- preflight orchestrator (C:391-452): shorebird binary/yaml, ExportOptions, --build-number with literal plists
- check_env_file (C:375-389): dart-define file exists with required keys non-empty
- repo checks via dart tools (O:281-318); check_signing key.properties (O:320-327)
- resolve_ios_upload_auth (C:319-349, K:266-296, L:298-344): AuthKey_ team vs ApiKey_ individual key, issuer required, Apple ID fallback
- verify_asc_credentials (L:371-387): altool --list-apps / --list-providers before building
- firebase / shorebird auth reports (C:354-370, L:430-521): whoami, sb_api_ token prefix, app_id visible
- guard_prod_source (R:121-147): dirty/untracked inputs, HEAD pushed (or pushed tag R:111-117), no pubspec_overrides.yaml, no `source: path`
- guard_patch_target (R:149-155), guard_new_release_number (R:157-163), assert_version_unreleased (L:143-159, allows second platform)
- check_app_store_train (R:168-188): iTunes lookup, pubspec <= live => closed train (90186)
- check_version_files_in_sync (R:92-103)
- release_kind (O:643-657): native diff refuses patch
- confirm (L:35-49): typed, refuses non-TTY without --yes

## Versioning
- pubspec/plist readers, version_gt (R:25-49, L:56-69); highest_build_number (R:53-65)
- write_version_files (R:70-88, exactly one match per key); run_version (R:336-362)
- build-number ledger with floors (L:86-120, O:73-75); reuse at HEAD for second platform (L:126-137)

## Build
- common args (C:561-570, O:434-453); shorebird defines after `--`
- run_in_worktree (R:196-221) with copied files
- android (C:621-668, O:455-496), ios (C:670-712), Agora strip + re-export (L:585-629)
- patch (C:791-828, O:621-704), R8 mapping archive/fetch/apply/restore (C:467-553)
- freshness marker (C:609-619, L:253-265), artifact discovery (C:586-605, L:543-573)
- verify_compiled_config (K:430-462): strings on libapp.so / App.framework for env host
- stash_artifact (C:575-584, L:271-278)

## Upload / distribute
- firebase appdistribution (C:737-748, L:523-534)
- run_altool (C:752-762, K:559-569): exit 0 can still mean rejection; parse output. L:395-400 misses this.
- ASC upload (C:764-785; K:580 uses `-p @env:` to keep password out of ps)
- dSYM upload via Crashlytics upload-symbols (C:721-735), warn only
- Play: manual

## Record / tag
- write_manifest (R:234-305): sha, deps ref, lock sha256, tool versions, env sha256, artifact sha256
- tag_and_record / patch_tag_name (R:227-330); tag_release `<app>/<flavor>/v...` with tickets (L:223-243)
- tickets from git log GMS-\d+ (O:396-426, L:173-220)

## Housekeeping
- run_clean (R:370-430), run_inspect (R:436-528), artifact summary (L:701)

## Per-app assumptions that become project config
Secrets location and required env keys; Firebase app ids and groups; bundle id + storefront;
Apple team; literal-version plist list; worktree files to copy; Shorebird flavors; prod
flavors; AAB vs APK per flavor; ExportOptions path; entrypoint pattern; artifact paths; tag
scheme (`v` vs `<app>/<flavor>/v`); build-number floors; Flutter version; mappings
dir/bucket; proguard path; dependency-ref regex for manifest; branch model; ticket regex;
custom repo tools (check_env, check_assets, release_kind); Agora strip list; per-flavor ASC
credentials.
