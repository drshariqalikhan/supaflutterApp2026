import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Reads credentials passed at runtime via: --dart-define-from-file=env.json
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

String? initializationError;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    initializationError =
        'Missing Supabase credentials!\nPlease run using:\nflutter run ... --dart-define-from-file=env.json';
  } else {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
    } catch (e) {
      initializationError = 'Failed to initialize Supabase:\n$e';
    }
  }

  runApp(const MyApp());
}

// Convenient global accessor for the client
SupabaseClient get supabase => Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Supabase + PubMed Sepsis',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3ECF8E), // Supabase green
          brightness: Brightness.dark,
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1E1E1E),
          elevation: 2,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3ECF8E),
            foregroundColor: Colors.black,
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
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
  // Database state
  String _dbMessage = 'No DB message fetched yet';
  bool _isDbLoading = false;

  // Edge Function / PubMed state
  List<dynamic> _papers = [];
  bool _isPapersLoading = false;
  String? _papersError;

  // 1. Fetch latest record from the Supabase Database
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
          _dbMessage = response.first['content'] ?? 'Empty row content';
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

  // 2. Insert a new record into the Supabase Database
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

  // 3. Call the Edge Function to fetch PubMed papers
  Future<void> _fetchSepsisPapers() async {
    setState(() {
      _isPapersLoading = true;
      _papersError = null;
    });

    try {
      final FunctionResponse response =
          await supabase.functions.invoke('hello-function');

      if (response.data is Map && response.data['papers'] != null) {
        setState(() {
          _papers = response.data['papers'];
        });
      } else if (response.data is Map && response.data['error'] != null) {
        setState(() {
          _papersError = response.data['error'].toString();
        });
      } else {
        setState(() {
          _papersError = 'Unexpected response structure: ${response.data}';
        });
      }
    } catch (e) {
      setState(() {
        _papersError = 'Edge Function invocation error:\n$e';
      });
    } finally {
      setState(() => _isPapersLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // If credentials were missing at launch, show helpful instructions
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
        title: const Text('Supabase + PubMed Sepsis'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---------------- DATABASE CARD ----------------
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.storage, color: Color(0xFF3ECF8E)),
                        SizedBox(width: 8),
                        Text(
                          'PostgreSQL Database',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    if (_isDbLoading)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      )
                    else
                      Text(
                        _dbMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14),
                      ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isDbLoading ? null : _fetchFromDatabase,
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text('Fetch Latest'),
                        ),
                        ElevatedButton.icon(
                          onPressed: _isDbLoading ? null : _insertToDatabase,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Insert Ping'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ---------------- EDGE FUNCTION CARD ----------------
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.biotech, color: Color(0xFF3ECF8E)),
                            SizedBox(width: 8),
                            Text(
                              'Recent Sepsis Papers',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          onPressed:
                              _isPapersLoading ? null : _fetchSepsisPapers,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Fetch'),
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    if (_isPapersLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Column(
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text('Querying PubMed via Edge Function...'),
                            ],
                          ),
                        ),
                      )
                    else if (_papersError != null)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          _papersError!,
                          style: const TextStyle(color: Colors.redAccent),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else if (_papers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'No papers fetched yet.\nTap "Fetch" to call the Edge Function.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _papers.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: Colors.white24),
                        itemBuilder: (context, index) {
                          final paper = _papers[index];
                          final title = paper['title'] ?? 'Untitled';
                          final journal = paper['journal'] ?? 'Unknown journal';
                          final pubDate = paper['pubDate'] ?? '';
                          final pmid = paper['pmid'] ?? '';
                          final List authorsList =
                              (paper['authors'] as List?) ?? [];
                          final authors = authorsList.take(3).join(', ') +
                              (authorsList.length > 3 ? ' et al.' : '');

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (authors.isNotEmpty)
                                  Text(
                                    authors,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF3ECF8E),
                                    ),
                                  ),
                                const SizedBox(height: 2),
                                Text(
                                  '$journal • $pubDate (PMID: $pmid)',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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
}