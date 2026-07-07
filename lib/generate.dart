library generate;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image/src/font/arial_14.dart' as arial14;

enum ApiProvider { groq, openai, gemini, unknown }

class BuiltInLocalGenerator {
  ApiProvider detectApiProvider(String apiKey) {
    if (apiKey.startsWith("gsk_")) {
      return ApiProvider.groq;
    }

    if (apiKey.startsWith("sk-")) {
      return ApiProvider.openai;
    }

    if (apiKey.startsWith("AIza")) {
      return ApiProvider.gemini;
    }

    if (apiKey.startsWith("AQ")) {
      return ApiProvider.gemini;
    }

    return ApiProvider.unknown;
  }

  Future<List<Uint8List>> fetchImages(
    String topic,
    int amount,
    String apiKey,
    void Function(int, double) onProgress,
  ) async {
    final provider = detectApiProvider(apiKey);

    switch (provider) {
      case ApiProvider.openai:
        return fetchOpenAIImages(topic, amount, apiKey, onProgress);
      case ApiProvider.gemini:
        return fetchGeminiImages(topic, amount, apiKey, onProgress);
      default:
        return fetchPolinationsImages(topic, amount, onProgress);
    }
  }

  Future<List<Uint8List>> fetchOpenAIImages(
    String topic,
    int amount,
    String apiKey,
    void Function(int, double) onProgress,
  ) async {
    List<Uint8List> images = [];

    for (int i = 0; i < amount; i++) {
      final response = await http.post(
        Uri.parse("https://api.openai.com/v1/images/generations"),
        headers: {
          "Authorization": "Bearer $apiKey",
          "Content-Type": "application/json",
        },

        body: jsonEncode({
          "model": "gpt-image-1",
          "prompt": topic,
          "size": "1024x1024",
          "n": 1,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception(response.body);
      }

      final data = jsonDecode(response.body);

      final url = data["data"][0]["url"];

      final imgResponse = await http.get(Uri.parse(url));

      images.add(imgResponse.bodyBytes);

      onProgress(i, 100);
    }

    return images;
  }

  Future<List<Uint8List>> fetchGeminiImages(
    String topic,
    int amount,
    String apiKey,
    void Function(int, double) onProgress,
  ) async {
    final images = <Uint8List>[];

    for (int i = 0; i < amount; i++) {
      onProgress(i, 5);

      final url = Uri.parse(
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent?key=$apiKey",
      );

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {
                  "text":
                      "Generate an image of $topic. Return only the image URL.",
                },
              ],
            },
          ],
        }),
      );

      if (response.statusCode != 200) {
        throw Exception(response.body);
      }

      final data = jsonDecode(response.body);
      final imageUrl = data["candidates"][0]["content"]["parts"][0]["text"];

      final imgResponse = await http.get(Uri.parse(imageUrl));

      images.add(imgResponse.bodyBytes);
      onProgress(i, 100);
    }

    return images;
  }

  Future<List<Uint8List>> fetchPolinationsImages(
    String topic,
    int amount,
    void Function(int index, double percent) onProgress,
  ) async {
    final images = <Uint8List>[];

    for (int i = 0; i < amount; i++) {
      onProgress(i, 5);

      final url = Uri.parse(
        "https://image.pollinations.ai/prompt/"
        "${Uri.encodeComponent(topic)}"
        "?width=768"
        "&height=768"
        "&seed=${DateTime.now().microsecondsSinceEpoch}",
      );

      Uint8List? imageBytes;

      for (int attempt = 0; attempt < 10; attempt++) {
        debugPrint("Attempt ${attempt + 1}: $url");

        try {
          final response = await http.get(
            url,
            headers: {"User-Agent": "Mozilla/5.0"},
          );

          debugPrint("Status: ${response.statusCode}");

          if (response.statusCode == 200) {
            imageBytes = response.bodyBytes;
            break;
          }

          debugPrint(response.body);

          if (response.statusCode == 429) {
            debugPrint("Queue full. Waiting...");
            onProgress(i, 10 + attempt * 8);
            await Future.delayed(const Duration(seconds: 5));
            continue;
          }

          if (response.statusCode == 500) {
            debugPrint("Server busy. Retrying...");
            await Future.delayed(const Duration(seconds: 3));
            continue;
          }

          break;
        } catch (e) {
          debugPrint(e.toString());
          await Future.delayed(const Duration(seconds: 3));
        }
      }

      images.add(imageBytes ?? generatePlaceholderImage(topic));
      onProgress(i, 100);

      // Give Pollinations time before requesting the next image.
      if (i < amount - 1) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    return images;
  }

  Future<Map<String, dynamic>> generateArticleWithProvider(
    String topic,
    String apiKey,
  ) async {
    final provider = detectApiProvider(apiKey);

    switch (provider) {
      case ApiProvider.groq:
        return generateArticleWithGroq(topic, apiKey);
      case ApiProvider.openai:
        return generateArticleWithOpenAI(topic, apiKey);
      case ApiProvider.gemini:
        return generateArticleWithGemini(topic, apiKey);
      default:
        throw Exception("Unknown API key type");
    }
  }

  Future<Map<String, dynamic>> generateArticleWithGroq(
    String topic,
    String apiKey,
  ) async {
    final prompt = generateArticle(topic);

    final response = await http.post(
      Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
      headers: {
        "Authorization": "Bearer $apiKey",
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        //"model": "llama-3.3-70b-versatile",
        "model": "llama-3.1-8b-instant",
        "messages": [
          {"role": "user", "content": prompt},
        ],
        "temperature": 0.5,
        "response_format": {"type": "json_object"},
        "max_tokens": 2500,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(response.body);
    }

    final json = jsonDecode(response.body);

    final content = json["choices"][0]["message"]["content"] as String;

    // debugPrint("========== GROQ ==========");
    // debugPrint(content);
    // debugPrint("==========================");

    String cleaned = content.trim();

    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');

    if (start == -1 || end == -1) {
      throw Exception("Groq returned no JSON:\n$cleaned");
    }

    cleaned = cleaned.substring(start, end + 1);

    return jsonDecode(cleaned);
  }

  Future<Map<String, dynamic>> generateArticleWithOpenAI(
    String topic,
    String apiKey,
  ) async {
    final response = await http.post(
      Uri.parse("https://api.openai.com/v1/chat/completions"),
      headers: {
        "Authorization": "Bearer $apiKey",
        "Content-Type": "application/json",
      },

      body: jsonEncode({
        "model": "gpt-4.1-mini",
        "messages": [
          {"role": "user", "content": generateArticle(topic)},
        ],

        "response_format": {"type": "json_object"},
        "temperature": 0.5,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(response.body);
    }

    final data = jsonDecode(response.body);

    return jsonDecode(data["choices"][0]["message"]["content"]);
  }

  Future<Map<String, dynamic>> generateArticleWithGemini(
    String topic,
    String apiKey,
  ) async {
    final url = Uri.parse(
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey",
    );

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},

      body: jsonEncode({
        "contents": [
          {
            "parts": [
              {"text": generateArticle(topic)},
            ],
          },
        ],
        "generationConfig": {"responseMimeType": "application/json"},
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(response.body);
    }

    final data = jsonDecode(response.body);

    final text = data["candidates"][0]["content"]["parts"][0]["text"];

    return jsonDecode(text);
  }

  String generateArticle(String topic) {
    final normalizedTopic = topic.trim().isEmpty
        ? "local knowledge"
        : topic.trim();

    return '''
  You are an experienced Wikipedia editor.

  Write a detailed Wikipedia-style article about "$normalizedTopic".

  Whenever another topic is mentioned that could be explored,
  surround it with double brackets.

  Example:

  Cybernetic gardens combine [[Robotics]], [[Artificial intelligence]] and [[Hydroponics]].

  Images are embedded inside paragraphs.

  Whenever an illustration should appear, insert

  ![[description of image]]

  Example:

  The [[Moon]] is Earth's only natural satellite.
  ![[A realistic view of the Moon from orbit]]
  It affects [[Tides]].

  Return ONLY valid JSON. Do not use markdown code fences.

  Use this schema exactly:

  {
    "title": "string",
    "content": [
      {
        "type": "heading",
        "text": "string"
      },
      {
        "type": "paragraph",
        "text": "string"
      }
    ]
  }

  Requirements

  - Around 1500 words.
  - Between 5 and 10 sections.
  - Each section begins with a heading item.
  - Follow each heading with several paragraph items.
  - Include many [[wiki links]].

  Image requirements

  - Insert ![[...]] markers inside paragraph text only.
  - The first paragraph must contain an image marker.
  - Only add an image marker when it significantly improves understanding.
  - Add 3-6 image markers at most.
  - Would prefer not every section has an image marker.
  - Each image prompt should describe exactly what should be illustrated.

  IMPORTANT

  - Return exactly one JSON object.
  - The first character must be {
  - The last character must be }
  - Do not output Markdown.
  - Do not output HTML.
  - Do not use code fences.
  - Do not explain the JSON.
  - Ensure the JSON is valid.
  ''';
  }

  Uint8List generatePlaceholderImage(String topic) {
    final text = topic.trim().isEmpty ? 'Stars and planets' : topic.trim();
    final image = img.Image(width: 512, height: 512);
    img.fill(image, color: img.ColorRgb8(4, 8, 24));

    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if ((x * 37 + y * 19) % 97 == 0) {
          image.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
    }

    _drawGlow(image, 110, 130, 70, img.ColorRgb8(255, 214, 102));
    _drawGlow(image, 370, 170, 95, img.ColorRgb8(110, 140, 255));
    _drawGlow(image, 310, 340, 70, img.ColorRgb8(255, 120, 120));
    _drawCircle(image, 120, 130, 34, img.ColorRgb8(255, 240, 200));
    _drawCircle(image, 370, 170, 52, img.ColorRgb8(96, 120, 255));
    _drawCircle(image, 310, 340, 34, img.ColorRgb8(255, 90, 90));
    _drawRing(image, 320, 180, 28, 70, img.ColorRgb8(180, 200, 255));
    _drawNebula(image);

    img.drawRect(
      image,
      x1: 36,
      y1: 36,
      x2: 476,
      y2: 476,
      color: img.ColorRgb8(255, 255, 255),
      thickness: 2,
    );

    img.drawString(
      image,
      'Stars and planets',
      font: arial14.arial14,
      x: 56,
      y: 56,
      color: img.ColorRgb8(248, 250, 252),
    );
    img.drawString(
      image,
      text,
      font: arial14.arial14,
      x: 56,
      y: 440,
      color: img.ColorRgb8(226, 232, 240),
    );

    return Uint8List.fromList(img.encodePng(image));
  }

  void _drawGlow(img.Image image, int cx, int cy, int radius, img.Color color) {
    for (var y = cy - radius; y <= cy + radius; y++) {
      for (var x = cx - radius; x <= cx + radius; x++) {
        if (x < 0 || y < 0 || x >= image.width || y >= image.height) {
          continue;
        }
        final dx = x - cx;
        final dy = y - cy;
        final dist = dx * dx + dy * dy;
        if (dist <= radius * radius) {
          final alpha = ((1 - (dist / (radius * radius))) * 0.35).clamp(
            0.0,
            1.0,
          );
          final current = image.getPixel(x, y);
          final r = (current.r * (1 - alpha) + color.r * alpha).round();
          final g = (current.g * (1 - alpha) + color.g * alpha).round();
          final b = (current.b * (1 - alpha) + color.b * alpha).round();
          image.setPixelRgba(x, y, r, g, b, 255);
        }
      }
    }
  }

  void _drawCircle(
    img.Image image,
    int cx,
    int cy,
    int radius,
    img.Color color,
  ) {
    for (var y = cy - radius; y <= cy + radius; y++) {
      for (var x = cx - radius; x <= cx + radius; x++) {
        if (x < 0 || y < 0 || x >= image.width || y >= image.height) {
          continue;
        }
        final dx = x - cx;
        final dy = y - cy;
        if (dx * dx + dy * dy <= radius * radius) {
          image.setPixelRgba(x, y, color.r, color.g, color.b, 255);
        }
      }
    }
  }

  void _drawLandscape(img.Image image) {
    for (var y = 320; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final dx = x - 256;
        final dy = y - 360;
        final wave = (dx * 0.006 + dy * 0.008).toDouble();
        final height = (dy * 0.02 + wave).clamp(-20, 20);
        if (height > -5) {
          image.setPixelRgba(x, y, 24, 49, 64, 255);
        }
      }
    }
  }

  void _drawRing(
    img.Image image,
    int cx,
    int cy,
    int innerRadius,
    int outerRadius,
    img.Color color,
  ) {
    for (var y = cy - outerRadius; y <= cy + outerRadius; y++) {
      for (var x = cx - outerRadius; x <= cx + outerRadius; x++) {
        if (x < 0 || y < 0 || x >= image.width || y >= image.height) {
          continue;
        }
        final dx = x - cx;
        final dy = y - cy;
        final dist = dx * dx + dy * dy;
        final isInner = dist <= innerRadius * innerRadius;
        final isOuter = dist <= outerRadius * outerRadius;
        if (isOuter && !isInner) {
          image.setPixelRgba(x, y, color.r, color.g, color.b, 255);
        }
      }
    }
  }

  void _drawNebula(img.Image image) {
    _drawGlow(image, 220, 240, 90, img.ColorRgb8(130, 78, 255));
    _drawGlow(image, 240, 260, 80, img.ColorRgb8(255, 110, 180));
  }
}

enum ContentType { heading, paragraph }

class ArticleItem {
  ArticleItem({
    required this.type,
    required this.text,
    this.image,
    this.progress = 0,
  });

  final ContentType type;
  final String text;
  Uint8List? image;
  double progress;
}

class InlineImage {
  InlineImage(this.prompt);
  final String prompt;
  Uint8List? image;
  String? error;
}
