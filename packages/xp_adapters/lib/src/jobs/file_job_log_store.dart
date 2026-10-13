import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// Job logs as files: `<root>/<jobId>/<ordinal>-<kind>.log`, one JSON object
/// per line, in the form of a `LogLineFrame` (`seq`, `step`, `at`, `stream`,
/// `text`).
///
/// A line is appended with one write, so another reader sees whole lines or,
/// at worst, a torn last line, which it skips.
class FileJobLogStore implements JobLogStore {
  /// Creates a store under [root].
  const new(this.root);

  /// The directory that holds one folder per job.
  final String root;

  static final _fileName = RegExp(r'^(\d+)-.*\.log$');

  @override
  Future<JobLogWriter> open({
    required String jobId,
    required int ordinal,
    required String kind,
  }) async {
    final directory = Directory(p.join(root, jobId));
    await directory.create(recursive: true);
    final safeKind = kind.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
    final path = p.join(directory.path, '$ordinal-$safeKind.log');
    return _FileLogWriter(path, File(path).openSync(mode: FileMode.append));
  }

  @override
  Stream<LogLineFrame> read(String jobId, {int after = 0}) async* {
    for (final file in _files(jobId)) {
      final lines = file
          .openRead()
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter());
      await for (final text in lines) {
        final line = _parse(text);
        if (line != null && line.seq > after) yield line;
      }
    }
  }

  @override
  Future<int> head(String jobId) async {
    for (final file in _files(jobId).reversed) {
      LogLineFrame? last;
      await for (final text
          in file
              .openRead()
              .transform(const Utf8Decoder(allowMalformed: true))
              .transform(const LineSplitter())) {
        last = _parse(text) ?? last;
      }
      if (last != null) return last.seq;
    }
    return 0;
  }

  /// The log files of the job, in step order.
  List<File> _files(String jobId) {
    final directory = Directory(p.join(root, jobId));
    if (!directory.existsSync()) return const [];
    final files =
        <(int, File)>[
          for (final entity in directory.listSync())
            if (entity is File)
              if (_fileName.firstMatch(p.basename(entity.path))
                  case final match?)
                (int.parse(match.group(1)!), entity),
        ]..sort(
          (a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2.path.compareTo(b.$2.path),
        );
    return [for (final (_, file) in files) file];
  }

  /// The line [text] holds, or `null` if it is torn or not a log line.
  static LogLineFrame? _parse(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return null;
      final frame = LogFrame.fromJson(json);
      return frame is LogLineFrame ? frame : null;
    } on FormatException {
      return null;
    }
  }
}

class _FileLogWriter implements JobLogWriter {
  new(this.path, this._file);

  @override
  final String path;
  final RandomAccessFile _file;

  @override
  Future<void> write(LogLineFrame line) async =>
      _file.writeStringSync('${jsonEncode(line.toJson())}\n');

  @override
  Future<void> close() => _file.close();
}
