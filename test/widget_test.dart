import 'package:flutter_test/flutter_test.dart';

import 'package:hallucinator/main.dart';

void main() {
  test('built-in generator creates a wiki style article', () {
    final generator = BuiltInLocalGenerator();
    final article = generator.generateArticle('cyberpunk gardens');

    expect(article.toLowerCase(), contains('cyberpunk gardens'));
    expect(article.toLowerCase(), contains('overview'));
    expect(article.toLowerCase(), contains('summary'));
  });

  test('built-in generator builds a stable horde request payload', () {
    final generator = BuiltInLocalGenerator();
    final payload = generator.buildStableHordeRequest('cyberpunk gardens', 3);

    expect(payload['prompt'], 'cyberpunk gardens');
    expect(payload['params']['n'], 3);
    expect(payload['censor_nsfw'], isTrue);
  });

  testWidgets('shows the browser-style local search UI', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('hallucinator'), findsOneWidget);
    expect(find.text('Search the local web'), findsOneWidget);
    expect(find.text('Image generation uses Stable Horde.'), findsOneWidget);
  });
}
