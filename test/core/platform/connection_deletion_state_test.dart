import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/platform/connection_deletion_state.dart';

// Note: This state model is now used locally within UI widgets
// rather than being managed at the cubit level.

void main() {
  group('ConnectionDeletionState', () {
    group('constructor', () {
      test('creates initial state with idle mode', () {
        const state = ConnectionDeletionState.initial();

        expect(state.mode, equals(DeletionMode.idle));
        expect(state.hoveredConnectionId, isNull);
        expect(state.selectedConnectionIds, isEmpty);
      });

      test('creates hover state with connection id', () {
        final state = ConnectionDeletionState.hovering('connection-1');

        expect(state.mode, equals(DeletionMode.hovering));
        expect(state.hoveredConnectionId, equals('connection-1'));
        expect(state.selectedConnectionIds, isEmpty);
      });

      test('creates tap selection state with connection ids', () {
        const connectionIds = {'connection-1', 'connection-2'};
        const state = ConnectionDeletionState.tapSelected(connectionIds);

        expect(state.mode, equals(DeletionMode.tapSelected));
        expect(state.hoveredConnectionId, isNull);
        expect(state.selectedConnectionIds, equals(connectionIds));
      });
    });

    group('equality and hashing', () {
      test('states with same values are equal', () {
        final state1 = ConnectionDeletionState.hovering('connection-1');
        final state2 = ConnectionDeletionState.hovering('connection-1');

        expect(state1, equals(state2));
        expect(state1.hashCode, equals(state2.hashCode));
      });

      test('states with different values are not equal', () {
        final state1 = ConnectionDeletionState.hovering('connection-1');
        final state2 = ConnectionDeletionState.hovering('connection-2');

        expect(state1, isNot(equals(state2)));
      });

      test('different deletion modes are not equal', () {
        const state1 = ConnectionDeletionState.initial();
        final state2 = ConnectionDeletionState.hovering('connection-1');

        expect(state1, isNot(equals(state2)));
      });
    });

    group('state validation', () {
      test('tap selected state can have empty selection', () {
        const state = ConnectionDeletionState.tapSelected({});

        expect(state.mode, equals(DeletionMode.tapSelected));
        expect(state.selectedConnectionIds, isEmpty);
      });
    });

    group('convenience methods', () {
      test('isHovering returns true for hovering mode', () {
        final state = ConnectionDeletionState.hovering('connection-1');

        expect(state.isHovering, isTrue);
        expect(state.isTapSelecting, isFalse);
        expect(state.isIdle, isFalse);
      });

      test('isTapSelecting returns true for tap selected mode', () {
        const state = ConnectionDeletionState.tapSelected({'connection-1'});

        expect(state.isTapSelecting, isTrue);
        expect(state.isHovering, isFalse);
        expect(state.isIdle, isFalse);
      });

      test('isIdle returns true for idle mode', () {
        const state = ConnectionDeletionState.initial();

        expect(state.isIdle, isTrue);
        expect(state.isHovering, isFalse);
        expect(state.isTapSelecting, isFalse);
      });

      test('hasSelectedConnection returns correct values', () {
        const idleState = ConnectionDeletionState.initial();
        final hoverState = ConnectionDeletionState.hovering('connection-1');
        const tapState = ConnectionDeletionState.tapSelected({'connection-1'});
        const emptyTapState = ConnectionDeletionState.tapSelected({});

        expect(idleState.hasSelectedConnection, isFalse);
        expect(hoverState.hasSelectedConnection, isTrue);
        expect(tapState.hasSelectedConnection, isTrue);
        expect(emptyTapState.hasSelectedConnection, isFalse);
      });

      test('isConnectionSelected identifies selected connections', () {
        final hoverState = ConnectionDeletionState.hovering('connection-1');
        const tapState = ConnectionDeletionState.tapSelected({
          'connection-1',
          'connection-2',
        });

        expect(hoverState.isConnectionSelected('connection-1'), isTrue);
        expect(hoverState.isConnectionSelected('connection-2'), isFalse);

        expect(tapState.isConnectionSelected('connection-1'), isTrue);
        expect(tapState.isConnectionSelected('connection-2'), isTrue);
        expect(tapState.isConnectionSelected('connection-3'), isFalse);
      });
    });
  });
}
