import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  // D-17, written out again on purpose: every legal move, and nothing else.
  const legal = <(ReleaseState, ReleaseState)>{
    (ReleaseState.draft, ReleaseState.building),
    (ReleaseState.draft, ReleaseState.abandoned),
    (ReleaseState.building, ReleaseState.uploaded),
    (ReleaseState.building, ReleaseState.abandoned),
    (ReleaseState.uploaded, ReleaseState.inReview),
    (ReleaseState.uploaded, ReleaseState.rejected),
    (ReleaseState.uploaded, ReleaseState.approved),
    (ReleaseState.uploaded, ReleaseState.live),
    (ReleaseState.uploaded, ReleaseState.abandoned),
    (ReleaseState.inReview, ReleaseState.rejected),
    (ReleaseState.inReview, ReleaseState.approved),
    (ReleaseState.inReview, ReleaseState.live),
    (ReleaseState.inReview, ReleaseState.abandoned),
    (ReleaseState.rejected, ReleaseState.building),
    (ReleaseState.rejected, ReleaseState.abandoned),
    (ReleaseState.approved, ReleaseState.live),
    (ReleaseState.approved, ReleaseState.abandoned),
    (ReleaseState.live, ReleaseState.merged),
    (ReleaseState.live, ReleaseState.abandoned),
  };

  group('ReleaseStateMachine', () {
    test('has a row for every state', () {
      expect(
        ReleaseStateMachine.transitions.keys,
        unorderedEquals(ReleaseState.values),
      );
    });

    for (final from in ReleaseState.values) {
      for (final to in ReleaseState.values) {
        final allowed = legal.contains((from, to));
        test(
          '${from.wire} -> ${to.wire} is ${allowed ? 'allowed' : 'refused'}',
          () {
            expect(ReleaseStateMachine.canMove(from, to), allowed);
            if (allowed) {
              expect(ReleaseStateMachine.move(from, to), to);
            } else {
              expect(
                () => ReleaseStateMachine.move(from, to),
                throwsA(
                  isA<ReleaseTransitionException>()
                      .having((e) => e.from, 'from', from)
                      .having((e) => e.to, 'to', to),
                ),
              );
            }
          },
        );
      }
    }

    test('a release that is over moves nowhere', () {
      for (final state in ReleaseState.values.where((s) => s.isTerminal)) {
        expect(ReleaseStateMachine.transitions[state], isEmpty);
      }
      expect(ReleaseState.values.where((s) => s.isTerminal), [
        ReleaseState.merged,
        ReleaseState.abandoned,
      ]);
    });

    test('only a rejected release goes back to building', () {
      expect(
        ReleaseState.values.where(
          (s) => ReleaseStateMachine.canMove(s, ReleaseState.building),
        ),
        [ReleaseState.draft, ReleaseState.rejected],
      );
    });

    test('only a live release is merged', () {
      expect(
        ReleaseState.values.where(
          (s) => ReleaseStateMachine.canMove(s, ReleaseState.merged),
        ),
        [ReleaseState.live],
      );
    });

    test('every release that is not over can be abandoned', () {
      for (final state in ReleaseState.values.where((s) => !s.isTerminal)) {
        expect(
          ReleaseStateMachine.canMove(state, ReleaseState.abandoned),
          isTrue,
          reason: state.wire,
        );
      }
    });

    test('the refusal says what it refused', () {
      const error = ReleaseTransitionException(
        ReleaseState.merged,
        ReleaseState.building,
      );

      expect(error.message, 'A release cannot move from merged to building.');
      expect(error.toString(), contains('merged to building'));
    });
  });

  group('the exceptions', () {
    test('print their kind and message', () {
      expect(const ReleaseException('a').toString(), 'ReleaseException: a');
      expect(
        const ReleaseNotFoundException('rel_1').toString(),
        'ReleaseNotFoundException: There is no release rel_1.',
      );
      expect(
        const ReleaseStateException('b').toString(),
        'ReleaseStateException: b',
      );
      expect(
        const ReleaseForbiddenException('c').toString(),
        'ReleaseForbiddenException: c',
      );
      expect(
        const ReleaseRequestException('d').toString(),
        'ReleaseRequestException: d',
      );
    });
  });
}
