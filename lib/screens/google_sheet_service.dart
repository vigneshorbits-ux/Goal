import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';

class GoogleSheetService {
  final String csvUrl;

  GoogleSheetService({required this.csvUrl});

  Future<List<Map<String, dynamic>>> fetchQuestionsFromSheet() async {
    final response = await http.get(Uri.parse(csvUrl));

    if (response.statusCode == 200) {
      // ✅ Decode as UTF-8 to support Tamil/Hindi
      final csvString = utf8.decode(response.bodyBytes);

      // ✅ Parse CSV safely
      final rows = const CsvToListConverter().convert(csvString);

      if (rows.isEmpty) return [];

      final headers = rows.first.map((e) => e.toString()).toList();

      final data = rows.skip(1).map((row) {
        final values = row.map((e) => e.toString()).toList();
        return Map<String, dynamic>.fromIterables(headers, values);
      }).toList();

      return data;
    } else {
      throw Exception('Failed to load questions from Google Sheet');
    }
  }
}
