import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/git/git_models.dart';
import 'package:xp_engine/src/git/git_service.dart';
import 'package:xp_engine/src/versioning/build_counter.dart';
import 'package:xp_engine/src/versioning/release_model.dart';
import 'package:xp_engine/src/versioning/store_build_numbers.dart';

/// Hands out build numbers (D-11).
///
/// The number is one more than the largest of what the stores have, what the
/// tags of the release model record and what the app's counter holds. It is
/// allocated when a release is dispatched and never returned, so numbers have
/// gaps after a failed job and never repeat.
class BuildNumberAllocator {
  /// Creates an allocator. [_clock] tells how old what the stores said is.
  new({
    required this._counters,
    required this._stores,
    required this._git,
    this._clock = const SystemClock(),
  });

  final BuildCounterRepository _counters;
  final StoreBuildNumbers _stores;
  final GitService _git;
  final Clock _clock;

  /// How long [peek] trusts what the stores said: a preview asks again
  /// after a pause, not on every change of the form.
  static const storeAnswerKept = Duration(minutes: 1);

  /// What the stores last said for each app (its iOS and Android ids), and
  /// when.
  final _storeAnswers = <(String?, String?), (DateTime, StoreBuilds?)>{};

  /// Allocates the next build number of the app at [appPath] in [projectId].
  ///
  /// [mirror] is the project's mirror, fetched by the caller so that its tags
  /// are current. If the stores cannot be asked, tags and counter decide
  /// alone; the `buildNumberReuse` guard checks again before the upload.
  ///
  /// Throws an `UnknownAppException` if the project has no such app.
  Future<int> allocate({
    required String projectId,
    required String appPath,
    required GitMirror mirror,
    ReleaseModel model = const ReleaseModel(),
    TagScope scope = const TagScope(),
    String? iosBundleId,
    String? androidAppId,
  }) async => await _counters.allocate(
    projectId: projectId,
    appPath: appPath,
    seed: await _seed(mirror, model, scope, iosBundleId, androidAppId),
  );

  /// The number [allocate] would hand out now, without handing it out: what
  /// a dry run of a dispatch shows. What the stores said in the last
  /// [storeAnswerKept] is used again rather than asked anew.
  ///
  /// Throws an `UnknownAppException` if the project has no such app.
  Future<int> peek({
    required String projectId,
    required String appPath,
    required GitMirror mirror,
    ReleaseModel model = const ReleaseModel(),
    TagScope scope = const TagScope(),
    String? iosBundleId,
    String? androidAppId,
  }) async => await _counters.peek(
    projectId: projectId,
    appPath: appPath,
    seed: await _seed(
      mirror,
      model,
      scope,
      iosBundleId,
      androidAppId,
      fresh: false,
    ),
  );

  /// The largest build number the stores and the tags know.
  Future<int> _seed(
    GitMirror mirror,
    ReleaseModel model,
    TagScope scope,
    String? iosBundleId,
    String? androidAppId, {
    bool fresh = true,
  }) async {
    final store = await _storeBuilds(iosBundleId, androidAppId, fresh: fresh);
    var seed = store?.highest ?? 0;
    for (final tag in await _git.listTags(mirror)) {
      final build = model.parseTag(tag.name, scope: scope)?.build ?? 0;
      if (build > seed) seed = build;
    }
    return seed;
  }

  /// What the stores say about the app, asked now unless [fresh] is false
  /// and they were asked in the last [storeAnswerKept].
  Future<StoreBuilds?> _storeBuilds(
    String? iosBundleId,
    String? androidAppId, {
    required bool fresh,
  }) async {
    final key = (iosBundleId, androidAppId);
    final now = _clock.now();
    if (_storeAnswers[key] case (final at, final builds)
        when !fresh && now.difference(at) < storeAnswerKept) {
      return builds;
    }
    final builds = await _stores.lookup(
      iosBundleId: iosBundleId,
      androidAppId: androidAppId,
    );
    _storeAnswers[key] = (now, builds);
    return builds;
  }
}
