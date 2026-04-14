import 'package:flutter_test/flutter_test.dart';

import 'package:drive_safe_mobile/main.dart';

void main() {
  testWidgets('Drive Safe mobile app renders home navigation', (tester) async {
    await tester.pumpWidget(const DriveSafeMobileApp());

    expect(find.text('Drive Safe'), findsWidgets);
    expect(find.text('Accueil'), findsOneWidget);
    expect(find.text('Surveillance'), findsOneWidget);
    expect(find.text('Historique'), findsOneWidget);
    expect(find.text('Confidentialite'), findsOneWidget);
  });
}
