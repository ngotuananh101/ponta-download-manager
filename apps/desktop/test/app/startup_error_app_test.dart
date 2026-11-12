import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/app/startup_error_app.dart';

void main() {
  testWidgets('shows the startup error message', (tester) async {
    await tester.pumpWidget(
      const StartupErrorApp(message: 'engine failed to open: boom'),
    );
    expect(find.text('Ponta Download Manager'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.text('Không thể khởi động ứng dụng.'), findsOneWidget);
  });
}
