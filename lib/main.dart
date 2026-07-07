import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'generate.dart';

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

class _LocalGenerationPageState extends State<LocalGenerationPage> {
  final TextEditingController _searchController = TextEditingController(
    text: '',
  );
  final TextEditingController _apiKeyController = TextEditingController();
  final BuiltInLocalGenerator _generator = BuiltInLocalGenerator();
  final Map<String, InlineImage> _inlineImages = {};

  bool _showApiKey = false;
  String _apiKey = "";

  bool _articleBusy = false;
  bool _imagesBusy = false;
  String _statusMessage = 'Search locally to generate a wiki-style page.';
  String _pageTitle = '';
  String _activeQuery = '';
  List<ArticleItem> _items = [];

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();

    final key = prefs.getString('apiKey') ?? '';

    setState(() {
      _apiKey = key;
      _apiKeyController.text = key;
    });
  }

  Future<void> _saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('apiKey', key);

    setState(() {
      _apiKey = key;
    });
  }

  Future<void> _searchLocalWeb() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() => _statusMessage = 'Enter a search term first.');
      return;
    }

    setState(() {
      _articleBusy = true;
      _imagesBusy = false;
      _statusMessage = 'Generating a wiki-style page...';
      _pageTitle = '';
      // _pageBody = '';
      _activeQuery = query;
    });

    try {
      final article = await _generator.generateArticleWithProvider(
        query,
        _apiKey,
      );

      final items = _itemsFromJson(article);
      final title = article["title"] as String;

      setState(() {
        _items = items;
        _inlineImages.clear();

        final regex = RegExp(r'!\[\[(.*?)\]\]');

        for (final item in _items) {
          if (item.type != ContentType.paragraph) continue;

          for (final match in regex.allMatches(item.text)) {
            final prompt = match.group(1)!.trim();

            _inlineImages.putIfAbsent(prompt, () => InlineImage(prompt));
          }
        }
        _pageTitle = title;
        _articleBusy = false;
        _imagesBusy = _inlineImages.isNotEmpty;
        _statusMessage = _inlineImages.isEmpty
            ? 'Done.'
            : 'Generating images...';
      });

      final imagesToLoad = List<InlineImage>.from(_inlineImages.values);

      _loadImagesForCurrentSearch(query, imagesToLoad);
      
    } catch (error) {
      final fallbackArticle = _generator.generateArticle(query);

      setState(() {
        _pageTitle = _extractTitle(fallbackArticle, query);
        _items = [
          ArticleItem(
            type: ContentType.paragraph,
            text:
                'The online article generator was unavailable, so this local fallback page was created for "$query".',
          ),
        ];
    _articleBusy = false;
    _imagesBusy = false;
        _statusMessage =
            'Article generation failed, so a local fallback page was used: $error';
      });
    }
  }

  Future<void> _loadImagesForCurrentSearch(
    String query,
    List<InlineImage> imagesToLoad,
  ) async {
    for (final image in imagesToLoad) {
      await _loadInlineImage(image);

      if (!mounted) return;

      // User has started another search. Stop updating old page state.
      if (_activeQuery != query) return;
    }

    if (!mounted) return;

    if (_activeQuery == query) {
      setState(() {
        _imagesBusy = false;
        _statusMessage = 'Done.';
      });
    }
  }

  String _extractTitle(String text, String query) {
    final lines = text
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    for (final line in lines) {
      if (line.toLowerCase().startsWith('title:')) {
        return line
            .replaceFirst(RegExp(r'^title:\s*', caseSensitive: false), '')
            .trim();
      }
    }

    return query.split(' ').take(5).join(' ').trim().isNotEmpty
        ? query.split(' ').take(5).join(' ').trim()
        : 'Local search result';
  }

  List<ArticleItem> _itemsFromJson(Map<String, dynamic> article) {
    final list = article["content"] as List;

    return list.map((item) {
      switch (item["type"]) {
        case "heading":
          return ArticleItem(type: ContentType.heading, text: item["text"]);

        case "paragraph":
          return ArticleItem(type: ContentType.paragraph, text: item["text"]);

        default:
          throw Exception("Unknown content type");
      }
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _apiKeyController.dispose();
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
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
                      onPressed: _articleBusy ? null : _searchLocalWeb,
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ],
                ),
              ),
            ),
            if (_articleBusy || _imagesBusy)
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
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
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
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
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
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                );

                              case ContentType.paragraph:
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: _buildWikiText(item.text),
                                );
                            }
                          }).toList(),
                        ),
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

  Future<void> _loadInlineImage(InlineImage image) async {
    try {
      final images = await _generator.fetchImages(
        image.prompt,
        1,
        _apiKey,
        (_, __) {},
      );

      if (!mounted) return;

      setState(() {
        image.image = images.first;
        image.error = null;
      });
    } catch (error) {
      final fallbackImage = _generator.generatePlaceholderImage(image.prompt);

      if (!mounted) return;

      setState(() {
        image.image = fallbackImage;
        image.error = error.toString();
      });
    }
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

    // 1. Build the unified Wikipedia frame container
    final Widget wikiImageFrame = image == null
        ? const SizedBox()
        : Container(
            padding: const EdgeInsets.all(
              3.0,
            ), // Standard Wikipedia frame internal padding
            decoration: BoxDecoration(
              color: const Color(
                0xFFF8F9FA,
              ), // Wikipedia thumbnail background fill
              border: Border.all(
                color: const Color(
                  0xFFA2A9B1,
                ), // Wikipedia light gray outer border
                width: 1.0,
              ),
            ),
            child: image.image == null
                ? AspectRatio(
                    aspectRatio: 1,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFFEAECF0),
                            width: 1.0,
                          ),
                        ),
                        child: Image.memory(image.image!, fit: BoxFit.cover),
                      ),
                      const SizedBox(height: 5),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3.0,
                          vertical: 2.0,
                        ),
                        child: Text(
                          prompt,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF202122),
                            fontFamily: 'sans-serif',
                          ),
                        ),
                      ),
                      if (image.error != null) ...[
                        const SizedBox(height: 4),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 3.0),
                          child: Text(
                            'Fallback image used',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          );

    // 2. Return the structural UI row layout
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (before.isNotEmpty) _buildRichText(before),
              if (after.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildRichText(after),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width:
              220, // Strict sidebar layout width block matching desktop layout rules
          child:
              wikiImageFrame, // CRITICAL FIX: Reference the styled frame variable here!
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
        spans.add(TextSpan(text: text.substring(last, match.start)));
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
      spans.add(TextSpan(text: text.substring(last)));
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
                  controller: _apiKeyController,
                  obscureText: !_showApiKey,
                  decoration: InputDecoration(
                    labelText: "Groq/OpenAI/Gemini API Key",
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showApiKey ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setDialogState(() {
                          _showApiKey = !_showApiKey;
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
                    await _saveApiKey(_apiKeyController.text.trim());

                    if (!mounted) return;

                    Navigator.pop(context);

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Groq/OpenAi/Gemini API key saved"),
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
