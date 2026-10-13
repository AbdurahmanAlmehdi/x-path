import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// A [SnapshotReader] that answers with the bytes the test gives it.
class FakeSnapshotReader implements SnapshotReader {
  /// Creates a reader whose packages hold [snapshot]; `null` means none.
  new([this.snapshot]);

  /// The chunks of the snapshot every package holds.
  List<List<int>>? snapshot;

  /// The kind and the content of every package it was asked about.
  final asked = <(ArtifactKind, List<int>)>[];

  @override
  Future<Stream<List<int>>?> snapshotOf(
    ArtifactKind kind,
    Stream<List<int>> package,
  ) async {
    final bytes = <int>[];
    await package.forEach(bytes.addAll);
    asked.add((kind, bytes));
    final chunks = snapshot;
    return chunks == null ? null : Stream.fromIterable(chunks);
  }
}
