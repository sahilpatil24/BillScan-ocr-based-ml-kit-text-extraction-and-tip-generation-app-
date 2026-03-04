import 'package:flutter_test/flutter_test.dart';
import 'package:bill_scan/main.dart';

void main() {
  testWidgets('BillScan smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const BillScanApp());
    expect(find.text('BillScan'), findsOneWidget);
  });
}