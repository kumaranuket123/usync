/// The two options of one "would you rather" question.
class WouldYouRatherQuestion {
  const WouldYouRatherQuestion(this.a, this.b);
  final String a, b;
}

/// Question bank for Would you rather. A game stores only indexes into this list, so questions
/// can be added at the END without changing games in progress; never reorder or remove.
const wouldYouRatherQuestions = <WouldYouRatherQuestion>[
  WouldYouRatherQuestion('Have a cozy night in together', 'Go out for a night on the town'),
  WouldYouRatherQuestion('Travel the world for a year', 'Build your dream home'),
  WouldYouRatherQuestion('Always be 10 minutes early', 'Always be 20 minutes late'),
  WouldYouRatherQuestion('Cook dinner together', 'Order in and watch a movie'),
  WouldYouRatherQuestion('Live by the beach', 'Live in the mountains'),
  WouldYouRatherQuestion('Get a surprise gift', 'Get a surprise trip'),
  WouldYouRatherQuestion('Relive your first date', 'Skip ahead to your 50th anniversary'),
  WouldYouRatherQuestion('Know exactly how you will die', 'Know exactly when you will die'),
  WouldYouRatherQuestion('Have breakfast in bed every day', 'Have a candlelit dinner every week'),
  WouldYouRatherQuestion('Never argue again but never debate', 'Argue sometimes and always make up'),
  WouldYouRatherQuestion('Be able to read minds', 'Be able to teleport'),
  WouldYouRatherQuestion('Go on a spontaneous road trip', 'Plan a perfect holiday months ahead'),
  WouldYouRatherQuestion('Adopt a dog together', 'Adopt a cat together'),
  WouldYouRatherQuestion('Spend a weekend in a cabin', 'Spend a weekend in a big city'),
  WouldYouRatherQuestion('Dance in the kitchen', 'Sing in the car'),
  WouldYouRatherQuestion('Have a big wedding', 'Have a tiny, private one'),
  WouldYouRatherQuestion('Give up sweets forever', 'Give up salty snacks forever'),
  WouldYouRatherQuestion('Wake up early and watch the sunrise', 'Stay up late and watch the stars'),
  WouldYouRatherQuestion('Have unlimited free flights', 'Have unlimited free restaurant meals'),
  WouldYouRatherQuestion('Only text each other', 'Only call each other'),
  WouldYouRatherQuestion('Learn a new skill together', 'Try a new food together'),
  WouldYouRatherQuestion('Be famous together', 'Be anonymous and rich together'),
  WouldYouRatherQuestion('Have a movie marathon', 'Have a game night'),
  WouldYouRatherQuestion('Always know the right thing to say', 'Always know the right gift to give'),
  WouldYouRatherQuestion('Spend a rainy day indoors', 'Spend a sunny day outdoors'),
  WouldYouRatherQuestion('Go back to the past for a day', 'Visit the future for a day'),
  WouldYouRatherQuestion('Slow dance in the rain', 'Watch the snow fall from a warm blanket'),
  WouldYouRatherQuestion('Have a love letter every month', 'Have a surprise date every month'),
  WouldYouRatherQuestion('Camp under the stars', 'Stay in a fancy hotel'),
  WouldYouRatherQuestion('Take a dance class together', 'Take a cooking class together'),
];

/// One "how well do you know me" topic: each partner picks an option for themselves and guesses
/// the partner's pick.
class QuizQuestion {
  const QuizQuestion(this.topic, this.options);
  final String       topic;
  final List<String> options;
}

