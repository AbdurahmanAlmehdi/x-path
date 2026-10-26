/// Where the guide is read: every link the app shows into it is built here,
/// so a test can check each page and anchor exists (U8).
const guideBase =
    'https://github.com/AbdurahmanAlmehdi/x-path/blob/main/docs/guide/';

/// The guide page [page] (`runners.md`), at [anchor] when given.
Uri guideUri(String page, {String? anchor}) =>
    Uri.parse('$guideBase$page${anchor == null ? '' : '#$anchor'}');
