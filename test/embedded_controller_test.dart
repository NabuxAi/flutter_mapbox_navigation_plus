import 'package:flutter/services.dart';
import 'package:flutter_mapbox_navigation_plus/src/embedded/controller.dart';
import 'package:flutter_mapbox_navigation_plus/src/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MapBoxNavigationViewController', () {
    const viewId = 7;
    const methodChannel = MethodChannel('flutter_mapbox_navigation/$viewId');
    const eventChannel =
        EventChannel('flutter_mapbox_navigation/$viewId/events');

    tearDown(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger
        ..setMockMethodCallHandler(methodChannel, null)
        ..setMockStreamHandler(eventChannel, null);
    });

    test('initialize and buildRoute share one native event subscription',
        () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var listenCount = 0;

      messenger
        ..setMockStreamHandler(
          eventChannel,
          MockStreamHandler.inline(
            onListen: (_, __) {
              listenCount += 1;
            },
          ),
        )
        ..setMockMethodCallHandler(methodChannel, (call) async {
          if (call.method == 'buildRoute') {
            return true;
          }
          return null;
        });

      final controller = MapBoxNavigationViewController(viewId, (_) {});
      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      await controller.buildRoute(
        wayPoints: [
          WayPoint(name: 'Origin', latitude: 23.5859, longitude: 58.4059),
          WayPoint(name: 'Stop', latitude: 23.5900, longitude: 58.4100),
        ],
        options: MapBoxOptions(mode: MapBoxNavigationMode.cycling),
      );
      await Future<void>.delayed(Duration.zero);

      expect(listenCount, 1);
      controller.dispose();
    });
  });
}
