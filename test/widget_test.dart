import 'package:flutter_test/flutter_test.dart';

import 'package:boardgame_acquire/main.dart';

void main() {
  testWidgets('App shell renders', (WidgetTester tester) async {
    await tester.pumpWidget(const LobbyApp());

    expect(find.text('This app is currently web-only.'), findsOneWidget);
  });
}
