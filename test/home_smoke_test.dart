import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_studio/main.dart';
import 'package:vibe_studio/state/app_controller.dart';

void main() {
  testWidgets('home page renders welcome screen and toolbar', (tester) async {
    final controller = AppController();
    await tester.pumpWidget(VibeStudioApp(controller: controller));
    await tester.pump();

    expect(find.text('Vibe Studio'), findsWidgets);
    expect(find.text('Open a project folder'), findsOneWidget);
    expect(find.text('Open Project'), findsOneWidget);
    expect(find.text('server stopped'), findsOneWidget);

    controller.dispose();
  });
}