/// Question bank for How well do you know me. Same rule as above: a game stores indexes, so add at
/// the END only; never reorder, remove, or change the number of options of an existing question.
const quizQuestions = <QuizQuestion>[
  QuizQuestion('Ideal weekend', ['Adventure outdoors', 'Cozy at home', 'Out with friends', 'Trying somewhere new']),
  QuizQuestion('Favorite season', ['Spring', 'Summer', 'Autumn', 'Winter']),
  QuizQuestion('Go-to comfort food', ['Pizza', 'Something sweet', 'Pasta or noodles', 'Soup or a warm bowl']),
  QuizQuestion('Perfect date night', ['Dinner out', 'Movie at home', 'Walk and talk', 'Something active']),
  QuizQuestion('Morning or night', ['Early riser', 'Night owl', 'Depends on the day', 'Needs coffee first']),
  QuizQuestion('Dream holiday', ['Beach', 'Mountains', 'City break', 'Road trip']),
  QuizQuestion('Way to relax', ['Music', 'A show or movie', 'Reading', 'Sleep']),
  QuizQuestion('Favorite way to be shown love', ['Words', 'Quality time', 'Gifts', 'Hugs and touch']),
  QuizQuestion('Biggest fear', ['Heights', 'Spiders or bugs', 'Being alone', 'Public speaking']),
  QuizQuestion('Favorite drink', ['Coffee', 'Tea', 'Juice or soda', 'Water']),
  QuizQuestion('Superpower they would pick', ['Flying', 'Invisibility', 'Reading minds', 'Time travel']),
  QuizQuestion('Pet they would want', ['Dog', 'Cat', 'Something small', 'No pets']),
  QuizQuestion('How they handle stress', ['Talk it out', 'Go quiet', 'Stay busy', 'Get outside']),
  QuizQuestion('Favorite kind of movie', ['Comedy', 'Romance', 'Thriller or horror', 'Action or sci-fi']),
  QuizQuestion('Dessert choice', ['Chocolate', 'Ice cream', 'Cake', 'Fruit']),
  QuizQuestion('First thing they do when they get home', ['Change clothes', 'Eat something', 'Check the phone', 'Sit down and rest']),
  QuizQuestion('Surprise they would love most', ['A trip', 'A handwritten note', 'A home-cooked meal', 'A party']),
  QuizQuestion('Spending style', ['Saver', 'Treats themselves', 'Spends on experiences', 'Spends on others']),
  QuizQuestion('Favorite time of day', ['Sunrise', 'Afternoon', 'Sunset', 'Late night']),
  QuizQuestion('Texting style', ['Long messages', 'Short and quick', 'Lots of emojis', 'Prefers calling']),
];

enum CardKind {
  talk('Conversation', '💬'),
  truth('Truth', '🫶'),
  dare('Dare', '🔥');

  const CardKind(this.label, this.emoji);
  final String label, emoji;
}

/// One conversation card: something to talk about, a question to answer honestly, or a small dare.
class ConversationCard {
  const ConversationCard(this.kind, this.text);
  final CardKind kind;
  final String   text;
}

/// Card deck for Conversation cards. A game stores indexes, so add at the END only; never reorder or remove.
const conversationCards = <ConversationCard>[
  ConversationCard(CardKind.talk, 'What is a small moment from this week that made you smile?'),
  ConversationCard(CardKind.talk, 'Where do you see us in five years?'),
  ConversationCard(CardKind.talk, 'What is something you have always wanted to try together?'),
  ConversationCard(CardKind.talk, 'Which memory of us would you relive if you could?'),
  ConversationCard(CardKind.talk, 'What is one thing you are looking forward to?'),
  ConversationCard(CardKind.talk, 'What is a tradition you would like us to start?'),
  ConversationCard(CardKind.talk, 'What did you think when you first saw me?'),
  ConversationCard(CardKind.talk, 'What is something I do that makes you feel loved?'),
  ConversationCard(CardKind.talk, 'If we had a free day with no plans, what would we do?'),
  ConversationCard(CardKind.talk, 'What is a song that reminds you of us?'),
  ConversationCard(CardKind.truth, 'What is something you admire about me that you rarely say?'),
  ConversationCard(CardKind.truth, 'What is a habit of mine that secretly makes you laugh?'),
  ConversationCard(CardKind.truth, 'When did you realise you liked me?'),
  ConversationCard(CardKind.truth, 'What is one thing you are afraid to ask me?'),
  ConversationCard(CardKind.truth, 'What is the most embarrassing thing you have done in front of me?'),
  ConversationCard(CardKind.truth, 'What is something you wish we did more of?'),
  ConversationCard(CardKind.truth, 'What is a dream you have not told many people?'),
  ConversationCard(CardKind.truth, 'What was your first impression of my family or friends?'),
  ConversationCard(CardKind.truth, 'What is one thing you would change about how we spend our time?'),
  ConversationCard(CardKind.truth, 'What moment made you feel closest to me?'),
  ConversationCard(CardKind.dare, 'Send your partner a voice message saying three things you love about them.'),
  ConversationCard(CardKind.dare, 'Do your best impression of your partner.'),
  ConversationCard(CardKind.dare, 'Give your partner a compliment every minute for three minutes.'),
  ConversationCard(CardKind.dare, 'Share a photo of the two of you and say why you love it.'),
  ConversationCard(CardKind.dare, 'Sing a line of a love song to your partner.'),
  ConversationCard(CardKind.dare, 'Draw your partner on the shared canvas in 30 seconds.'),
  ConversationCard(CardKind.dare, 'Say "I love you" in the silliest way you can.'),
  ConversationCard(CardKind.dare, 'Plan a surprise for your partner this week and tell them the day.'),
];
