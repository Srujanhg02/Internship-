import 'package:flutter_test/flutter_test.dart';
import 'package:tkap_scanner/main.dart';

void main() {
  testWidgets('App renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const TKAPScannerApp());

    // The scanner screen should render its bottom controls.
    expect(find.text('Manual'), findsOneWidget);
  });
}
