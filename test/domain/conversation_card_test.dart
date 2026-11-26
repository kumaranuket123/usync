import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/constants/game_content.dart';

void main() {
  test('a card shared to the chat names its kind and keeps its text', () {
    const card = ConversationCard(CardKind.truth, 'What do you love most about us?');
    expect(card.shareText, '🫶 Truth: What do you love most about us?');
  });
}
