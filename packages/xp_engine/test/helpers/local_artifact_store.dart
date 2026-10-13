import 'package:xp_engine/xp_engine.dart';

/// An [InMemoryArtifactStore] that pretends its files are on disk under
/// `/artifacts`.
class LocalInMemoryArtifactStore extends InMemoryArtifactStore
    implements LocalArtifactStore {
  @override
  String localPath(String path) => '/artifacts/$path';
}
