import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

// Read keys from compile-time flags (--dart-define-from-file=env.json)
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

String? initializationError;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Validate that the keys were provided
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    initializationError = 'Missing Supabase credentials!\nPlease provide --dart-define-from-file=env.json when running.';
  } else {
    try {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    } catch (e) {
      initializationError = 'Failed to initialize Supabase: $e';
    }
  }

  runApp(const HomeWidget());

  // Wrap runApp with DevicePreview
  // runApp(DevicePreview());
}

// Convenient getter for the Supabase client
SupabaseClient get supabase => Supabase.instance.client;


class HomeWidget extends StatelessWidget {
  const HomeWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Supabase + Flutter',
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
        cardTheme: const CardThemeData(color: Color(0xFF1E1E1E), elevation: 2),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3ECF8E),
            foregroundColor: Colors.black, // Dark text on green
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
  String _dbMessage = 'No DB message fetched yet';
  String _functionMessage = 'Function not called yet';
  bool _isLoading = false;

  // 1. Fetch latest message from Database
  Future<void> _fetchFromDatabase() async {
    setState(() => _isLoading = true);
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
          _dbMessage = 'No messages found in the table.';
        });
      }
    } catch (e) {
      setState(() => _dbMessage = 'DB Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 2. Insert a new message into Database
  Future<void> _insertToDatabase() async {
    setState(() => _isLoading = true);
    try {
      final timestamp = DateTime.now().toLocal().toString().split('.')[0];
      await supabase.from('messages').insert({
        'content': 'Ping from Flutter at $timestamp',
      });
      // Refresh display after insert
      await _fetchFromDatabase();
    } catch (e) {
      setState(() {
        _dbMessage = 'Insert Error: $e';
        _isLoading = false;
      });
    }
  }

  // 3. Invoke Supabase Edge Function
  Future<void> _callEdgeFunction() async {
    setState(() => _isLoading = true);
    try {
      final FunctionResponse response = await supabase.functions.invoke(
        'hello-function',
      );

      setState(() {
        if (response.data is Map && response.data['message'] != null) {
          _functionMessage = response.data['message'];
        } else {
          _functionMessage = response.data.toString();
        }
      });
    } catch (e) {
      setState(() => _functionMessage = 'Function Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // If credentials failed at startup, show friendly error instead of crashing
    if (initializationError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Configuration Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              color: Colors.red.shade900.withAlpha(80),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  initializationError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Supabase AND Flutter'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 20.0),
                  child: CircularProgressIndicator(),
                ),

              // Database Card
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
                            'Database Operations',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
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
                            onPressed: _isLoading ? null : _fetchFromDatabase,
                            icon: const Icon(Icons.download, size: 18),
                            label: const Text('Fetch Latest'),
                          ),
                          ElevatedButton.icon(
                            onPressed: _isLoading ? null : _insertToDatabase,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Insert Ping'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Edge Function Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bolt, color: Color(0xFF3ECF8E)),
                          SizedBox(width: 8),
                          Text(
                            'Edge Function',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Text(
                        _functionMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _callEdgeFunction,
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Invoke Function'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
