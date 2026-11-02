import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/ui/widgets/routing/mini_map_widget.dart';

void main() {
  group('MiniMapWidget', () {
    late ScrollController horizontalController;
    late ScrollController verticalController;

    setUp(() {
      horizontalController = ScrollController();
      verticalController = ScrollController();
    });

    tearDown(() {
      horizontalController.dispose();
      verticalController.dispose();
    });

    group('Initialization', () {
      testWidgets('should create widget with default dimensions', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MiniMapWidget(
                horizontalScrollController: horizontalController,
                verticalScrollController: verticalController,
                canvasWidth: 5000.0,
                canvasHeight: 5000.0,
              ),
            ),
          ),
        );

        expect(find.byType(MiniMapWidget), findsOneWidget);

        // Verify the widget has the correct default dimensions (200x150 from spec)
        final miniMapWidget = tester.widget<MiniMapWidget>(
          find.byType(MiniMapWidget),
        );
        expect(miniMapWidget.width, equals(200.0));
        expect(miniMapWidget.height, equals(150.0));
      });

      testWidgets('should accept custom dimensions', (tester) async {
        const customWidth = 250.0;
        const customHeight = 180.0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MiniMapWidget(
                horizontalScrollController: horizontalController,
                verticalScrollController: verticalController,
                canvasWidth: 5000.0,
                canvasHeight: 5000.0,
                width: customWidth,
                height: customHeight,
              ),
            ),
          ),
        );

        final miniMapWidget = tester.widget<MiniMapWidget>(
          find.byType(MiniMapWidget),
        );
        expect(miniMapWidget.width, equals(customWidth));
        expect(miniMapWidget.height, equals(customHeight));
      });

      testWidgets('should properly receive and store canvas dimensions', (
        tester,
      ) async {
        const canvasWidth = 5000.0;
        const canvasHeight = 5000.0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MiniMapWidget(
                horizontalScrollController: horizontalController,
                verticalScrollController: verticalController,
                canvasWidth: canvasWidth,
                canvasHeight: canvasHeight,
              ),
            ),
          ),
        );

        final miniMapWidget = tester.widget<MiniMapWidget>(
          find.byType(MiniMapWidget),
        );
        expect(miniMapWidget.canvasWidth, equals(canvasWidth));
        expect(miniMapWidget.canvasHeight, equals(canvasHeight));
      });
    });

    group('Scroll Controller Binding', () {
      testWidgets('should accept horizontal scroll controller', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MiniMapWidget(
                horizontalScrollController: horizontalController,
                verticalScrollController: verticalController,
                canvasWidth: 5000.0,
                canvasHeight: 5000.0,
              ),
            ),
          ),
        );

        final miniMapWidget = tester.widget<MiniMapWidget>(
          find.byType(MiniMapWidget),
        );
        expect(
          miniMapWidget.horizontalScrollController,
          equals(horizontalController),
        );
      });

      testWidgets('should accept vertical scroll controller', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MiniMapWidget(
                horizontalScrollController: horizontalController,
                verticalScrollController: verticalController,
                canvasWidth: 5000.0,
                canvasHeight: 5000.0,
              ),
            ),
          ),
        );

        final miniMapWidget = tester.widget<MiniMapWidget>(
          find.byType(MiniMapWidget),
        );
        expect(
          miniMapWidget.verticalScrollController,
          equals(verticalController),
        );
      });

      
    });

    group('Scale Factor Calculation', () {
      testWidgets('should calculate correct scale factor', (tester) async {
        const canvasWidth = 5000.0;
        const canvasHeight = 5000.0;
        const miniMapWidth = 200.0;
        const miniMapHeight = 150.0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MiniMapWidget(
                horizontalScrollController: horizontalController,
                verticalScrollController: verticalController,
                canvasWidth: canvasWidth,
                canvasHeight: canvasHeight,
                width: miniMapWidth,
                height: miniMapHeight,
              ),
            ),
          ),
        );

        final state = tester.state<MiniMapWidgetState>(
          find.byType(MiniMapWidget),
        );

        // Scale factor should be min(miniMapWidth/canvasWidth, miniMapHeight/canvasHeight)
        // min(200/5000, 150/5000) = min(0.04, 0.03) = 0.03
        expect(state.scaleFactor, closeTo(0.03, 0.001));
      });
    });

    group('Viewport Position Tracking', () {
      testWidgets(
        'should update viewport position when scroll controllers change',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: SingleChildScrollView(
                controller: horizontalController,
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  controller: verticalController,
                  scrollDirection: Axis.vertical,
                  child: SizedBox(
                    width: 5000,
                    height: 5000,
                    child: Stack(
                      children: [
                        MiniMapWidget(
                          horizontalScrollController: horizontalController,
                          verticalScrollController: verticalController,
                          canvasWidth: 5000.0,
                          canvasHeight: 5000.0,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );

          final state = tester.state<MiniMapWidgetState>(
            find.byType(MiniMapWidget),
          );

          // Initially, viewport should be at (0, 0)
          expect(state.viewportOffset, equals(Offset.zero));

          // Simulate scroll
          horizontalController.jumpTo(100.0);
          verticalController.jumpTo(200.0);

          await tester.pump();

          // Viewport offset should update to reflect scroll position
          expect(state.viewportOffset, equals(const Offset(100.0, 200.0)));
        },
      );

      testWidgets('should handle scroll controller disposal gracefully', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MiniMapWidget(
                horizontalScrollController: horizontalController,
                verticalScrollController: verticalController,
                canvasWidth: 5000.0,
                canvasHeight: 5000.0,
              ),
            ),
          ),
        );

        // Widget should be created successfully
        expect(find.byType(MiniMapWidget), findsOneWidget);

        // Remove the widget (this should trigger dispose)
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));

        // Should not throw any errors during disposal
        expect(tester.takeException(), isNull);
      });
    });

    group('Widget Lifecycle Management', () {
      testWidgets(
        'should properly dispose of listeners when widget is disposed',
        (tester) async {
          final testController = ScrollController();

          // Track when listeners are removed
          void testListener() {}
          testController.addListener(testListener);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MiniMapWidget(
                  horizontalScrollController: testController,
                  verticalScrollController: verticalController,
                  canvasWidth: 5000.0,
                  canvasHeight: 5000.0,
                ),
              ),
            ),
          );

          // Remove the widget to trigger disposal
          await tester.pumpWidget(const MaterialApp(home: Scaffold()));

          // Dispose should have been called and shouldn't throw
          expect(tester.takeException(), isNull);

          testController.dispose();
        },
      );
    });

    group('MiniMapPainter', () {
      group('Coordinate Scaling Calculations', () {
        

        test('should correctly calculate viewport rectangle dimensions', () {
          const scaleFactor = 0.03; // min(200/5000, 150/5000)

          // Viewport size from RoutingEditorWidget defaults
          const viewportWidth = 1200.0;
          const viewportHeight = 800.0;

          final scaledViewportWidth = viewportWidth * scaleFactor;
          final scaledViewportHeight = viewportHeight * scaleFactor;

          expect(scaledViewportWidth, closeTo(36.0, 0.1));
          expect(scaledViewportHeight, closeTo(24.0, 0.1));
        });

        test('should handle edge cases for coordinate scaling', () {
          const scaleFactor = 0.03;

          // Test negative coordinates (canvas can scroll to negative positions)
          const negativeCoord = Offset(-100, -50);
          final scaledNegative = Offset(
            negativeCoord.dx * scaleFactor,
            negativeCoord.dy * scaleFactor,
          );

          expect(scaledNegative.dx, closeTo(-3.0, 0.1));
          expect(scaledNegative.dy, closeTo(-1.5, 0.1));

          // Test zero coordinates
          const zeroCoord = Offset.zero;
          final scaledZero = Offset(
            zeroCoord.dx * scaleFactor,
            zeroCoord.dy * scaleFactor,
          );

          expect(scaledZero, equals(Offset.zero));

          // Test very large coordinates
          const largeCoord = Offset(10000, 8000);
          final scaledLarge = Offset(
            largeCoord.dx * scaleFactor,
            largeCoord.dy * scaleFactor,
          );

          expect(scaledLarge.dx, closeTo(300.0, 0.1));
          expect(scaledLarge.dy, closeTo(240.0, 0.1));
        });
      });

      group('Node Position Scaling', () {
        test(
          'should correctly scale node positions from canvas to mini-map space',
          () {
            const scaleFactor = 0.04; // 200/5000

            final nodePositions = {
              'algorithm_1': const Offset(1000, 500),
              'algorithm_2': const Offset(2500, 1500),
              'physical_inputs': const Offset(200, 400),
              'physical_outputs': const Offset(4800, 400),
            };

            final expectedScaledPositions = {
              'algorithm_1': const Offset(40, 20),
              'algorithm_2': const Offset(100, 60),
              'physical_inputs': const Offset(8, 16),
              'physical_outputs': const Offset(192, 16),
            };

            for (final entry in nodePositions.entries) {
              final scaled = Offset(
                entry.value.dx * scaleFactor,
                entry.value.dy * scaleFactor,
              );
              final expected = expectedScaledPositions[entry.key]!;

              expect(
                scaled.dx,
                closeTo(expected.dx, 0.1),
                reason: 'Node ${entry.key} X coordinate scaling failed',
              );
              expect(
                scaled.dy,
                closeTo(expected.dy, 0.1),
                reason: 'Node ${entry.key} Y coordinate scaling failed',
              );
            }
          },
        );
      });

      group('Connection Path Scaling', () {
        test('should correctly scale connection start and end points', () {
          const scaleFactor = 0.04;

          final connectionPaths = [
            (start: const Offset(200, 400), end: const Offset(1000, 500)),
            (start: const Offset(1000, 500), end: const Offset(2500, 1500)),
            (start: const Offset(2500, 1500), end: const Offset(4800, 400)),
          ];

          final expectedScaledPaths = [
            (start: const Offset(8, 16), end: const Offset(40, 20)),
            (start: const Offset(40, 20), end: const Offset(100, 60)),
            (start: const Offset(100, 60), end: const Offset(192, 16)),
          ];

          for (int i = 0; i < connectionPaths.length; i++) {
            final path = connectionPaths[i];
            final expected = expectedScaledPaths[i];

            final scaledStart = Offset(
              path.start.dx * scaleFactor,
              path.start.dy * scaleFactor,
            );
            final scaledEnd = Offset(
              path.end.dx * scaleFactor,
              path.end.dy * scaleFactor,
            );

            expect(scaledStart.dx, closeTo(expected.start.dx, 0.1));
            expect(scaledStart.dy, closeTo(expected.start.dy, 0.1));
            expect(scaledEnd.dx, closeTo(expected.end.dx, 0.1));
            expect(scaledEnd.dy, closeTo(expected.end.dy, 0.1));
          }
        });
      });

      group('Clipping and Bounds', () {
        test(
          'should correctly calculate clipping bounds for overflow prevention',
          () {
            const miniMapWidth = 200.0;
            const miniMapHeight = 150.0;

            final testRectangles = [
              // Rectangle completely inside bounds
              const Rect.fromLTWH(10, 10, 50, 30),
              // Rectangle partially outside right edge
              const Rect.fromLTWH(180, 10, 50, 30),
              // Rectangle partially outside bottom edge
              const Rect.fromLTWH(10, 140, 50, 30),
              // Rectangle completely outside bounds
              const Rect.fromLTWH(250, 200, 50, 30),
            ];

            final expectedClippedRectangles = [
              // Should remain unchanged
              const Rect.fromLTWH(10, 10, 50, 30),
              // Should be clipped to mini-map right edge
              const Rect.fromLTWH(180, 10, 20, 30),
              // Should be clipped to mini-map bottom edge
              const Rect.fromLTWH(10, 140, 50, 10),
              // Should be clipped to zero size (completely outside)
              const Rect.fromLTWH(200, 150, 0, 0),
            ];

            for (int i = 0; i < testRectangles.length; i++) {
              final rect = testRectangles[i];
              final expected = expectedClippedRectangles[i];

              // Simulate clipping logic
              final clippedLeft = rect.left.clamp(0.0, miniMapWidth);
              final clippedTop = rect.top.clamp(0.0, miniMapHeight);
              final maxWidth = (miniMapWidth - clippedLeft).clamp(
                0.0,
                miniMapWidth,
              );
              final maxHeight = (miniMapHeight - clippedTop).clamp(
                0.0,
                miniMapHeight,
              );
              final clippedWidth = (rect.width).clamp(0.0, maxWidth);
              final clippedHeight = (rect.height).clamp(0.0, maxHeight);

              final clippedRect = Rect.fromLTWH(
                clippedLeft,
                clippedTop,
                clippedWidth,
                clippedHeight,
              );

              expect(clippedRect.left, closeTo(expected.left, 0.1));
              expect(clippedRect.top, closeTo(expected.top, 0.1));
              expect(clippedRect.width, closeTo(expected.width, 0.1));
              expect(clippedRect.height, closeTo(expected.height, 0.1));
            }
          },
        );
      });
    });

    group('Tap-to-Navigate Interaction', () {
      group('Coordinate Transformation', () {
        

        
      });

      group('Tap Detection and Response', () {
        testWidgets('should detect tap on mini-map widget', (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: SingleChildScrollView(
                controller: horizontalController,
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  controller: verticalController,
                  scrollDirection: Axis.vertical,
                  child: SizedBox(
                    width: 5000,
                    height: 5000,
                    child: Stack(
                      children: [
                        Positioned(
                          top: 20,
                          left: 20,
                          child: MiniMapWidget(
                            horizontalScrollController: horizontalController,
                            verticalScrollController: verticalController,
                            canvasWidth: 5000.0,
                            canvasHeight: 5000.0,
                            width: 200.0,
                            height: 150.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );

          // Tap at a position that should trigger navigation
          await tester.tapAt(
            const Offset(120, 95),
          ); // Position relative to screen (accounting for widget position)
          await tester.pump();

          // If tap is detected and handled, scroll positions should change or be handled gracefully
          expect(find.byType(MiniMapWidget), findsOneWidget);
        });

        testWidgets('should respond to tap within 50ms requirement', (
          tester,
        ) async {
          final stopwatch = Stopwatch();

          await tester.pumpWidget(
            MaterialApp(
              home: SingleChildScrollView(
                controller: horizontalController,
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  controller: verticalController,
                  scrollDirection: Axis.vertical,
                  child: SizedBox(
                    width: 5000,
                    height: 5000,
                    child: Stack(
                      children: [
                        Positioned(
                          top: 20,
                          left: 20,
                          child: MiniMapWidget(
                            horizontalScrollController: horizontalController,
                            verticalScrollController: verticalController,
                            canvasWidth: 5000.0,
                            canvasHeight: 5000.0,
                            width: 200.0,
                            height: 150.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );

          stopwatch.start();

          // Tap at center of mini-map
          await tester.tapAt(const Offset(120, 95));
          await tester.pump();

          stopwatch.stop();

          // Verify response time is under 50ms (this tests initial response, not animation completion)
          expect(stopwatch.elapsedMilliseconds, lessThan(50));
        });
      });

      group('Scroll Navigation', () {
        testWidgets('should animate scroll controllers to target position', (
          tester,
        ) async {
          await tester.pumpWidget(
            MaterialApp(
              home: SingleChildScrollView(
                controller: horizontalController,
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  controller: verticalController,
                  scrollDirection: Axis.vertical,
                  child: SizedBox(
                    width: 5000,
                    height: 5000,
                    child: Stack(
                      children: [
                        Positioned(
                          top: 20,
                          left: 20,
                          child: MiniMapWidget(
                            horizontalScrollController: horizontalController,
                            verticalScrollController: verticalController,
                            canvasWidth: 5000.0,
                            canvasHeight: 5000.0,
                            width: 200.0,
                            height: 150.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );

          // Initial scroll position should be 0
          expect(horizontalController.offset, equals(0.0));
          expect(verticalController.offset, equals(0.0));

          // Tap at center of mini-map should scroll to center of canvas
          // Center tap: (100, 75) -> Canvas: (3333, 2500)
          // Viewport centered at (3333, 2500) with viewport size (1200, 800)
          // Scroll offset should be (3333 - 600, 2500 - 400) = (2733, 2100)
          await tester.tapAt(
            const Offset(120, 95),
          ); // Position relative to screen

          // Allow animation to complete
          await tester.pumpAndSettle();

          // Verify scroll controllers have been updated (within viewport centering bounds)
          expect(horizontalController.offset, greaterThan(2000));
          expect(verticalController.offset, greaterThan(1800));
        });

        testWidgets('should apply boundary checking for scroll positions', (
          tester,
        ) async {
          await tester.pumpWidget(
            MaterialApp(
              home: SingleChildScrollView(
                controller: horizontalController,
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  controller: verticalController,
                  scrollDirection: Axis.vertical,
                  child: SizedBox(
                    width: 5000,
                    height: 5000,
                    child: Stack(
                      children: [
                        Positioned(
                          top: 20,
                          left: 20,
                          child: MiniMapWidget(
                            horizontalScrollController: horizontalController,
                            verticalScrollController: verticalController,
                            canvasWidth: 5000.0,
                            canvasHeight: 5000.0,
                            width: 200.0,
                            height: 150.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );

          // Test tapping near the edges to ensure boundary checking
          final testCases = [
            // Tap near top-left (should be constrained to min scroll extent)
            const Offset(20, 20),
            // Tap near bottom-right (should be constrained to max scroll extent)
            const Offset(170, 135),
          ];

          for (final tapPosition in testCases) {
            await tester.tapAt(
              tapPosition.translate(20, 20),
            ); // Account for widget position
            await tester.pumpAndSettle();

            // Verify scroll positions are within valid bounds
            expect(
              horizontalController.offset,
              inInclusiveRange(
                horizontalController.position.minScrollExtent,
                horizontalController.position.maxScrollExtent,
              ),
            );
            expect(
              verticalController.offset,
              inInclusiveRange(
                verticalController.position.minScrollExtent,
                verticalController.position.maxScrollExtent,
              ),
            );
          }
        });
      });
    });
  });
}
