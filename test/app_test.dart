import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/main.dart';

void main() {
  testWidgets('splash then empty Albums', (tester) async {
    await tester.pumpWidget(const FluoApp());
    expect(find.text('FLUO'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('New album'), findsOneWidget);
    expect(find.text('No albums yet'), findsOneWidget);
  });
}
