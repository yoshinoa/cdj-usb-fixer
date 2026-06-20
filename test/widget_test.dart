import 'package:flutter_test/flutter_test.dart';

import 'package:cdj_usb/main.dart';

void main() {
  testWidgets('app boots and shows title', (tester) async {
    await tester.pumpWidget(const CdjUsbApp());
    expect(find.text('CDJ USB Checker'), findsOneWidget);
  });
}
