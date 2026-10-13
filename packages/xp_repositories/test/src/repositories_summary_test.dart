import 'package:test/test.dart';
import 'package:xp_repositories/xp_repositories.dart';

void main() {
  test('repositoriesSummary names the client', () {
    expect(repositoriesSummary(), 'xp_repositories over xp_client (API v1)');
  });
}
