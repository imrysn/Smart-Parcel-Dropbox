import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_parcel_dropbox/models/tracking_model.dart';
import 'package:smart_parcel_dropbox/presentation/screens/orders/orders_tab.dart';
import 'package:smart_parcel_dropbox/services/database_service.dart';

class _OrdersDatabase extends Fake implements DatabaseService {
  @override
  List<TrackingModel> get cachedTracking => [
        TrackingModel(
          trackingId: 'delivery-1',
          userId: 'owner',
          shopName: 'Shopee',
          status: 'pending',
        ),
      ];

  @override
  Stream<List<TrackingModel>> getUserTrackingIds(String userId) =>
      const Stream.empty();

  @override
  Future<void> refreshTracking(String userId) async {}
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('Orders filters wrap and stay tappable in ${brightness.name}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final database = _OrdersDatabase();
      var mode = 0;
      var inboundFilter = 0;
      var outboundFilter = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness, useMaterial3: true),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 640),
                textScaler: TextScaler.linear(1.8),
              ),
              child: StatefulBuilder(
                builder: (context, setState) => OrdersTab(
                  userId: 'owner',
                  databaseService: database,
                  ordersMode: mode,
                  inboundFilterIndex: inboundFilter,
                  outboundFilterIndex: outboundFilter,
                  onOrdersModeChanged: (value) => setState(() => mode = value),
                  onInboundFilterChanged: (value) =>
                      setState(() => inboundFilter = value),
                  onOutboundFilterChanged: (value) =>
                      setState(() => outboundFilter = value),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final order = tester.widget<Card>(find.byType(Card));
      expect(
        order.color,
        brightness == Brightness.dark
            ? const Color(0xFF201F1D)
            : const Color(0xFFFFFDFA),
      );
      expect(
        (order.shape as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(24),
      );

      final all = find.widgetWithText(ChoiceChip, 'All (1)');
      final retrieved = find.widgetWithText(ChoiceChip, 'Retrieved (0)');
      expect(tester.getTopLeft(retrieved).dy,
          greaterThan(tester.getTopLeft(all).dy));
      await tester.tap(retrieved);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(retrieved).selected, isTrue);
      expect(find.text('No Retrieval History'), findsOneWidget);

      await tester.tap(find.text('Pickups'));
      await tester.pumpAndSettle();
      final completed = find.widgetWithText(ChoiceChip, 'Completed (0)');
      await tester.tap(completed);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(completed).selected, isTrue);
      expect(find.text('No Completed Pickups'), findsOneWidget);

      await tester.tap(find.text('Deliveries'));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(retrieved).selected, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
