import 'package:flutter_test/flutter_test.dart';

import 'package:audiobook_app/main.dart';

void main() {
  testWidgets('Audiobook app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const AudiobookApp());
    expect(find.text('Audiobooks'), findsNothing);
  });
}
