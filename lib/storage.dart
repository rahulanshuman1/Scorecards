import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class Store {
  static const _key = 'matches_v1';

  static Future<List<SportMatch>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((j) => SportMatch.fromJson(Map<String, dynamic>.from(j)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<SportMatch> matches) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(matches.map((m) => m.toJson()).toList()));
  }
}
