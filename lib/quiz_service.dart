import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;

Future<List<Map<String, dynamic>>> scrapeQuestions(String category, String difficulty) async {
  try {
    // Example URL (replace with actual URL)
    final url = 'https://www.sawaal.com//$category/$difficulty';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final document = parse(response.body);
      final questions = document.querySelectorAll('.question');
      final options = document.querySelectorAll('.options');

      List<Map<String, dynamic>> quizQuestions = [];
      for (int i = 0; i < questions.length; i++) {
        final questionText = questions[i].text.trim();
        final optionElements = options[i].querySelectorAll('li');
        final correctOption = options[i].querySelector('.correct')?.text.trim();

        quizQuestions.add({
          'question': questionText,
          'options': optionElements.map((e) => e.text.trim()).toList(),
          'answer': correctOption,
        });
      }

      return quizQuestions;
    } else {
      throw Exception('Failed to fetch quiz questions. Status code: ${response.statusCode}');
    }
  } catch (e) {
    print('Error scraping questions: $e');
    return [];
  }
}
