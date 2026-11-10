import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/app/app.dart';

void main() {
  testWidgets('shows the downloads screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PdmApp()));
    await tester.pumpAndSettle();
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('No downloads yet.'), findsOneWidget);
  });
}
