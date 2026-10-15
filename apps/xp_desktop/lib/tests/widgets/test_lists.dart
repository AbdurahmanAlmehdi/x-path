import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The tests of a run that changed or still fail, new failures first: new
/// failures, failing in the baseline too, fixed since the baseline, and in
/// the baseline but not reported.
class TestLists extends StatelessWidget {
  const new({required this.response, super.key});

  final TestRunResponse response;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final diff = response.run.diff;
    final cases = {for (final test in response.tests) test.ref: test};
    final newRefs = diff.newFailures.toSet();
    final still = [
      for (final test in response.tests)
        if (!newRefs.contains(test.ref)) test,
    ];
    TestRow failure(TestRef ref) {
      final test = cases[ref];
      return TestRow(
        ref: ref,
        status: XpStatus.jobFailed,
        label: test?.status == TestStatus.errored
            ? l10n.testsErrored
            : l10n.testsFailed,
        message: test?.message,
      );
    }

    final sections = [
      if (diff.newFailures.isNotEmpty)
        _Section(
          title: l10n.testsNewFailuresTitle,
          count: diff.newFailures.length,
          rows: [for (final ref in diff.newFailures) failure(ref)],
        ),
      if (still.isNotEmpty)
        _Section(
          title: l10n.testsStillFailingTitle,
          count: diff.stillFailing,
          rows: [for (final test in still) failure(test.ref)],
        ),
      if (diff.fixed.isNotEmpty)
        _Section(
          title: l10n.testsFixedTitle,
          count: diff.fixed.length,
          rows: [
            for (final ref in diff.fixed)
              TestRow(
                ref: ref,
                status: XpStatus.jobSucceeded,
                label: l10n.testsFixed,
              ),
          ],
        ),
      if (diff.missing.isNotEmpty)
        _Section(
          title: l10n.testsMissingTitle,
          count: diff.missing.length,
          rows: [
            for (final ref in diff.missing)
              TestRow(
                ref: ref,
                status: XpStatus.appstoreUnknown,
                label: l10n.testsMissing,
              ),
          ],
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (response.total > response.tests.length) ...[
          XpMessage(
            XpStatus.scanInfo,
            l10n.testsTruncated(
              formatCount(response.tests.length),
              formatCount(response.total),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (sections.isEmpty)
          XpMessage(XpStatus.jobSucceeded, l10n.testsAllPassed)
        else
          for (final (index, section) in sections.indexed) ...[
            if (index > 0) const SizedBox(height: 16),
            section,
          ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const new({required this.title, required this.count, required this.rows});

  final String title;
  final int count;
  final List<TestRow> rows;

  @override
  Widget build(BuildContext context) => XpPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              XpSectionLabel(title),
              const SizedBox(width: 6),
              XpCode(formatCount(count), color: context.xpColors.textSecondary),
            ],
          ),
        ),
        for (final row in rows) ...[const XpHairline(), row],
      ],
    ),
  );
}

/// One test: its status, full name and file, and what went wrong.
class TestRow extends StatelessWidget {
  const new({
    required this.ref,
    required this.status,
    required this.label,
    this.message,
    super.key,
  });

  final TestRef ref;
  final XpStatus status;
  final String label;

  /// What went wrong, for a failure.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final type = context.xpType;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              XpStatusIcon(status),
              const SizedBox(width: 6),
              Expanded(
                child: Tooltip(
                  message: ref.name,
                  child: Text(
                    ref.name,
                    overflow: TextOverflow.ellipsis,
                    style: type.bodyStrong.copyWith(color: colors.textPrimary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                ref.suite,
                overflow: TextOverflow.ellipsis,
                style: type.code.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: type.caption.copyWith(
                  color: colors.onContainer(status.pair),
                ),
              ),
            ],
          ),
          if (message case final message? when message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colors.surfaceSunken,
                borderRadius: BorderRadius.circular(context.xpRadii.md),
              ),
              child: SelectableText(
                message.trimRight(),
                minLines: 1,
                maxLines: 6,
                style: type.code.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
