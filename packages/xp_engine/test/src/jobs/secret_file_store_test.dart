import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  test(
    'InMemorySecretFileStore writes files per job and deletes them',
    () async {
      final store = InMemorySecretFileStore();

      final a = await store.write('job_1', 'KEY', 'secret-a');
      final b = await store.write('job_2', 'KEY', 'secret-b');
      await store.deleteAll('job_1');

      expect(a, isNot(b));
      expect(store.files, {b: 'secret-b'});
      expect(store.written, {a: 'secret-a', b: 'secret-b'});
      expect(store.deleted, ['job_1']);
    },
  );
}
