import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  test('exceptions describe themselves', () {
    expect(const JobException('x').toString(), 'JobException: x');
    expect(
      const JobNotFoundException('job_1').toString(),
      'JobNotFoundException: There is no job job_1.',
    );
    expect(const JobNotFoundException('job_1').id, 'job_1');
    expect(const JobStateException('y').toString(), 'JobStateException: y');
    expect(const JobInvalidException('z').toString(), 'JobInvalidException: z');
    expect(const JobNotFoundException('j'), isA<JobException>());
  });
}
