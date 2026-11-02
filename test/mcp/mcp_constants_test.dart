import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/mcp/mcp_constants.dart';

class TestAlgorithm {
  final String guid;
  final String name;
  TestAlgorithm(this.guid, this.name);
}

void main() {
  group('MCPConstants', () {
    test('maxSlots is 40', () {
      expect(MCPConstants.maxSlots, 40);
    });

    test('fuzzyMatchThreshold is 0.7', () {
      expect(MCPConstants.fuzzyMatchThreshold, 0.7);
    });

    test('maxNotesLines is 7', () {
      expect(MCPConstants.maxNotesLines, 7);
    });

    test('maxNotesLineLength is 31', () {
      expect(MCPConstants.maxNotesLineLength, 31);
    });
  });

  group('MCPUtils', () {
    group('scaleForDisplay', () {
      test('returns raw value when powerOfTen is null', () {
        expect(MCPUtils.scaleForDisplay(1234, null), 1234);
      });

      test('returns raw value when powerOfTen is 0', () {
        expect(MCPUtils.scaleForDisplay(1234, 0), 1234);
      });

      test('scales by power of 10 when powerOfTen is positive', () {
        expect(MCPUtils.scaleForDisplay(1234, 1), 123.4);
        expect(MCPUtils.scaleForDisplay(1234, 2), 12.34);
        expect(MCPUtils.scaleForDisplay(1234, 3), 1.234);
      });

      test('returns raw value when powerOfTen is negative', () {
        // Negative powerOfTen does not scale (condition is > 0)
        expect(MCPUtils.scaleForDisplay(1234, -1), 1234);
        expect(MCPUtils.scaleForDisplay(1234, -2), 1234);
      });

      test('handles zero value', () {
        expect(MCPUtils.scaleForDisplay(0, 2), 0.0);
        expect(MCPUtils.scaleForDisplay(0, null), 0);
      });

      test('handles negative values', () {
        expect(MCPUtils.scaleForDisplay(-500, 2), -5.0);
        expect(MCPUtils.scaleForDisplay(-500, null), -500);
      });

      test('handles large powerOfTen', () {
        expect(MCPUtils.scaleForDisplay(1000000, 6), 1.0);
      });
    });

    group('scaleToRaw', () {
      test('returns int when powerOfTen is null', () {
        expect(MCPUtils.scaleToRaw(123.4, null), 123);
      });

      test('returns int when powerOfTen is 0', () {
        expect(MCPUtils.scaleToRaw(123.4, 0), 123);
      });

      test('scales up by power of 10 when powerOfTen is positive', () {
        expect(MCPUtils.scaleToRaw(12.34, 2), 1234);
        expect(MCPUtils.scaleToRaw(1.5, 1), 15);
      });

      test('rounds correctly when scaling', () {
        // 1.555 * 100 = 155.5 -> rounds to 156
        expect(MCPUtils.scaleToRaw(1.555, 2), 156);
        // 1.554 * 100 = 155.4 -> rounds to 155
        expect(MCPUtils.scaleToRaw(1.554, 2), 155);
      });

      test('truncates (toInt) when powerOfTen is null', () {
        // toInt truncates towards zero, does not round
        expect(MCPUtils.scaleToRaw(1.9, null), 1);
        expect(MCPUtils.scaleToRaw(-1.9, null), -1);
      });

      test('handles zero display value', () {
        expect(MCPUtils.scaleToRaw(0, 2), 0);
        expect(MCPUtils.scaleToRaw(0, null), 0);
      });

      test('handles negative display value', () {
        expect(MCPUtils.scaleToRaw(-5.0, 2), -500);
      });

      test('round-trips with scaleForDisplay', () {
        // scaleToRaw(scaleForDisplay(x, p), p) should return x for integer values
        for (final powerOfTen in [null, 0, 1, 2, 3]) {
          for (final value in [0, 1, 100, -50, 9999]) {
            final displayed = MCPUtils.scaleForDisplay(value, powerOfTen);
            final raw = MCPUtils.scaleToRaw(displayed, powerOfTen);
            expect(
              raw,
              value,
              reason:
                  'Round trip failed for value=$value, powerOfTen=$powerOfTen',
            );
          }
        }
      });

      test('returns int when powerOfTen is negative', () {
        // Negative powerOfTen does not scale (condition is > 0)
        expect(MCPUtils.scaleToRaw(123.7, -1), 123);
      });

      test('handles floating point precision correctly', () {
        // Classic FP issues: 1.23 * 100 = 122.99999... in IEEE 754
        expect(MCPUtils.scaleToRaw(1.23, 2), 123);
        // 0.1 * 10 = 1.0000000000000002
        expect(MCPUtils.scaleToRaw(0.1, 1), 1);
        // 0.3 * 10 = 2.9999999999999996
        expect(MCPUtils.scaleToRaw(0.3, 1), 3);
        // 19.99 * 100 = 1998.9999999999998
        expect(MCPUtils.scaleToRaw(19.99, 2), 1999);
      }, tags: ['regression']);
    });

    group('levenshteinDistance', () {
      test('returns 0 for identical strings', () {
        expect(MCPUtils.levenshteinDistance('abc', 'abc'), 0);
      });

      test('returns length of other string when one is empty', () {
        expect(MCPUtils.levenshteinDistance('', 'abc'), 3);
        expect(MCPUtils.levenshteinDistance('abc', ''), 3);
      });

      test('returns 0 for both empty strings', () {
        expect(MCPUtils.levenshteinDistance('', ''), 0);
      });

      test('is case-insensitive', () {
        expect(MCPUtils.levenshteinDistance('ABC', 'abc'), 0);
        expect(MCPUtils.levenshteinDistance('Hello', 'hello'), 0);
      });

      test('computes known distances correctly', () {
        // kitten -> sitting: 3 edits
        expect(MCPUtils.levenshteinDistance('kitten', 'sitting'), 3);
        // Single character difference
        expect(MCPUtils.levenshteinDistance('cat', 'car'), 1);
        // Insertion
        expect(MCPUtils.levenshteinDistance('cat', 'cats'), 1);
        // Deletion
        expect(MCPUtils.levenshteinDistance('cats', 'cat'), 1);
      });

      test('handles single character strings', () {
        expect(MCPUtils.levenshteinDistance('a', 'b'), 1);
        expect(MCPUtils.levenshteinDistance('a', 'a'), 0);
        expect(MCPUtils.levenshteinDistance('a', ''), 1);
      });

      test('is symmetric', () {
        expect(
          MCPUtils.levenshteinDistance('abc', 'xyz'),
          MCPUtils.levenshteinDistance('xyz', 'abc'),
        );
        expect(
          MCPUtils.levenshteinDistance('flutter', 'flatter'),
          MCPUtils.levenshteinDistance('flatter', 'flutter'),
        );
      });
    });

    group('similarity', () {
      test('returns 1.0 for identical strings', () {
        expect(MCPUtils.similarity('abc', 'abc'), 1.0);
      });

      test('returns 1.0 for both empty strings', () {
        expect(MCPUtils.similarity('', ''), 1.0);
      });

      test('returns 0.0 for completely different single-char strings', () {
        expect(MCPUtils.similarity('a', 'b'), 0.0);
      });

      test('returns 0.0 for one empty and one non-empty string', () {
        // distance('', 'abc') = 3, maxLen = 3, similarity = 0/3 = 0.0
        expect(MCPUtils.similarity('', 'abc'), 0.0);
        expect(MCPUtils.similarity('abc', ''), 0.0);
      });

      test('returns value between 0 and 1 for partial matches', () {
        final sim = MCPUtils.similarity('kitten', 'sitting');
        // distance is 3, maxLen is 7, similarity = 4/7 ≈ 0.571
        expect(sim, closeTo(4.0 / 7.0, 0.001));
      });

      test('is case-insensitive', () {
        expect(MCPUtils.similarity('Hello', 'hello'), 1.0);
      });

      test('is symmetric', () {
        expect(
          MCPUtils.similarity('abc', 'xyz'),
          MCPUtils.similarity('xyz', 'abc'),
        );
      });

      test('higher similarity for closer strings', () {
        // 'cat' vs 'car' (1 edit, len 3) = 2/3 ≈ 0.667
        // 'cat' vs 'dog' (3 edits, len 3) = 0/3 = 0.0
        expect(
          MCPUtils.similarity('cat', 'car'),
          greaterThan(MCPUtils.similarity('cat', 'dog')),
        );
      });
    });

    group('validateParam', () {
      test('returns false for null', () {
        expect(MCPUtils.validateParam(null), false);
      });

      test('returns false for empty string', () {
        expect(MCPUtils.validateParam(''), false);
      });

      test('returns true for non-empty string', () {
        expect(MCPUtils.validateParam('hello'), true);
      });

      test('returns true for zero (int)', () {
        // 0.toString() == "0", which is non-empty
        expect(MCPUtils.validateParam(0), true);
      });

      test('returns true for false (bool)', () {
        // false.toString() == "false", which is non-empty
        expect(MCPUtils.validateParam(false), true);
      });

      test('returns true for non-zero int', () {
        expect(MCPUtils.validateParam(42), true);
      });

      test('returns true for whitespace-only string', () {
        // Whitespace is non-empty
        expect(MCPUtils.validateParam('  '), true);
      });
    });

    group('validateRequiredParam', () {
      test('returns null for valid param', () {
        expect(MCPUtils.validateRequiredParam('value', 'paramName'), isNull);
      });

      test('returns error map for null param', () {
        final result = MCPUtils.validateRequiredParam(null, 'my_param');
        expect(result, isNotNull);
        expect(result!['success'], false);
        expect(result['error'], contains('my_param'));
      });

      test('returns error map for empty string param', () {
        final result = MCPUtils.validateRequiredParam('', 'my_param');
        expect(result, isNotNull);
        expect(result!['success'], false);
      });

      test('includes helpCommand when provided', () {
        final result = MCPUtils.validateRequiredParam(
          null,
          'my_param',
          helpCommand: 'Use search tool',
        );
        expect(result, isNotNull);
        expect(result!['help_command'], 'Use search tool');
      });
    });

    group('validateSlotIndex', () {
      test('returns error for null', () {
        final result = MCPUtils.validateSlotIndex(null);
        expect(result, isNotNull);
        expect(result!['success'], false);
        expect(result['error'], contains('slot_index'));
      });

      test('returns null for slot 0 (minimum valid)', () {
        expect(MCPUtils.validateSlotIndex(0), isNull);
      });

      test('returns null for slot 39 (maximum valid)', () {
        expect(MCPUtils.validateSlotIndex(39), isNull);
      });

      test('returns error for slot -1 (below range)', () {
        final result = MCPUtils.validateSlotIndex(-1);
        expect(result, isNotNull);
        expect(result!['success'], false);
        expect(result['error'], contains('out of range'));
      });

      test('returns error for slot 40 (above range)', () {
        final result = MCPUtils.validateSlotIndex(40);
        expect(result, isNotNull);
        expect(result!['success'], false);
      });

      test('returns null for mid-range slot', () {
        expect(MCPUtils.validateSlotIndex(15), isNull);
      });
    });

    group('validateParameterNumber', () {
      test('returns error for null', () {
        final result = MCPUtils.validateParameterNumber(null, 10, 0);
        expect(result, isNotNull);
        expect(result!['success'], false);
        expect(result['error'], contains('parameter_number'));
      });

      test('returns null for param 0 (minimum valid)', () {
        expect(MCPUtils.validateParameterNumber(0, 10, 0), isNull);
      });

      test('returns null for param maxParams-1 (maximum valid)', () {
        expect(MCPUtils.validateParameterNumber(9, 10, 0), isNull);
      });

      test('returns error for param -1 (below range)', () {
        final result = MCPUtils.validateParameterNumber(-1, 10, 0);
        expect(result, isNotNull);
        expect(result!['success'], false);
      });

      test('returns error for param equal to maxParams (above range)', () {
        final result = MCPUtils.validateParameterNumber(10, 10, 0);
        expect(result, isNotNull);
        expect(result!['success'], false);
      });

      test('includes slot index in error message', () {
        final result = MCPUtils.validateParameterNumber(100, 10, 5);
        expect(result, isNotNull);
        expect(result!['error'], contains('slot 5'));
      });

      test('handles maxParams of 0 (no valid parameters)', () {
        // When maxParams=0, even param 0 is out of range
        final result = MCPUtils.validateParameterNumber(0, 0, 0);
        expect(result, isNotNull);
        expect(result!['success'], false);
      });
    });

    group('validateMutuallyExclusive', () {
      test('returns error when no params provided', () {
        final result = MCPUtils.validateMutuallyExclusive({}, [
          'param_a',
          'param_b',
        ]);
        expect(result, isNotNull);
        expect(result!['success'], false);
        expect(result['error'], contains('required'));
      });

      test('returns null when exactly one param provided', () {
        final result = MCPUtils.validateMutuallyExclusive(
          {'param_a': 'value'},
          ['param_a', 'param_b'],
        );
        expect(result, isNull);
      });

      test('returns error when multiple params provided', () {
        final result = MCPUtils.validateMutuallyExclusive(
          {'param_a': 'value', 'param_b': 'value2'},
          ['param_a', 'param_b'],
        );
        expect(result, isNotNull);
        expect(result!['error'], contains('only one'));
      });

      test('ignores null and empty string params', () {
        final result = MCPUtils.validateMutuallyExclusive(
          {'param_a': null, 'param_b': '', 'param_c': 'value'},
          ['param_a', 'param_b', 'param_c'],
        );
        expect(result, isNull);
      });

      test('returns error when all three of three params provided', () {
        final result = MCPUtils.validateMutuallyExclusive(
          {'a': 'v1', 'b': 'v2', 'c': 'v3'},
          ['a', 'b', 'c'],
        );
        expect(result, isNotNull);
        expect(result!['error'], contains('only one'));
      });

      test('handles params not present in map as missing', () {
        final result = MCPUtils.validateMutuallyExclusive(
          {'other': 'value'},
          ['param_a', 'param_b'],
        );
        expect(result, isNotNull);
        expect(result!['error'], contains('required'));
      });
    });

    group('validateExactlyOne', () {
      test('returns error when no params provided', () {
        final result = MCPUtils.validateExactlyOne({}, ['param_a', 'param_b']);
        expect(result, isNotNull);
        expect(result!['success'], false);
      });

      test('returns null when exactly one param provided', () {
        final result = MCPUtils.validateExactlyOne(
          {'param_a': 'value'},
          ['param_a', 'param_b'],
        );
        expect(result, isNull);
      });

      test('returns error when multiple params provided', () {
        final result = MCPUtils.validateExactlyOne(
          {'param_a': 'value', 'param_b': 'value2'},
          ['param_a', 'param_b'],
        );
        expect(result, isNotNull);
        expect(result!['error'], contains('not both'));
      });

      test('includes helpCommand when provided', () {
        final result = MCPUtils.validateExactlyOne({}, [
          'param_a',
          'param_b',
        ], helpCommand: 'search tool');
        expect(result, isNotNull);
        expect(result!['help_command'], 'search tool');
      });

      test('returns error when all three of three params provided', () {
        final result = MCPUtils.validateExactlyOne(
          {'a': 'v1', 'b': 'v2', 'c': 'v3'},
          ['a', 'b', 'c'],
        );
        expect(result, isNotNull);
        expect(result!['success'], false);
      });
    });

    group('buildError', () {
      test('includes success false and message', () {
        final result = MCPUtils.buildError('something went wrong');
        expect(result['success'], false);
        expect(result['error'], 'something went wrong');
      });

      test('includes helpCommand when provided', () {
        final result = MCPUtils.buildError('err', helpCommand: 'help');
        expect(result['help_command'], 'help');
      });

      test('does not include help_command when null', () {
        final result = MCPUtils.buildError('err');
        expect(result.containsKey('help_command'), false);
      });

      test('includes details when provided and non-empty', () {
        final result = MCPUtils.buildError('err', details: {'key': 'value'});
        expect(result['details'], {'key': 'value'});
      });

      test('does not include details when empty map', () {
        final result = MCPUtils.buildError('err', details: {});
        expect(result.containsKey('details'), false);
      });

      test('does not include details when null', () {
        final result = MCPUtils.buildError('err', details: null);
        expect(result.containsKey('details'), false);
      });
    });

    group('buildSuccess', () {
      test('includes success true and message', () {
        final result = MCPUtils.buildSuccess('done');
        expect(result['success'], true);
        expect(result['message'], 'done');
      });

      test('merges data into result when provided', () {
        final result = MCPUtils.buildSuccess(
          'done',
          data: {'count': 5, 'name': 'x'},
        );
        expect(result['success'], true);
        expect(result['message'], 'done');
        expect(result['count'], 5);
        expect(result['name'], 'x');
      });

      test('does not add extra keys when data is null', () {
        final result = MCPUtils.buildSuccess('done');
        expect(result.keys, containsAll(['success', 'message']));
        expect(result.length, 2);
      });

      test('data cannot overwrite success field', () {
        final result = MCPUtils.buildSuccess('done', data: {'success': false});
        // success should remain true regardless of data contents
        expect(result['success'], true);
      });

      test('data cannot overwrite message field', () {
        final result = MCPUtils.buildSuccess(
          'done',
          data: {'message': 'hijacked'},
        );
        // message should remain 'done' regardless of data contents
        expect(result['message'], 'done');
      }, tags: ['regression']);
    });
  });

  group('AlgorithmResolutionResult', () {
    test('success has resolvedGuid and isSuccess true', () {
      final result = AlgorithmResolutionResult.success('abc123');
      expect(result.isSuccess, true);
      expect(result.resolvedGuid, 'abc123');
      expect(result.error, isNull);
    });

    test('error has error map and isSuccess false', () {
      final errorMap = {'success': false, 'error': 'something'};
      final result = AlgorithmResolutionResult.error(errorMap);
      expect(result.isSuccess, false);
      expect(result.error, errorMap);
      expect(result.resolvedGuid, isNull);
    });
  });

  group('AlgorithmResolver', () {
    final algorithms = [
      TestAlgorithm('abcd', 'Reverb'),
      TestAlgorithm('efgh', 'Delay'),
      TestAlgorithm('ijkl', 'Chorus'),
      TestAlgorithm('mnop', 'Flanger'),
    ];

    group('resolveAlgorithm', () {
      test('returns error when both guid and algorithmName are null', () {
        final result = AlgorithmResolver.resolveAlgorithm(
          guid: null,
          algorithmName: null,
          allAlgorithms: algorithms,
        );
        expect(result.isSuccess, false);
        expect(result.error!['error'], contains('guid'));
        expect(result.error!['error'], contains('algorithm_name'));
      });

      test('returns error when both guid and algorithmName are empty', () {
        final result = AlgorithmResolver.resolveAlgorithm(
          guid: '',
          algorithmName: '',
          allAlgorithms: algorithms,
        );
        expect(result.isSuccess, false);
      });

      test('returns guid directly when guid is provided', () {
        final result = AlgorithmResolver.resolveAlgorithm(
          guid: 'my-guid',
          algorithmName: null,
          allAlgorithms: algorithms,
        );
        expect(result.isSuccess, true);
        expect(result.resolvedGuid, 'my-guid');
      });

      test('prefers guid over algorithmName when both provided', () {
        final result = AlgorithmResolver.resolveAlgorithm(
          guid: 'custom-guid',
          algorithmName: 'Reverb',
          allAlgorithms: algorithms,
        );
        expect(result.isSuccess, true);
        expect(result.resolvedGuid, 'custom-guid');
      });

      test('resolves by exact name match (case-insensitive)', () {
        final result = AlgorithmResolver.resolveAlgorithm(
          guid: null,
          algorithmName: 'reverb',
          allAlgorithms: algorithms,
        );
        expect(result.isSuccess, true);
        expect(result.resolvedGuid, 'abcd');
      });

      test('resolves by exact name match (exact case)', () {
        final result = AlgorithmResolver.resolveAlgorithm(
          guid: null,
          algorithmName: 'Delay',
          allAlgorithms: algorithms,
        );
        expect(result.isSuccess, true);
        expect(result.resolvedGuid, 'efgh');
      });

      test('returns error for multiple exact matches', () {
        final dupes = [
          TestAlgorithm('aaa', 'Reverb'),
          TestAlgorithm('bbb', 'Reverb'),
        ];
        final result = AlgorithmResolver.resolveAlgorithm(
          guid: null,
          algorithmName: 'Reverb',
          allAlgorithms: dupes,
        );
        expect(result.isSuccess, false);
        expect(result.error!['error'], contains('Multiple'));
        expect(result.error!['error'], contains('guid'));
      });

      test('falls back to fuzzy match when no exact match', () {
        final result = AlgorithmResolver.resolveAlgorithm(
          guid: null,
          algorithmName: 'Reverd', // close to Reverb
          allAlgorithms: algorithms,
        );
        // similarity('Reverb', 'Reverd') = 1 - 1/6 ≈ 0.833 > 0.7
        expect(result.isSuccess, true);
        expect(result.resolvedGuid, 'abcd');
      });

      test('returns error when no match found at all', () {
        final result = AlgorithmResolver.resolveAlgorithm(
          guid: null,
          algorithmName: 'ZZZZZZZZZ',
          allAlgorithms: algorithms,
        );
        expect(result.isSuccess, false);
        expect(result.error!['error'], contains('No algorithm found'));
      });

      test('returns error for multiple fuzzy matches', () {
        // Two very similar names that both fuzzy match with input
        final similar = [
          TestAlgorithm('aaa', 'Flang'),
          TestAlgorithm('bbb', 'Flank'),
        ];
        final result = AlgorithmResolver.resolveAlgorithm(
          guid: null,
          algorithmName: 'Fland', // close to both
          allAlgorithms: similar,
        );
        // similarity('Flang', 'Fland') = 1 - 1/5 = 0.8
        // similarity('Flank', 'Fland') = 1 - 1/5 = 0.8
        expect(result.isSuccess, false);
        expect(result.error!['error'], contains('Multiple'));
      });

      test('resolves with empty algorithm list returns error', () {
        final result = AlgorithmResolver.resolveAlgorithm(
          guid: null,
          algorithmName: 'Reverb',
          allAlgorithms: [],
        );
        expect(result.isSuccess, false);
        expect(result.error!['error'], contains('No algorithm found'));
      });

      test('guid takes priority even if empty name also provided', () {
        final result = AlgorithmResolver.resolveAlgorithm(
          guid: 'direct-guid',
          algorithmName: '',
          allAlgorithms: algorithms,
        );
        expect(result.isSuccess, true);
        expect(result.resolvedGuid, 'direct-guid');
      });

      test('whitespace-only algorithmName does not match', () {
        final result = AlgorithmResolver.resolveAlgorithm(
          guid: null,
          algorithmName: '   ',
          allAlgorithms: algorithms,
        );
        // Whitespace-only name should not match any algorithm
        expect(result.isSuccess, false);
      });
    });
  });
}
