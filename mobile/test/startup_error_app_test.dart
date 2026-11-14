import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('shows the startup error instead of a blank screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      StartupErrorApp(error: UnsupportedError('not configured for web')),
    );

    expect(find.text('CampusNiaga could not start'), findsOneWidget);
    expect(find.textContaining('not configured for web'), findsOneWidget);
    expect(find.textContaining('supabase_config.dart'), findsOneWidget);
  });
}
