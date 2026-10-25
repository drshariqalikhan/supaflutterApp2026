import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      title: 'Evidence Poster Infographic',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(
          0xFF0A0E17,
        ), // Deep dark navy/slate
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007ACC),
          brightness: Brightness.dark,
        ),
        cardTheme: const CardThemeData(color: Color(0xFF131B26), elevation: 4),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _dbMessage = 'No DB record fetched yet';
  bool _isDbLoading = false;

  Map<String, dynamic>? _infographic;
  bool _isAiLoading = false;
  String? _errorMessage;

  // 1. Fetch DB
  Future<void> _fetchFromDatabase() async {
    setState(() => _isDbLoading = true);
    try {
      final List<Map<String, dynamic>> response = await supabase
          .from('messages')
          .select()
          .order('id', ascending: false)
          .limit(1);

      if (response.isNotEmpty) {
        setState(() {
          _dbMessage = response.first['content'] ?? 'Empty row';
        });
      } else {
        setState(() {
          _dbMessage = 'Table is empty. Tap "Insert Ping" to add a row.';
        });
      }
    } catch (e) {
      setState(() => _dbMessage = 'Database Error: $e');
    } finally {
      setState(() => _isDbLoading = false);
    }
  }

  // 2. Insert DB
  Future<void> _insertToDatabase() async {
    setState(() => _isDbLoading = true);
    try {
      final timestamp = DateTime.now().toLocal().toString().split('.')[0];
      await supabase.from('messages').insert({
        'content': 'Ping from Flutter at $timestamp',
      });
      await _fetchFromDatabase();
    } catch (e) {
      setState(() {
        _dbMessage = 'Insert Error: $e';
        _isDbLoading = false;
      });
    }
  }

  // 3. Generate Infographic via Edge Function
  Future<void> _generateInfographic() async {
    setState(() {
      _isAiLoading = true;
      _errorMessage = null;
    });

    try {
      final FunctionResponse response = await supabase.functions.invoke(
        'hello-function',
      );

      if (response.data is Map && response.data['infographic'] != null) {
        setState(() {
          _infographic = Map<String, dynamic>.from(
            response.data['infographic'],
          );
        });
      } else if (response.data is Map && response.data['error'] != null) {
        setState(() {
          _errorMessage = response.data['error'].toString();
        });
      } else {
        setState(() {
          _errorMessage = 'Unexpected response structure: ${response.data}';
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Function Error:\n$e');
    } finally {
      setState(() => _isAiLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (initializationError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Configuration Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              color: Colors.red.shade900.withAlpha(90),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  initializationError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Evidence Poster Infographic'),
        centerTitle: true,
        backgroundColor: const Color(0xFF0A0E17),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Database Mini-card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    const Icon(
                      Icons.storage,
                      color: Color(0xFF00A3E0),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _dbMessage,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: _isDbLoading ? null : _insertToDatabase,
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      tooltip: 'Insert Ping',
                    ),
                    IconButton(
                      onPressed: _isDbLoading ? null : _fetchFromDatabase,
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: 'Fetch DB',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Poster Generator Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Visual Evidence Brief',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: _isAiLoading ? null : _generateInfographic,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007ACC),
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  icon: const Icon(Icons.auto_graph, size: 18),
                  label: const Text('Generate Poster'),
                ),
              ],
            ),

            const SizedBox(height: 14),

            if (_isAiLoading)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(40.0),
                  child: Column(
                    children: const [
                      CircularProgressIndicator(color: Color(0xFF00A3E0)),
                      SizedBox(height: 16),
                      Text(
                        'Extracting PubMed abstract...\nRendering dark theme poster...',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              )
            else if (_errorMessage != null)
              Card(
                color: Colors.red.shade900.withAlpha(80),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(_errorMessage!, textAlign: TextAlign.center),
                ),
              )
            else if (_infographic == null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(36.0),
                  child: Column(
                    children: const [
                      Icon(
                        Icons.pie_chart_outline,
                        size: 52,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Tap "Generate Poster" to synthesize the latest sepsis study into a dark poster layout.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, height: 1.4),
                      ),
                    ],
                  ),
                ),
              )
            else
              _buildDarkPosterLayout(_infographic!),
          ],
        ),
      ),
    );
  }

  // ================= THE DARK THEMED INFOGRAPHIC POSTER =================
  Widget _buildDarkPosterLayout(Map<String, dynamic> data) {
    const primaryBlue = Color(0xFF00A3E0); // High-contrast electric cyan/blue
    const primaryPurple = Color(0xFFB57EDC); // High-contrast lavender/purple
    const deepBlueHeader = Color(0xFF0F3057); // Deep oceanic navy banner
    const cardSurface = Color(0xFF131B26); // Poster background slate

    final meta = data['meta'] as Map<String, dynamic>? ?? {};
    final title = meta['title'] ?? 'Clinical Study';
    final journal = meta['journal'] ?? 'Journal';
    final year = meta['publication_year']?.toString() ?? '2026';
    final author = meta['lead_author'] ?? 'Authors';
    final pmid = meta['pmid']?.toString() ?? '';

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
        border: Border.all(color: Colors.white.withAlpha(20)),
        boxShadow: [
          //BoxShadow(color: Colors.black80, blurRadius: 20, offset: Offset(0, 8)),
          // ✅ Fixed
          BoxShadow(
            color: Colors.black.withAlpha(200),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---------------- 1. TOP HEADER BANNER ----------------
// ---------------- 1. TOP HEADER BANNER ----------------
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            decoration: const BoxDecoration(
              color: deepBlueHeader,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Category / Condition Pill Tag
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

                // FULL PAPER TITLE AS PRIMARY HEADING
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

                const SizedBox(height: 10),
                Container(
                  height: 3,
                  width: 44,
                  decoration: BoxDecoration(
                    color: primaryBlue,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---------------- 2. HERO STAT BLOCK ----------------
                if (stat1 != null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.monitor_heart,
                        color: primaryPurple,
                        size: 28,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          (stat1['label'] ?? '').toString().toUpperCase(),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: primaryBlue,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Auto-scales down so long strings never overflow
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        stat1['stat_value'] ?? '',
                        style: const TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          color: primaryBlue,
                          letterSpacing: -1.0,
                        ),
                      ),
                    ),
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
                  _buildDarkDottedSeparator(),
                  const SizedBox(height: 16),
                ],

                // ---------------- 3. SECONDARY STAT & GAP ----------------
                if (stat2 != null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          (stat2['label'] ?? '').toString().toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: primaryPurple,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        stat2['stat_value'] ?? '',
                        style: const TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          color: primaryPurple,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ),
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
                _buildDarkDottedSeparator(),
                const SizedBox(height: 16),

                // ---------------- 4. DUAL COMPARISON ----------------
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
                  _buildDarkDottedSeparator(),
                  const SizedBox(height: 16),
                ],

                // ---------------- 5. FINDINGS / BARS ----------------
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

                // ---------------- 6. STAT 3 ----------------
                if (stat3 != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B2433),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            stat3['label'] ?? '',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          stat3['stat_value'] ?? '',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: primaryBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                _buildDarkDottedSeparator(),
                const SizedBox(height: 16),

                // ---------------- 7. CLINICAL TAKEAWAY ----------------
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
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),

          // ---------------- 8. POSTER FOOTER / CITATION ----------------
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0F1520),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
              border: Border(top: BorderSide(color: Colors.white12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'SOURCE & METHODOLOGY',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        color: Colors.white38,
                      ),
                    ),
                    if (pmid.isNotEmpty)
                      Text(
                        'PUBMED ID: $pmid',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: primaryBlue,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '$author • $journal ($year)',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white60,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Dotted separator with dark-theme styling
  Widget _buildDarkDottedSeparator() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double dotSize = 3.5;
        const double space = 4.0;
        final int dotCount = (constraints.maxWidth / (dotSize + space)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(dotCount, (_) {
            return Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(40),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
