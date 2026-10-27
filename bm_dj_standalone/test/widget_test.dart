import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:bm_dj/main.dart';
import 'package:bm_dj/controllers/dj_deck_manager.dart';
import 'package:bm_dj/services/api_service.dart';

void main() {
  setUpAll(() {
    ApiService.isTestMode = true;
  });

  testWidgets('BM DJ App smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DJDeckManager(),
        child: const BMDJApp(),
      ),
    );
    await tester.pump();

    expect(find.text('BM DJ'), findsOneWidget);
    expect(find.text('DECK A'), findsWidgets);
    expect(find.text('DECK B'), findsWidgets);
    expect(find.text('MANUAL BPM'), findsOneWidget);
    expect(find.text('SYNC'), findsWidgets);
  });
}
