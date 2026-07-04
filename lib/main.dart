import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image/src/font/arial_14.dart' as arial14;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'hallucinator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const LocalGenerationPage(),
    );
  }
}

class LocalGenerationPage extends StatefulWidget {
  const LocalGenerationPage({super.key});

  @override
  State<LocalGenerationPage> createState() => _LocalGenerationPageState();
}

class BuiltInLocalGenerator {
  Map<String, dynamic> buildStableHordeRequest(String topic, int amount) {
    final normalizedTopic = topic.trim().isEmpty ? 'fantasy landscape' : topic.trim();
    return {
      'prompt': normalizedTopic,
      'params': {
        'sampler_name': 'k_dpmpp_2m',
        'cfg_scale': 7.5,
        'height': 768,
        'width': 768,
        'steps': 30,
        'n': amount,
      },
      'nsfw': false,
      'censor_nsfw': true,
      'trusted_workers': false,
      'models': ['Deliberate'],
    };
  }

  Future<List<Uint8List>> fetchPolinationsAiImages(
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
        "&seed=${DateTime.now().microsecondsSinceEpoch}"
      );

      Uint8List? imageBytes;

      for (int attempt = 0; attempt < 10; attempt++) {
        debugPrint("Attempt ${attempt + 1}: $url");

        try {
          final response = await http.get(
            url,
            headers: {
              "User-Agent": "Mozilla/5.0",
            },
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
        "model": "llama-3.3-70b-versatile",
        //"model": "llama-3.1-8b-instant",
        "messages": [
          {
            "role": "user",
            "content": prompt
          }
        ],
        "temperature": 0.5,
        "response_format": {
          "type": "json_object"
        },
        "max_tokens": 2500
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(response.body);
    }

    final json = jsonDecode(response.body);

    final content =
        json["choices"][0]["message"]["content"] as String;
        
    debugPrint("========== GROQ ==========");
    debugPrint(content);
    debugPrint("==========================");

    String cleaned = content.trim();

    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');

    if (start == -1 || end == -1) {
      throw Exception("Groq returned no JSON:\n$cleaned");
    }

    cleaned = cleaned.substring(start, end + 1);

    return jsonDecode(cleaned);
  }

  String generateArticle(String topic) {
    final normalizedTopic =
        topic.trim().isEmpty ? "local knowledge" : topic.trim();

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

  Return ONLY valid JSON.

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
  - Insert image items naturally where an illustration would help.
  - Usually include 5–10 image items.
  - Each image prompt should describe exactly what should be illustrated.
  - Include many [[wiki links]].
  - Do not mention images in paragraph text.

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
          final alpha = ((1 - (dist / (radius * radius))) * 0.35).clamp(0.0, 1.0);
          final current = image.getPixel(x, y);
          final r = (current.r * (1 - alpha) + color.r * alpha).round();
          final g = (current.g * (1 - alpha) + color.g * alpha).round();
          final b = (current.b * (1 - alpha) + color.b * alpha).round();
          image.setPixelRgba(x, y, r, g, b, 255);
        }
      }
    }
  }

  void _drawCircle(img.Image image, int cx, int cy, int radius, img.Color color) {
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

  void _drawRing(img.Image image, int cx, int cy, int innerRadius, int outerRadius, img.Color color) {
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

enum ContentType {
  heading,
  paragraph,
}

class ArticleItem {
  ArticleItem({
    required this.type,
    required this.text,
    this.image,
    this.progress = 0,
  });

  final ContentType type;

  // heading text
  // paragraph text
  // image prompt
  final String text;

  Uint8List? image;

  double progress;
}

class InlineImage {
  InlineImage(this.prompt);

  final String prompt;

  Uint8List? image;

  double progress = 0;
}

class _LocalGenerationPageState extends State<LocalGenerationPage> {
  final TextEditingController _searchController = TextEditingController(
    text: '',
  );
  final TextEditingController _groqKeyController = TextEditingController();
  final BuiltInLocalGenerator _generator = BuiltInLocalGenerator();
  final Map<String, InlineImage> _inlineImages = {};

  bool _showGroqKey = false;
  String _groqApiKey = "";

  bool _isBusy = false;
  String _statusMessage = 'Search locally to generate a wiki-style page.';
  String _pageTitle = '';
  String _activeQuery = '';
  List<ArticleItem> _items = [];
  
  @override
  void initState() {
    super.initState();
    _loadGroqKey();
  }

  Future<void> _loadGroqKey() async {
    final prefs = await SharedPreferences.getInstance();

    final key = prefs.getString('groqKey') ?? '';

    setState(() {
      _groqApiKey = key;
      _groqKeyController.text = key;
    });
  }

  Future<void> _saveGroqKey(String key) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('groqKey', key);

    setState(() {
      _groqApiKey = key;
    });
  }

  Future<void> _searchLocalWeb() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() => _statusMessage = 'Enter a search term first.');
      return;
    }

    setState(() {
      _isBusy = true;
      _statusMessage = 'Generating a wiki-style page...';
      _pageTitle = '';
      // _pageBody = '';
      _activeQuery = query;
    });

    try {
      final article = await _generator.generateArticleWithGroq(
        query,
        _groqApiKey,
      );

      final items = _itemsFromJson(article);
      final title = article["title"] as String;

      setState(() {
        _items = items;_inlineImages.clear();

        final regex = RegExp(r'!\[\[(.*?)\]\]');

        for (final item in _items) {

          if (item.type != ContentType.paragraph) continue;

          for (final match in regex.allMatches(item.text)) {

            final prompt = match.group(1)!.trim();

            _inlineImages.putIfAbsent(
              prompt,
              () => InlineImage(prompt),
            );

          }

        }
        _pageTitle = title;
        _statusMessage = 'Generating images...';
      });

      for (final image in _inlineImages.values) {
        await _loadInlineImage(image);
      }
      
    } catch (error) {
      final fallbackImage = _generator.generatePlaceholderImage(query);
      setState(() {
        _pageTitle = _extractTitle(_generator.generateArticle(query), query);
        _statusMessage = 'Image generation was unavailable, so the app used a local fallback image: $error';
      });
    } finally {
      setState(() => _isBusy = false);
    }
  }

  String _extractTitle(String text, String query) {
    final lines = text.split('\n').where((line) => line.trim().isNotEmpty).toList();
    for (final line in lines) {
      if (line.toLowerCase().startsWith('title:')) {
        return line.replaceFirst(RegExp(r'^title:\s*', caseSensitive: false), '').trim();
      }
    }

    return query.split(' ').take(5).join(' ').trim().isNotEmpty
        ? query.split(' ').take(5).join(' ').trim()
        : 'Local search result';
  }

  List<ArticleItem> _itemsFromJson(
      Map<String, dynamic> article) {

    final list = article["content"] as List;

    return list.map((item) {

      switch (item["type"]) {

        case "heading":
          return ArticleItem(
            type: ContentType.heading,
            text: item["text"],
          );

        case "paragraph":
          return ArticleItem(
            type: ContentType.paragraph,
            text: item["text"],
          );

        default:
          throw Exception("Unknown content type");
      }

    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _groqKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('hallucinator'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _searchLocalWeb(),
                        decoration: const InputDecoration(
                          hintText: 'Search hallucinator',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _isBusy ? null : _searchLocalWeb,
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ],
                ),
              ),
            ),
            if (_isBusy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_pageTitle.isEmpty) // && _pageBody.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                        child: Text(
                          'Search for a topic to create a Wikipedia-style page with text and illustrations.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      )
                    else ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                        child: Column(

                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: _items.map((item) {

                            switch (item.type) {

                              case ContentType.heading:

                                return Padding(
                                  padding: const EdgeInsets.only(top: 20),
                                  child: Text(
                                    item.text,
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                );

                              case ContentType.paragraph:

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: _buildWikiText(item.text),
                                );

                            }

                          }).toList(),

                        )
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      _statusMessage,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  Future<void> _loadInlineImage(
      InlineImage image) async {

    final images =
        await _generator.fetchPolinationsAiImages(

      image.prompt,

      1,

      (_, percent) {

        if (!mounted) return;

        setState(() {
          image.progress = percent;
        });

      },
    );

    if (!mounted) return;

    setState(() {

      image.image = images.first;

      image.progress = 100;

    });

  }

  Widget _buildWikiText(String text) {
    final imageRegex = RegExp(r'!\[\[(.*?)\]\]');
    final match = imageRegex.firstMatch(text);

    // No image in this paragraph
    if (match == null) {
      return _buildRichText(text);
    }

    final prompt = match.group(1)!.trim();

    final before = text.substring(0, match.start).trim();
    final after = text.substring(match.end).trim();

    final image = _inlineImages[prompt];
    
    final Widget imageWidget = image == null
    ? const SizedBox()
    : image.image == null
        ? AspectRatio(
            aspectRatio: 1,
            child: Center(
              child: CircularProgressIndicator(
                value: image.progress / 100,
              ),
            ),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              image.image!,
              fit: BoxFit.cover,
            ),
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              if (before.isNotEmpty)
                _buildRichText(before),

              if (after.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildRichText(after),
              ],
            ],
          ),
        ),

        const SizedBox(width: 16),

        SizedBox(
          width: 220,
          child: image == null
              ? const SizedBox()
              : image.image == null
                  ? AspectRatio(
                      aspectRatio: 1,
                      child: Center(
                        child: CircularProgressIndicator(
                          value: image.progress / 100,
                        ),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        image.image!,
                        fit: BoxFit.cover,
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildRichText(String text) {
    final spans = <InlineSpan>[];

    final regex = RegExp(r'\[\[(.*?)\]\]');

    int last = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > last) {
        spans.add(
          TextSpan(
            text: text.substring(last, match.start),
          ),
        );
      }

      final topic = match.group(1)!;

      spans.add(
        TextSpan(
          text: topic,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => _followWikiLink(topic),
        ),
      );

      last = match.end;
    }

    if (last < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(last),
        ),
      );
    }

    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
        children: spans,
      ),
    );
  }

  Future<void> _followWikiLink(String topic) async {
    _searchController.text = topic;
    await _searchLocalWeb();
  }

  void _showSettings() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Settings"),
              content: SizedBox(
                width: 450,
                child: TextField(
                  controller: _groqKeyController,
                  obscureText: !_showGroqKey,
                  decoration: InputDecoration(
                    labelText: "Groq API Key",
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showGroqKey
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setDialogState(() {
                          _showGroqKey = !_showGroqKey;
                        });
                      },
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text("Cancel"),
                ),
                FilledButton(
                  onPressed: () async {
                    await _saveGroqKey(
                      _groqKeyController.text.trim(),
                    );

                    if (!mounted) return;

                    Navigator.pop(context);

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Groq key saved"),
                      ),
                    );
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
