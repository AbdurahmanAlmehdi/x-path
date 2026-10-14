import 'package:xp/src/commands/xp_command.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp/src/output/format.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

/// `xp storage`: what the engine keeps on disk.
XpGroup storageCommand(XpContext context) => XpGroup(
  context,
  'storage',
  'Report disk use, free up space and set the retention.',
  [
    StorageReportCommand(context),
    StorageFreeCommand(context),
    StorageRetentionCommand(context),
  ],
);

/// `xp storage report`.
class StorageReportCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'report';

  @override
  String get description =>
      'Show what the engine keeps and what could be freed.';

  @override
  Future<int> execute(XpClient client) async {
    final report = await client.getStorage();
    emit(report.toJson(), () {
      final total =
          'total: ${formatBytes(report.usedBytes)}, '
          '${formatBytes(report.reclaimableBytes)} can be freed';
      final retention =
          'retention: last ${report.retention.keepPerFlavor} builds per '
          'flavor, ${report.retention.logDays} days of logs';
      final lines = [
        renderTable(
          ['CATEGORY', 'USED', 'FREEABLE', 'ITEMS'],
          [
            for (final category in report.categories)
              [
                category.category.wire,
                formatBytes(category.usedBytes),
                formatBytes(category.reclaimableBytes),
                '${category.items}',
              ],
          ],
        ),
        '',
        total,
        retention,
      ];
      return lines.join('\n');
    });
    return XpExit.ok;
  }
}

/// `xp storage free [--apply]`.
class StorageFreeCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser
      ..addFlag(
        'apply',
        negatable: false,
        help: 'Free the space. Without it, only say how much would be freed.',
      )
      ..addMultiOption(
        'category',
        help: 'Only free this category. Repeatable.',
        allowed: StorageCategory.values.map((category) => category.wire),
      );
  }

  @override
  String get name => 'free';

  @override
  String get description =>
      'Free up space (a dry run unless you pass --apply).';

  @override
  Future<int> execute(XpClient client) async {
    final categories = argResults!.multiOption('category');
    final result = await client.freeStorage(
      FreeSpaceRequest(
        dryRun: !argResults!.flag('apply'),
        categories: categories.isEmpty
            ? null
            : [
                for (final wire in categories)
                  StorageCategory.values.firstWhere((c) => c.wire == wire),
              ],
      ),
    );
    emit(result.toJson(), () {
      final lines = [
        if (result.dryRun)
          'Would free ${formatBytes(result.bytes)} (pass --apply to do it):'
        else
          'Freed ${formatBytes(result.bytes)}:',
        renderTable(
          ['CATEGORY', 'SIZE', 'ITEMS'],
          [
            for (final freed in result.categories)
              [freed.category.wire, formatBytes(freed.bytes), '${freed.items}'],
          ],
        ),
        for (final failure in result.failures) 'could not free: $failure',
      ];
      return lines.join('\n');
    });
    return result.failures.isEmpty ? XpExit.ok : XpExit.failed;
  }
}

/// `xp storage retention [--keep n] [--log-days n]`.
class StorageRetentionCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser
      ..addOption(
        'keep',
        help: 'How many builds to keep per flavor.',
        valueHelp: 'count',
      )
      ..addOption(
        'log-days',
        help: 'How many days of logs to keep.',
        valueHelp: 'days',
      );
  }

  @override
  String get name => 'retention';

  @override
  String get description => 'Show the retention, or change it.';

  @override
  Future<int> execute(XpClient client) async {
    final keep = _count('keep');
    final logDays = _count('log-days');
    var settings = await client.getRetention();
    if (keep != null || logDays != null) {
      settings = await client.setRetention(
        RetentionSettings(
          keepPerFlavor: keep ?? settings.keepPerFlavor,
          logDays: logDays ?? settings.logDays,
        ),
      );
    }
    emit(
      settings.toJson(),
      () =>
          'keep ${settings.keepPerFlavor} builds per flavor, '
          '${settings.logDays} days of logs',
    );
    return XpExit.ok;
  }

  int? _count(String option) {
    final text = argResults!.option(option);
    if (text == null) return null;
    final value = int.tryParse(text);
    if (value == null || value < 0) {
      usageException('--$option must be a non-negative number.');
    }
    return value;
  }
}
