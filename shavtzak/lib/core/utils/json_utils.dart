import 'dart:convert';

/// Utility class for handling JSON parsing with escaped characters
class JsonUtils {
  /// Parses a JSON string that may have escaped newlines and other characters
  static Map<String, dynamic> parseJsonWithEscapes(String jsonString) {
    // Parse the JSON directly first
    final parsed = jsonDecode(jsonString);

    // Ensure the private_key field is properly formatted
    if (parsed is Map && parsed.containsKey('private_key')) {
      final privateKey = parsed['private_key'] as String;
      // If the private key doesn't have actual newlines, try to convert escaped newlines
      if (!privateKey.contains('\n') && privateKey.contains(r'\n')) {
        // Split on literal \n and join with actual newlines
        final parts = privateKey.split(r'\n');
        parsed['private_key'] = parts.join('\n');
      }
    }

    return Map<String, dynamic>.from(parsed);
  }

  /// Converts a map to JSON string with properly escaped private key
  static String encodeJsonWithEscapedPrivateKey(Map<String, dynamic> map) {
    // Create a copy of the map to avoid modifying the original
    final Map<String, dynamic> copy = Map.from(map);

    // Handle private_key field specifically
    if (copy.containsKey('private_key') && copy['private_key'] is String) {
      final privateKey = copy['private_key'] as String;
      // Replace newlines with escaped newlines
      copy['private_key'] = privateKey.replaceAll('\n', '\\n');
    }

    return jsonEncode(copy);
  }
}