import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

String? initializationError;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    initializationError = 'Missing Supabase credentials!\nPlease run using:\nflutter run ... --dart-define-from-file=env.json';
  } else {
    try {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    } catch (e) {
      initializationError = 'Failed to initialize Supabase:\n$e';
    }
  }

  runApp(const MyApp());
}

SupabaseClient get supabase => Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Evidence Brief & Clinical Infographics',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007ACC),
          brightness: Brightness.dark,
        ),
        cardTheme: const CardThemeData(color: Color(0xFF131B26), elevation: 4),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF007ACC),
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  String _deviceId = '';

  List<String> _userJournals = [
    'Crit Care Med',
    'Lancet',
    'N Engl J Med',
    'JAMA',
  ];

  List<dynamic> _articles = [];
  bool _isLoadingArticles = false;
  String? _articlesError;

  // Active generating state for inline progress bars
  String? _generatingPmid;
  String _progressStageText = '';

  final List<Map<String, dynamic>> _infographics = [];
  final Set<String> _savedPmids = {};

  @override
  void initState() {
    super.initState();
    _initDeviceAndFeed();
  }

  // 1. Initialize anonymous Device ID and load re-ranked feed
  Future<void> _initDeviceAndFeed() async {
    final prefs = await SharedPreferences.getInstance();
    String? storedId = prefs.getString('anonymous_device_id');
    if (storedId == null) {
      final random = Random();
      storedId =
          'dev_${DateTime.now().millisecondsSinceEpoch}_${random.nextInt(999999)}';
      await prefs.setString('anonymous_device_id', storedId);
    }

    setState(() {
      _deviceId = storedId!;
    });

    _fetchArticlesForJournals();
  }

  // 2. Fetch articles (Re-ranked by Option C Tag Scoring)
  Future<void> _fetchArticlesForJournals() async {
    setState(() {
      _isLoadingArticles = true;
      _articlesError = null;
    });

    try {
      final FunctionResponse response = await supabase.functions.invoke(
        'hello-function',
        body: {
          'action': 'fetch_articles',
          'journals': _userJournals,
          'device_id': _deviceId,
        },
      );

      if (response.data is Map && response.data['articles'] != null) {
        setState(() {
          _articles = response.data['articles'];
        });
      } else if (response.data is Map && response.data['error'] != null) {
        setState(() {
          _articlesError = response.data['error'].toString();
        });
      }
    } catch (e) {
      setState(() => _articlesError = 'Failed to load articles:\n$e');
    } finally {
      setState(() => _isLoadingArticles = false);
    }
  }

  // 3. 1-Click Generate with Progressive Feedback
  Future<void> _generateInfographicForArticle(
    Map<String, dynamic> article,
  ) async {
    final pmid = article['pmid']?.toString() ?? '';
    if (pmid.isEmpty) return;

    // Check if already in carousel
    final alreadyExists = _infographics.any((item) {
      final meta = item['meta'] as Map<String, dynamic>?;
      return meta?['pmid']?.toString() == pmid;
    });

    if (alreadyExists) {
      setState(() => _currentIndex = 1);
      return;
    }

    setState(() {
      _generatingPmid = pmid;
      _progressStageText = '1/3 Fetching abstract from PubMed...';
    });

    // Simulated progress stage updates while request runs
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted && _generatingPmid == pmid) {
        setState(
          () => _progressStageText = '2/3 Extracting clinical facts with AI...',
        );
      }
    });

    Future.delayed(const Duration(milliseconds: 3800), () {
      if (mounted && _generatingPmid == pmid) {
        setState(() => _progressStageText = '3/3 Formatting visual brief...');
      }
    });

    try {
      final FunctionResponse response = await supabase.functions.invoke(
        'hello-function',
        body: {
          'action': 'generate_infographic',
          'pmid': pmid,
          'device_id': _deviceId,
        },
      );

      final data = response.data as Map<String, dynamic>?;

      if (data != null && data['infographic'] != null) {
        final newInfographic = Map<String, dynamic>.from(data['infographic']);
        setState(() {
          _infographics.insert(0, newInfographic);
          _currentIndex = 1; // Transition to brief view
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data?['error'] ?? 'Could not parse brief.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Generation failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _generatingPmid = null;
          _progressStageText = '';
        });
      }
    }
  }

  Future<void> _openArticleUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _toggleSave(String pmid) {
    setState(() {
      if (_savedPmids.contains(pmid)) {
        _savedPmids.remove(pmid);
      } else {
        _savedPmids.add(pmid);
      }
    });
  }

  void _showShareDialog(String title, String url) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131B26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Share Brief / Abstract',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(fontSize: 13, color: Colors.white70),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.link, color: Color(0xFF00A3E0)),
                title: const Text('Copy PubMed Link'),
                subtitle: Text(url, style: const TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                      content: Text('Link copied to clipboard!'),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (initializationError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Configuration Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(initializationError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildFeedTab(),
          _buildInfographicsTab(),
          _buildSettingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF0E141F),
        indicatorColor: const Color(0xFF007ACC).withAlpha(80),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.feed_outlined),
            selectedIcon: const Icon(Icons.feed, color: Color(0xFF00A3E0)),
            label: 'Feed',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _infographics.isNotEmpty,
              label: Text('${_infographics.length}'),
              child: const Icon(Icons.auto_graph_outlined),
            ),
            selectedIcon: const Icon(
              Icons.auto_graph,
              color: Color(0xFF00A3E0),
            ),
            label: 'Briefs',
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings, color: Color(0xFF00A3E0)),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  // ================= TAB 1: FEED (1-CLICK & RE-RANKED) =================
  Widget _buildFeedTab() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Latest Publications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoadingArticles ? null : _fetchArticlesForJournals,
            tooltip: 'Refresh Articles',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF0E141F),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text(
                    'Journals: ',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  ..._userJournals.map(
                    (j) => Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: Chip(
                        label: Text(j, style: const TextStyle(fontSize: 11)),
                        backgroundColor: const Color(0xFF131B26),
                        side: const BorderSide(color: Colors.white12),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoadingArticles
                ? const Center(child: CircularProgressIndicator())
                : _articlesError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Text(_articlesError!, textAlign: TextAlign.center),
                    ),
                  )
                : _articles.isEmpty
                ? const Center(child: Text('No articles found.'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _articles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final article = _articles[index];
                      final pmid = article['pmid']?.toString() ?? '';
                      final isCurrentGenerating = _generatingPmid == pmid;
                      final isRecommended = article['isRecommended'] == true;

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF007ACC)
                                          .withAlpha(35),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      article['journal'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF00A3E0),
                                      ),
                                    ),
                                  ),
                                  if (isRecommended) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFB57EDC)
                                            .withAlpha(35),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: const Color(0xFFB57EDC)
                                              .withAlpha(90),
                                        ),
                                      ),
                                      child: const Text(
                                        '★ Recommended',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFB57EDC),
                                        ),
                                      ),
                                    ),
                                  ],
                                  const Spacer(),
                                  Text(
                                    article['pubDate'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                article['title'] ?? '',
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                article['authors'] ?? '',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 12),

                              // INLINE PROGRESS BAR OR 1-CLICK GENERATE
                              if (isCurrentGenerating)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1B2433),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Color(0xFF00A3E0),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _progressStageText,
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                color: Color(0xFF00A3E0),
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      const ClipRRect(
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(4),
                                        ),
                                        child: LinearProgressIndicator(
                                          minHeight: 4,
                                          color: Color(0xFF00A3E0),
                                          backgroundColor: Colors.white10,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: _generatingPmid != null
                                          ? null
                                          : () =>
                                                _generateInfographicForArticle(
                                                  article,
                                                ),
                                      icon: const Icon(Icons.bolt, size: 16),
                                      label: const Text('Generate Brief'),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ================= TAB 2: BRIEFS & POSTERS =================
  Widget _buildInfographicsTab() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visual Briefs & Abstracts'),
        actions: [
          if (_infographics.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Text(
                  '${_infographics.length} Saved',
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
      body: _infographics.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.auto_graph_outlined,
                      size: 56,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No Briefs Generated Yet',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tap "Generate Brief" on any article in your feed to analyze it.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => setState(() => _currentIndex = 0),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Go to Feed'),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _infographics.length,
              itemBuilder: (context, index) {
                final item = _infographics[index];
                final meta = item['meta'] as Map<String, dynamic>? ?? {};
                final pmid = meta['pmid']?.toString() ?? index.toString();
                final title = meta['title'] ?? 'Brief';
                final isFallback = item['isFallback'] == true;

                return Dismissible(
                  key: Key(pmid),
                  direction: DismissDirection.horizontal,
                  background: Container(
                    margin: const EdgeInsets.only(bottom: 24.0),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 24),
                    child: const Row(
                      children: [
                        Icon(Icons.delete, color: Colors.white, size: 28),
                        SizedBox(width: 8),
                        Text(
                          'Delete',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  secondaryBackground: Container(
                    margin: const EdgeInsets.only(bottom: 24.0),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'Delete',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.delete, color: Colors.white, size: 28),
                      ],
                    ),
                  ),
                  onDismissed: (direction) {
                    final removedPoster = _infographics[index];
                    setState(() {
                      _infographics.removeAt(index);
                    });

                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 3),
                        content: Text('Deleted "$title"'),
                        action: SnackBarAction(
                          label: 'UNDO',
                          textColor: const Color(0xFF00A3E0),
                          onPressed: () {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            setState(() {
                              _infographics.insert(index, removedPoster);
                            });
                          },
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: isFallback
                        ? _buildFormattedAbstractCard(item)
                        : _buildPosterCard(item),
                  ),
                );
              },
            ),
    );
  }

  // ================= TAB 3: SETTINGS =================
  Widget _buildSettingsTab() {
    final TextEditingController journalInputController =
        TextEditingController();

    return Scaffold(
      appBar: AppBar(title: const Text('Preferences & Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Followed Medical Journals',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Articles with abstracts from these journals are queried and re-ranked automatically.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white70,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _userJournals.map((journal) {
                return Chip(
                  label: Text(journal),
                  backgroundColor: const Color(0xFF1B2433),
                  side: const BorderSide(color: Color(0xFF007ACC)),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() {
                      _userJournals.remove(journal);
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: journalInputController,
                    decoration: InputDecoration(
                      labelText: 'Add Journal (e.g. Chest, Circulation)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () {
                    final text = journalInputController.text.trim();
                    if (text.isNotEmpty && !_userJournals.contains(text)) {
                      setState(() {
                        _userJournals.add(text);
                        journalInputController.clear();
                      });
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Popular Presets:',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  [
                    'N Engl J Med',
                    'Lancet',
                    'JAMA',
                    'Crit Care Med',
                    'Intensive Care Med',
                    'Chest',
                    'BMJ',
                  ].where((preset) => !_userJournals.contains(preset)).map((
                    preset,
                  ) {
                    return ActionChip(
                      label: Text('+ $preset'),
                      backgroundColor: const Color(0xFF131B26),
                      onPressed: () =>
                          setState(() => _userJournals.add(preset)),
                    );
                  }).toList(),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF131B26),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.fingerprint,
                    size: 18,
                    color: Color(0xFF00A3E0),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Profile ID: $_deviceId',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white60,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                _fetchArticlesForJournals();
                setState(() => _currentIndex = 0);
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                    content: Text('Preferences saved! Re-ranking feed...'),
                  ),
                );
              },
              icon: const Icon(Icons.save),
              label: const Text('Save & Reload Feed'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= FALLBACK: FORMATTED ABSTRACT CARD (<40%) =================
  Widget _buildFormattedAbstractCard(Map<String, dynamic> data) {
    const primaryBlue = Color(0xFF00A3E0);
    const cardSurface = Color(0xFF131B26);

    final meta = data['meta'] as Map<String, dynamic>? ?? {};
    final title = meta['title'] ?? 'Clinical Study';
    final journal = meta['journal'] ?? 'Journal';
    final year = meta['publication_year']?.toString() ?? '2026';
    final leadAuthor = meta['lead_author'] ?? 'Authors';
    final location = meta['location'] ?? 'Medical Institution';
    final pmid = meta['pmid']?.toString() ?? '';
    final articleUrl =
        meta['article_url'] ?? 'https://pubmed.ncbi.nlm.nih.gov/$pmid/';
    final rawAbstract = (data['rawAbstract'] ?? '').toString();
    final takeaway = (data['clinical_takeaway'] ?? '').toString();

    final isSaved = _savedPmids.contains(pmid);

    return Container(
      decoration: BoxDecoration(
        color: cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(180),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              color: Color(0xFF1D283A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade900.withAlpha(80),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'CLINICAL REVIEW / NARRATIVE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.amberAccent,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$journal • $year',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$leadAuthor • $location',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (takeaway.isNotEmpty && takeaway != 'N/A') ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primaryBlue.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: const Border(
                        left: BorderSide(color: primaryBlue, width: 4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CORE TAKEAWAY',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: primaryBlue,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          takeaway,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                const Text(
                  'STRUCTURED ABSTRACT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white60,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E141F),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Text(
                    rawAbstract.isNotEmpty
                        ? rawAbstract
                        : 'No abstract text available for this paper.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: Colors.white70,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Action Toolbar
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: () => _toggleSave(pmid),
                      icon: Icon(
                        isSaved ? Icons.bookmark : Icons.bookmark_border,
                        color: isSaved ? primaryBlue : Colors.white70,
                      ),
                      tooltip: isSaved ? 'Saved' : 'Save',
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: () => _showShareDialog(title, articleUrl),
                      icon: const Icon(
                        Icons.share_outlined,
                        color: Colors.white70,
                      ),
                      tooltip: 'Share',
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () => _openArticleUrl(articleUrl),
                      icon: const Icon(Icons.open_in_new, size: 15),
                      label: const Text('PubMed Article'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryBlue,
                        side: const BorderSide(color: primaryBlue),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================= MAIN POSTER CARD (>=40%) =================
  Widget _buildPosterCard(Map<String, dynamic> data) {
    const primaryBlue = Color(0xFF00A3E0);
    const primaryPurple = Color(0xFFB57EDC);
    const deepBlueHeader = Color(0xFF0F3057);
    const cardSurface = Color(0xFF131B26);

    final meta = data['meta'] as Map<String, dynamic>? ?? {};
    final title = meta['title'] ?? 'Clinical Study';
    final journal = meta['journal'] ?? 'Journal';
    final year = meta['publication_year']?.toString() ?? '2026';
    final leadAuthor = meta['lead_author'] ?? 'Authors';
    final location = meta['location'] ?? 'Medical Institution';
    final pmid = meta['pmid']?.toString() ?? '';
    final articleUrl =
        meta['article_url'] ?? 'https://pubmed.ncbi.nlm.nih.gov/$pmid/';

    final isSaved = _savedPmids.contains(pmid);

    final problem = data['the_problem'] as Map<String, dynamic>? ?? {};
    final condition = (problem['condition'] ?? 'CLINICAL CONDITION')
        .toString()
        .toUpperCase();
    final knowledgeGap = problem['knowledge_gap'] ?? '';

    final design = data['study_design'] as Map<String, dynamic>? ?? {};
    final studyType = design['type'] ?? 'Clinical Trial';
    final sampleSize = design['sample_size'] ?? 'N/A';
    final interventions =
        (design['interventions_or_groups'] as List?)?.cast<String>() ?? [];

    final stats = (data['key_stat_callouts'] as List?) ?? [];
    final stat1 = stats.isNotEmpty ? stats[0] : null;
    final stat2 = stats.length > 1 ? stats[1] : null;
    final stat3 = stats.length > 2 ? stats[2] : null;

    final findings = (data['major_findings'] as List?)?.cast<String>() ?? [];
    final takeaway = data['clinical_takeaway'] ?? '';

    return Container(
      decoration: BoxDecoration(
        color: cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(180),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            decoration: const BoxDecoration(
              color: deepBlueHeader,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: primaryBlue.withAlpha(35),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: primaryBlue.withAlpha(100)),
                  ),
                  child: Text(
                    condition,
                    style: const TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w800,
                      color: primaryBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                    color: Colors.white,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 3,
                  width: 44,
                  decoration: BoxDecoration(
                    color: primaryBlue,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.people_outline,
                      size: 14,
                      color: primaryPurple,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        leadAuthor,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 14,
                      color: primaryBlue,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        location,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.white70,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (stat1 != null) ...[
                  _buildSelfAdaptingStatBlock(
                    stat1,
                    primaryBlue,
                    icon: Icons.monitor_heart,
                    iconColor: primaryPurple,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 8,
                          ),
                          decoration: BoxDecoration(
                            color: primaryPurple.withAlpha(35),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: primaryPurple.withAlpha(80),
                            ),
                          ),
                          child: Text(
                            sampleSize,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: primaryPurple,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 8,
                          ),
                          decoration: BoxDecoration(
                            color: primaryBlue.withAlpha(35),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: primaryBlue.withAlpha(80),
                            ),
                          ),
                          child: Text(
                            studyType,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: primaryBlue,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildDottedDivider(),
                  const SizedBox(height: 16),
                ],
                if (stat2 != null) ...[
                  _buildSelfAdaptingStatBlock(stat2, primaryPurple),
                ],
                if (knowledgeGap.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B2433),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: primaryBlue,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            knowledgeGap,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _buildDottedDivider(),
                const SizedBox(height: 16),
                if (interventions.isNotEmpty) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: primaryBlue.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: primaryBlue.withAlpha(70),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ARM 1',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: primaryBlue,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                interventions[0],
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: primaryPurple.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: primaryPurple.withAlpha(70),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ARM 2',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: primaryPurple,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                interventions.length > 1
                                    ? interventions[1]
                                    : 'Control',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildDottedDivider(),
                  const SizedBox(height: 16),
                ],
                const Text(
                  'OUTCOME MEASURES & FINDINGS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 10),
                ...findings.asMap().entries.map((entry) {
                  final index = entry.key;
                  final text = entry.value;
                  final barColor = index.isEven ? primaryBlue : primaryPurple;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 3),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: barColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                text,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: 0.45 + (index * 0.25) % 0.5,
                            backgroundColor: Colors.white10,
                            valueColor: AlwaysStoppedAnimation<Color>(barColor),
                            minHeight: 5,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                if (stat3 != null) ...[
                  const SizedBox(height: 4),
                  _buildSelfAdaptingStatBlock(
                    stat3,
                    primaryBlue,
                    isBoxed: true,
                  ),
                ],
                const SizedBox(height: 16),
                _buildDottedDivider(),
                const SizedBox(height: 16),
                if (takeaway.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primaryBlue.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: const Border(
                        left: BorderSide(color: primaryBlue, width: 4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CLINICAL TAKEAWAY',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                            color: primaryBlue,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          takeaway,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 10,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton.filledTonal(
                          onPressed: () => _toggleSave(pmid),
                          icon: Icon(
                            isSaved ? Icons.bookmark : Icons.bookmark_border,
                            color: isSaved ? primaryBlue : Colors.white70,
                          ),
                          tooltip: isSaved ? 'Saved' : 'Save',
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: () => _showShareDialog(title, articleUrl),
                          icon: const Icon(
                            Icons.share_outlined,
                            color: Colors.white70,
                          ),
                          tooltip: 'Share',
                        ),
                      ],
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openArticleUrl(articleUrl),
                      icon: const Icon(Icons.open_in_new, size: 15),
                      label: const Text('Full Article'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryBlue,
                        side: const BorderSide(color: primaryBlue),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0F1520),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
              border: Border(top: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '$journal ($year)',
                    style: const TextStyle(fontSize: 10, color: Colors.white60),
                  ),
                ),
                if (pmid.isNotEmpty)
                  Text(
                    'PUBMED: $pmid',
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: primaryBlue,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelfAdaptingStatBlock(
    Map<String, dynamic> stat,
    Color accentColor, {
    IconData? icon,
    Color? iconColor,
    bool isBoxed = false,
  }) {
    final rawLabel = (stat['label'] ?? '').toString().trim();
    final rawValue = (stat['stat_value'] ?? '').toString().trim();

    final isShortNumber = rawValue.length <= 10;

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rawLabel.isNotEmpty) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Icon(icon, color: iconColor ?? accentColor, size: 22),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  rawLabel.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isBoxed ? Colors.white70 : accentColor,
                    height: 1.25,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        if (rawValue.isNotEmpty) ...[
          if (isShortNumber)
            Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  rawValue,
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    color: accentColor,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            )
          else
            Text(
              rawValue,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isBoxed ? accentColor : Colors.white,
                height: 1.35,
              ),
            ),
        ],
      ],
    );

    if (isBoxed) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1B2433),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: content,
      );
    }

    return content;
  }

  Widget _buildDottedDivider() {
    return SizedBox(
      height: 3,
      width: double.infinity,
      child: CustomPaint(
        painter: _DottedLinePainter(color: Colors.white.withAlpha(35)),
      ),
    );
  }
}

class _DottedLinePainter extends CustomPainter {
  final Color color;
  _DottedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    double startX = 0;
    const double step = 7.0;
    while (startX < size.width) {
      canvas.drawCircle(Offset(startX, size.height / 2), 1.4, paint);
      startX += step;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
