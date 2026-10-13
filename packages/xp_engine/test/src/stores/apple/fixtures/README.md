# altool output fixtures

Text that `xcrun altool --upload-package` prints, for the tests of the output parser and of
`upload.appStore`. Where each file comes from:

- `altool27_missing_key.txt` and `altool27_missing_ipa.txt` were captured from altool 27.0.5
  (Xcode 27.1) on 2026-10-13 with deliberately wrong arguments, so nothing reached Apple. Only the
  working directory was replaced by `/work/job`.
- The others are reconstructed from the markers the reference scripts grep for
  (`ERROR:|Validation failed|UPLOAD FAILED|VALIDATION_ERROR`) and from Apple's published ITMS
  messages. `altool_closed_train_exit0.txt` is the shape of the incident the plan names: a rejection
  (closed train, ITMS-90186) after which altool exited 0. No real upload was made to capture them.
