import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const baseUrl = "http://10.0.2.2:5000";

  static Future<Map<String, dynamic>> getSummary() async {
    final res = await http.get(Uri.parse("$baseUrl/metrics/summary"));
    return jsonDecode(res.body);
  }

  static Future<List<dynamic>> getTokens() async {
    final res = await http.get(Uri.parse("$baseUrl/metrics/tokens"));
    return jsonDecode(res.body);
  }
}
