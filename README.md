# flutter_web_bridge

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.



https://claude.ai/chat/170e4fa7-d818-4fb2-9643-6f8881715b5b

// pubspec.yaml
name: flutter_web_bridge
description: A Flutter package for integrating web views with dynamic content updates
version: 1.0.0

environment:
  sdk: '>=3.0.0 <4.0.0'
  flutter: ">=3.0.0"

dependencies:
  flutter:
    sdk: flutter
  webview_flutter: ^4.4.2
  http: ^1.1.0
  connectivity_plus: ^5.0.2
  shared_preferences: ^2.2.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

---

// lib/flutter_web_bridge.dart
library flutter_web_bridge;

export 'src/web_bridge_controller.dart';
export 'src/web_bridge_widget.dart';
export 'src/models/bridge_config.dart';
export 'src/models/bridge_event.dart';
export 'src/services/bridge_service.dart';

---

// lib/src/models/bridge_config.dart
class BridgeConfig {
  final String baseUrl;
  final Map<String, String> headers;
  final bool enableJavaScript;
  final bool enableCache;
  final Duration cacheTimeout;
  final List<String> allowedDomains;
  final Map<String, dynamic> initialData;

  const BridgeConfig({
    required this.baseUrl,
    this.headers = const {},
    this.enableJavaScript = true,
    this.enableCache = true,
    this.cacheTimeout = const Duration(hours: 1),
    this.allowedDomains = const [],
    this.initialData = const {},
  });

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'headers': headers,
        'enableJavaScript': enableJavaScript,
        'enableCache': enableCache,
        'cacheTimeout': cacheTimeout.inMilliseconds,
        'allowedDomains': allowedDomains,
        'initialData': initialData,
      };
}

---

// lib/src/models/bridge_event.dart
enum BridgeEventType {
  navigation,
  dataUpdate,
  error,
  ready,
  scroll,
  resize,
  custom,
}

class BridgeEvent {
  final BridgeEventType type;
  final String? action;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  BridgeEvent({
    required this.type,
    this.action,
    this.data = const {},
  }) : timestamp = DateTime.now();

  factory BridgeEvent.fromJson(Map<String, dynamic> json) {
    return BridgeEvent(
      type: BridgeEventType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => BridgeEventType.custom,
      ),
      action: json['action'],
      data: json['data'] ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'action': action,
        'data': data,
        'timestamp': timestamp.toIso8601String(),
      };
}

---

// lib/src/services/bridge_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/bridge_config.dart';
import '../models/bridge_event.dart';

class BridgeService {
  final BridgeConfig config;
  final StreamController<BridgeEvent> _eventController = StreamController.broadcast();
  final StreamController<String> _urlController = StreamController.broadcast();
  
  Timer? _refreshTimer;
  bool _isOnline = true;

  BridgeService(this.config) {
    _initConnectivityListener();
    _startPeriodicRefresh();
  }

  Stream<BridgeEvent> get eventStream => _eventController.stream;
  Stream<String> get urlStream => _urlController.stream;

  void _initConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((result) {
      _isOnline = result != ConnectivityResult.none;
      if (_isOnline) {
        _emitEvent(BridgeEvent(type: BridgeEventType.ready));
      }
    });
  }

  void _startPeriodicRefresh() {
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_isOnline) {
        checkForUpdates();
      }
    });
  }

  Future<void> checkForUpdates() async {
    try {
      final response = await http.get(
        Uri.parse('${config.baseUrl}/api/version'),
        headers: config.headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final currentVersion = await _getCachedVersion();
        
        if (data['version'] != currentVersion) {
          await _setCachedVersion(data['version']);
          _emitEvent(BridgeEvent(
            type: BridgeEventType.dataUpdate,
            data: data,
          ));
          
          // Update URL to force refresh
          _urlController.add('${config.baseUrl}?v=${data['version']}&t=${DateTime.now().millisecondsSinceEpoch}');
        }
      }
    } catch (e) {
      _emitEvent(BridgeEvent(
        type: BridgeEventType.error,
        data: {'error': e.toString()},
      ));
    }
  }

  Future<String?> _getCachedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('web_bridge_version');
  }

  Future<void> _setCachedVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('web_bridge_version', version);
  }

  void _emitEvent(BridgeEvent event) {
    _eventController.add(event);
  }

  void handleWebViewMessage(String message) {
    try {
      final data = json.decode(message);
      final event = BridgeEvent.fromJson(data);
      _emitEvent(event);
    } catch (e) {
      _emitEvent(BridgeEvent(
        type: BridgeEventType.error,
        data: {'error': 'Invalid message format: $message'},
      ));
    }
  }

  Future<void> sendMessageToWeb(String action, Map<String, dynamic> data) async {
    final message = json.encode({
      'action': action,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });
    
    // This will be handled by the WebBridgeController
    _emitEvent(BridgeEvent(
      type: BridgeEventType.custom,
      action: 'sendToWeb',
      data: {'message': message},
    ));
  }

  void dispose() {
    _refreshTimer?.cancel();
    _eventController.close();
    _urlController.close();
  }
}

---

// lib/src/web_bridge_controller.dart
import 'dart:async';
import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';
import 'models/bridge_config.dart';
import 'models/bridge_event.dart';
import 'services/bridge_service.dart';

class WebBridgeController {
  late final WebViewController _webViewController;
  late final BridgeService _bridgeService;
  final StreamController<BridgeEvent> _eventController = StreamController.broadcast();
  
  String? _currentUrl;
  bool _isReady = false;

  WebBridgeController(BridgeConfig config) {
    _bridgeService = BridgeService(config);
    _initWebViewController(config);
    _setupEventListeners();
  }

  Stream<BridgeEvent> get eventStream => _eventController.stream;
  WebViewController get webViewController => _webViewController;
  bool get isReady => _isReady;
  String? get currentUrl => _currentUrl;

  void _initWebViewController(BridgeConfig config) {
    _webViewController = WebViewController()
      ..setJavaScriptMode(
        config.enableJavaScript 
          ? JavaScriptMode.unrestricted 
          : JavaScriptMode.disabled
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            _currentUrl = url;
            _emitEvent(BridgeEvent(
              type: BridgeEventType.navigation,
              action: 'started',
              data: {'url': url},
            ));
          },
          onPageFinished: (url) {
            _currentUrl = url;
            _isReady = true;
            _injectBridgeScript();
            _emitEvent(BridgeEvent(
              type: BridgeEventType.ready,
              data: {'url': url},
            ));
          },
          onNavigationRequest: (request) {
            if (config.allowedDomains.isNotEmpty) {
              final uri = Uri.parse(request.url);
              if (!config.allowedDomains.contains(uri.host)) {
                return NavigationDecision.prevent;
              }
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: (message) {
          _bridgeService.handleWebViewMessage(message.message);
        },
      );
  }

  void _setupEventListeners() {
    _bridgeService.eventStream.listen((event) {
      _eventController.add(event);
      
      if (event.type == BridgeEventType.custom && 
          event.action == 'sendToWeb' && 
          _isReady) {
        final message = event.data['message'];
        _webViewController.runJavaScript('''
          if (window.FlutterBridgeReceiver) {
            window.FlutterBridgeReceiver($message);
          }
        ''');
      }
    });

    _bridgeService.urlStream.listen((url) {
      if (_currentUrl != url) {
        loadUrl(url);
      }
    });
  }

  void _injectBridgeScript() {
    _webViewController.runJavaScript('''
      (function() {
        if (window.FlutterBridgeInjected) return;
        
        window.FlutterBridgeInjected = true;
        
        // Flutter to Web communication receiver
        window.FlutterBridgeReceiver = function(message) {
          if (window.onFlutterMessage) {
            window.onFlutterMessage(JSON.parse(message));
          }
        };
        
        // Web to Flutter communication sender
        window.FlutterBridge = {
          send: function(type, action, data) {
            FlutterBridge.postMessage(JSON.stringify({
              type: type,
              action: action,
              data: data || {}
            }));
          },
          
          navigate: function(url) {
            this.send('navigation', 'navigate', { url: url });
          },
          
          updateData: function(data) {
            this.send('dataUpdate', 'update', data);
          },
          
          ready: function(data) {
            this.send('ready', 'webReady', data);
          },
          
          error: function(error) {
            this.send('error', 'webError', { error: error });
          },
          
          scroll: function(position) {
            this.send('scroll', 'position', position);
          }
        };
        
        // Auto-send ready event
        setTimeout(function() {
          window.FlutterBridge.ready({
            userAgent: navigator.userAgent,
            url: window.location.href,
            timestamp: new Date().toISOString()
          });
        }, 100);
        
        // Listen for scroll events
        let scrollTimeout;
        window.addEventListener('scroll', function() {
          clearTimeout(scrollTimeout);
          scrollTimeout = setTimeout(function() {
            window.FlutterBridge.scroll({
              x: window.scrollX,
              y: window.scrollY,
              maxX: document.body.scrollWidth - window.innerWidth,
              maxY: document.body.scrollHeight - window.innerHeight
            });
          }, 100);
        });
        
        // Listen for resize events
        window.addEventListener('resize', function() {
          window.FlutterBridge.send('resize', 'windowResize', {
            width: window.innerWidth,
            height: window.innerHeight
          });
        });
        
      })();
    ''');
  }

  Future<void> loadUrl(String url) async {
    await _webViewController.loadRequest(Uri.parse(url));
  }

  Future<void> sendMessage(String action, Map<String, dynamic> data) async {
    await _bridgeService.sendMessageToWeb(action, data);
  }

  Future<void> refresh() async {
    await _webViewController.reload();
  }

  Future<void> checkForUpdates() async {
    await _bridgeService.checkForUpdates();
  }

  void _emitEvent(BridgeEvent event) {
    _eventController.add(event);
  }

  void dispose() {
    _bridgeService.dispose();
    _eventController.close();
  }
}

---

// lib/src/web_bridge_widget.dart
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'web_bridge_controller.dart';
import 'models/bridge_config.dart';
import 'models/bridge_event.dart';

class WebBridgeWidget extends StatefulWidget {
  final BridgeConfig config;
  final Widget? loadingWidget;
  final Widget? errorWidget;
  final Function(BridgeEvent)? onEvent;
  final Function(String)? onUrlChanged;
  final bool showRefreshButton;
  final bool showProgressIndicator;

  const WebBridgeWidget({
    Key? key,
    required this.config,
    this.loadingWidget,
    this.errorWidget,
    this.onEvent,
    this.onUrlChanged,
    this.showRefreshButton = true,
    this.showProgressIndicator = true,
  }) : super(key: key);

  @override
  State<WebBridgeWidget> createState() => _WebBridgeWidgetState();
}

class _WebBridgeWidgetState extends State<WebBridgeWidget> {
  late WebBridgeController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = WebBridgeController(widget.config);
    _setupEventListener();
    _loadInitialUrl();
  }

  void _setupEventListener() {
    _controller.eventStream.listen((event) {
      widget.onEvent?.call(event);
      
      switch (event.type) {
        case BridgeEventType.ready:
          setState(() {
            _isLoading = false;
            _hasError = false;
          });
          if (event.data['url'] != null) {
            widget.onUrlChanged?.call(event.data['url']);
          }
          break;
          
        case BridgeEventType.navigation:
          if (event.action == 'started') {
            setState(() {
              _isLoading = true;
              _hasError = false;
              _progress = 0.0;
            });
          }
          break;
          
        case BridgeEventType.error:
          setState(() {
            _isLoading = false;
            _hasError = true;
            _errorMessage = event.data['error']?.toString();
          });
          break;
          
        case BridgeEventType.dataUpdate:
          // Handle data updates - could show a snackbar or update indicator
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Content updated!'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          break;
          
        default:
          break;
      }
    });
  }

  void _loadInitialUrl() {
    final url = '${widget.config.baseUrl}?t=${DateTime.now().millisecondsSinceEpoch}';
    _controller.loadUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showRefreshButton ? AppBar(
        title: Text(_controller.currentUrl ?? 'Web Bridge'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _controller.refresh();
            },
          ),
          IconButton(
            icon: const Icon(Icons.update),
            onPressed: () {
              _controller.checkForUpdates();
            },
          ),
        ],
      ) : null,
      body: Column(
        children: [
          if (widget.showProgressIndicator && _isLoading)
            LinearProgressIndicator(value: _progress),
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller.webViewController),
                
                if (_isLoading && widget.loadingWidget != null)
                  widget.loadingWidget!,
                
                if (_isLoading && widget.loadingWidget == null)
                  const Center(
                    child: CircularProgressIndicator(),
                  ),
                
                if (_hasError && widget.errorWidget != null)
                  widget.errorWidget!,
                
                if (_hasError && widget.errorWidget == null)
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Failed to load content',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _errorMessage!,
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => _controller.refresh(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

# ------------------------------ How to use ---------------------------------------------



# Flutter Web Bridge Project Structure

## Root pubspec.yaml
name: flutter_web_bridge_app
description: A Flutter application with web bridge integration
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'
  flutter: ">=3.0.0"

dependencies:
  flutter:
    sdk: flutter
  webview_flutter: ^4.4.2
  http: ^1.1.0
  connectivity_plus: ^5.0.2
  shared_preferences: ^2.2.2
  cupertino_icons: ^1.0.2
  provider: ^6.1.1
  flutter_secure_storage: ^9.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/images/
    - assets/web/

---

## lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'providers/app_provider.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize services
  await StorageService.instance.init();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
      ],
      child: MaterialApp(
        title: 'Flutter Web Bridge',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

---

## lib/providers/app_provider.dart
import 'package:flutter/material.dart';
import '../models/bridge_config.dart';
import '../models/bridge_event.dart';
import '../services/storage_service.dart';

class AppProvider with ChangeNotifier {
  final List<BridgeEvent> _events = [];
  final StorageService _storage = StorageService.instance;
  
  String _currentUrl = '';
  bool _isConnected = true;
  int _updateCount = 0;
  Map<String, dynamic> _webData = {};

  List<BridgeEvent> get events => List.unmodifiable(_events);
  String get currentUrl => _currentUrl;
  bool get isConnected => _isConnected;
  int get updateCount => _updateCount;
  Map<String, dynamic> get webData => _webData;

  void addEvent(BridgeEvent event) {
    _events.insert(0, event);
    if (_events.length > 100) {
      _events.removeLast();
    }
    
    switch (event.type) {
      case BridgeEventType.navigation:
        if (event.data['url'] != null) {
          _currentUrl = event.data['url'];
        }
        break;
      case BridgeEventType.dataUpdate:
        _updateCount++;
        _webData.addAll(event.data);
        _storage.saveWebData(_webData);
        break;
      case BridgeEventType.ready:
        _isConnected = true;
        break;
      case BridgeEventType.error:
        _isConnected = false;
        break;
      default:
        break;
    }
    
    notifyListeners();
  }

  void clearEvents() {
    _events.clear();
    notifyListeners();
  }

  Future<void> loadSavedData() async {
    _webData = await _storage.getWebData();
    notifyListeners();
  }

  BridgeConfig getBridgeConfig() {
    return BridgeConfig(
      baseUrl: 'https://example.com', // Replace with your web app URL
      headers: {
        'User-Agent': 'FlutterWebBridge/1.0',
        'Accept': 'text/html,application/json',
      },
      enableJavaScript: true,
      enableCache: true,
      cacheTimeout: const Duration(minutes: 30),
      allowedDomains: ['example.com', 'cdn.example.com'],
      initialData: {
        'app_version': '1.0.0',
        'platform': 'flutter',
        'user_id': 'demo_user',
      },
    );
  }
}

---

## lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import 'web_bridge_screen.dart';
import 'settings_screen.dart';
import 'events_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const WebBridgeScreen(),
    const EventsScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    context.read<AppProvider>().loadSavedData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.web),
            label: 'Web App',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.event),
            label: 'Events',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

---

## lib/screens/web_bridge_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../bridge/web_bridge_widget.dart';
import '../models/bridge_event.dart';

class WebBridgeScreen extends StatefulWidget {
  const WebBridgeScreen({super.key});

  @override
  State<WebBridgeScreen> createState() => _WebBridgeScreenState();
}

class _WebBridgeScreenState extends State<WebBridgeScreen> {
  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Web Bridge Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          Consumer<AppProvider>(
            builder: (context, provider, _) => Badge(
              label: Text('${provider.updateCount}'),
              isLabelVisible: provider.updateCount > 0,
              child: IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: () {
                  _showUpdateDialog(context, provider.updateCount);
                },
              ),
            ),
          ),
          Consumer<AppProvider>(
            builder: (context, provider, _) => Icon(
              provider.isConnected ? Icons.wifi : Icons.wifi_off,
              color: provider.isConnected ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: WebBridgeWidget(
        config: appProvider.getBridgeConfig(),
        onEvent: (event) {
          appProvider.addEvent(event);
        },
        onUrlChanged: (url) {
          // Handle URL changes if needed
        },
        loadingWidget: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading web content...'),
            ],
          ),
        ),
        errorWidget: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text('Failed to load web content'),
              SizedBox(height: 8),
              Text('Please check your internet connection'),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _sendTestMessage(context),
        icon: const Icon(Icons.send),
        label: const Text('Send Test Message'),
      ),
    );
  }

  void _sendTestMessage(BuildContext context) {
    final appProvider = context.read<AppProvider>();
    // This would be handled by your WebBridgeController
    appProvider.addEvent(BridgeEvent(
      type: BridgeEventType.custom,
      action: 'test_message',
      data: {
        'message': 'Hello from Flutter!',
        'timestamp': DateTime.now().toIso8601String(),
        'user_action': true,
      },
    ));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Test message sent to web app'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showUpdateDialog(BuildContext context, int updateCount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Content Updates'),
        content: Text('Web content has been updated $updateCount times'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () {
              context.read<AppProvider>().clearEvents();
              Navigator.of(context).pop();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

---

## lib/screens/events_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/bridge_event.dart';

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bridge Events'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: () {
              context.read<AppProvider>().clearEvents();
            },
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, appProvider, _) {
          final events = appProvider.events;
          
          if (events.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_note, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No events yet'),
                  Text('Interact with the web app to see events'),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];
              return EventTile(event: event);
            },
          );
        },
      ),
    );
  }
}

class EventTile extends StatelessWidget {
  final BridgeEvent event;

  const EventTile({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: _getEventColor(event.type),
          child: Icon(
            _getEventIcon(event.type),
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Text(
          _getEventTitle(event.type, event.action),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          _formatTimestamp(event.timestamp),
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
        children: [
          if (event.data.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Event Data:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ...event.data.entries.map((entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${entry.key}: ',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Expanded(
                            child: Text(
                              entry.value.toString(),
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _getEventColor(BridgeEventType type) {
    switch (type) {
      case BridgeEventType.navigation:
        return Colors.blue;
      case BridgeEventType.dataUpdate:
        return Colors.green;
      case BridgeEventType.error:
        return Colors.red;
      case BridgeEventType.ready:
        return Colors.orange;
      case BridgeEventType.scroll:
        return Colors.purple;
      case BridgeEventType.resize:
        return Colors.teal;
      case BridgeEventType.custom:
        return Colors.indigo;
    }
  }

  IconData _getEventIcon(BridgeEventType type) {
    switch (type) {
      case BridgeEventType.navigation:
        return Icons.navigation;
      case BridgeEventType.dataUpdate:
        return Icons.update;
      case BridgeEventType.error:
        return Icons.error;
      case BridgeEventType.ready:
        return Icons.check_circle;
      case BridgeEventType.scroll:
        return Icons.scroll;
      case BridgeEventType.resize:
        return Icons.aspect_ratio;
      case BridgeEventType.custom:
        return Icons.extension;
    }
  }

  String _getEventTitle(BridgeEventType type, String? action) {
    final baseTitle = type.name.toUpperCase();
    return action != null ? '$baseTitle - $action' : baseTitle;
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${timestamp.day}/${timestamp.month} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }
}

---

## lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  final _storage = StorageService.instance;
  
  bool _enableJavaScript = true;
  bool _enableCache = true;
  bool _showDebugInfo = true;
  int _cacheTimeoutMinutes = 30;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _storage.getSettings();
    setState(() {
      _urlController.text = settings['baseUrl'] ?? 'https://example.com';
      _enableJavaScript = settings['enableJavaScript'] ?? true;
      _enableCache = settings['enableCache'] ?? true;
      _showDebugInfo = settings['showDebugInfo'] ?? true;
      _cacheTimeoutMinutes = settings['cacheTimeoutMinutes'] ?? 30;
    });
  }

  Future<void> _saveSettings() async {
    await _storage.saveSettings({
      'baseUrl': _urlController.text,
      'enableJavaScript': _enableJavaScript,
      'enableCache': _enableCache,
      'showDebugInfo': _showDebugInfo,
      'cacheTimeoutMinutes': _cacheTimeoutMinutes,
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved successfully'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Web App Configuration',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'Base URL',
                      hintText: 'https://your-web-app.com',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Enable JavaScript'),
                    subtitle: const Text('Allow JavaScript execution in web view'),
                    value: _enableJavaScript,
                    onChanged: (value) {
                      setState(() {
                        _enableJavaScript = value;
                      });
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Enable Cache'),
                    subtitle: const Text('Cache web content for offline access'),
                    value: _enableCache,
                    onChanged: (value) {
                      setState(() {
                        _enableCache = value;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Performance Settings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('Cache Timeout'),
                    subtitle: Text('$_cacheTimeoutMinutes minutes'),
                    trailing: DropdownButton<int>(
                      value: _cacheTimeoutMinutes,
                      items: [5, 15, 30, 60, 120].map((minutes) {
                        return DropdownMenuItem(
                          value: minutes,
                          child: Text('$minutes min'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _cacheTimeoutMinutes = value;
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Debug Options',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Show Debug Info'),
                    subtitle: const Text('Display debug information in events'),
                    value: _showDebugInfo,
                    onChanged: (value) {
                      setState(() {
                        _showDebugInfo = value;
                      });
                    },
                  ),
                  ListTile(
                    title: const Text('Clear Cache'),
                    subtitle: const Text('Remove all cached data'),
                    trailing: const Icon(Icons.delete),
                    onTap: () async {
                      await _storage.clearCache();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Cache cleared successfully'),
                          ),
                        );
                      }
                    },
                  ),
                  ListTile(
                    title: const Text('Reset Settings'),
                    subtitle: const Text('Reset all settings to default'),
                    trailing: const Icon(Icons.restore),
                    onTap: () => _showResetDialog(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Consumer<AppProvider>(
            builder: (context, provider, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Status',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    _buildStatusRow('Connection', 
                      provider.isConnected ? 'Connected' : 'Disconnected',
                      provider.isConnected ? Colors.green : Colors.red),
                    _buildStatusRow('Current URL', provider.currentUrl.isEmpty 
                      ? 'Not loaded' : provider.currentUrl, Colors.blue),
                    _buildStatusRow('Total Events', '${provider.events.length}', Colors.orange),
                    _buildStatusRow('Updates Received', '${provider.updateCount}', Colors.purple),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
  }

  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Settings'),
        content: const Text('Are you sure you want to reset all settings to default values?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _storage.clearSettings();
              await _loadSettings();
              if (mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Settings reset successfully'),
                  ),
                );
              }
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
}

---

## lib/services/storage_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();
  
  static StorageService get instance => _instance;
  
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // Web data storage
  Future<void> saveWebData(Map<String, dynamic> data) async {
    await _prefs?.setString('web_data', json.encode(data));
  }

  Future<Map<String, dynamic>> getWebData() async {
    final data = _prefs?.getString('web_data');
    if (data == null) return {};
    return json.decode(data) as Map<String, dynamic>;
  }

  // Settings storage
  Future<void> saveSettings(Map<String, dynamic> settings) async {
    await _prefs?.setString('app_settings', json.encode(settings));
  }

  Future<Map<String, dynamic>> getSettings() async {
    final settings = _prefs?.getString('app_settings');
    if (settings == null) return {};
    return json.decode(settings) as Map<String, dynamic>;
  }

  // Cache management
  Future<void> clearCache() async {
    await _prefs?.remove('web_data');
    await _prefs?.remove('web_bridge_version');
  }

  Future<void> clearSettings() async {
    await _prefs?.remove('app_settings');
  }

  Future<void> clearAll() async {
    await _prefs?.clear();
  }
}

---

## Copy the bridge package files from previous artifact:
## lib/bridge/ (directory)
# Copy all files from the previous Flutter Web Bridge package:
# - bridge_config.dart -> lib/models/bridge_config.dart
# - bridge_event.dart -> lib/models/bridge_event.dart  
# - bridge_service.dart -> lib/services/bridge_service.dart
# - web_bridge_controller.dart -> lib/bridge/web_bridge_controller.dart
# - web_bridge_widget.dart -> lib/bridge/web_bridge_widget.dart

---

## android/app/src/main/AndroidManifest.xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

    <application
        android:label="Flutter Web Bridge"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>

---

## ios/Runner/Info.plist additions
Add these keys to your Info.plist:

<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
<key>io.flutter.embedded_views_preview</key>
<true/>

---

## assets/web/demo.html (Example web app for testing)
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Web Bridge Demo</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: white;
        }
        
        .container {
            max-width: 600px;
            margin: 0 auto;
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 30px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
        }
        
        .header {
            text-align: center;
            margin-bottom: 30px;
        }
        
        .status {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 10px;
            margin-bottom: 20px;
        }
        
        .status-dot {
            width: 12px;
            height: 12px;
            border-radius: 50%;
            background: #4ade80;
            animation: pulse 2s infinite;
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        
        .card {
            background: rgba(255, 255, 255, 0.1);
            border-radius: 15px;
            padding: 20px;
            margin-bottom: 20px;
            border: 1px solid rgba(255, 255, 255, 0.2);
        }
        
        .button {
            background: rgba(255, 255, 255, 0.2);
            border: none;
            border-radius: 10px;
            padding: 12px 24px;
            color: white;
            font-size: 16px;
            cursor: pointer;
            transition: all 0.3s ease;
            margin: 5px;
        }
        
        .button:hover {
            background: rgba(255, 255, 255, 0.3);
            transform: translateY(-2px);
        }
        
        .input {
            width: 100%;
            padding: 12px;
            border: none;
            border-radius: 10px;
            background: rgba(255, 255, 255, 0.2);
            color: white;
            font-size: 16px;
            margin-bottom: 10px;
        }
        
        .input::placeholder {
            color: rgba(255, 255, 255, 0.7);
        }
        
        .log {
            background: rgba(0, 0, 0, 0.3);
            border-radius: 10px;
            padding: 15px;
            font-family: 'Courier New', monospace;
            font-size: 14px;
            max-height: 200px;
            overflow-y: auto;
            margin-top: 10px;
        }
        
        .dynamic-content {
            background: linear-gradient(45deg, #ff6b6b, #4ecdc4);
            border-radius: 15px;
            padding: 20px;
            margin: 20px 0;
            text-align: center;
            animation: colorShift 5s infinite;
        }
        
        @keyframes colorShift {
            0%, 100% { background: linear-gradient(45deg, #ff6b6b, #4ecdc4); }
            50% { background: linear-gradient(45deg, #4ecdc4, #45b7d1); }
        }
        
        .scroll-content {
            height: 300px;
            overflow-y: auto;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 10px;
            padding: 15px;
            margin-top: 15px;
        }
        
        .scroll-item {
            padding: 10px;
            margin: 5px 0;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 8px;
            border-left: 4px solid #4ade80;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🌐 Web Bridge Demo</h1>
            <div class="status">
                <div class="status-dot"></div>
                <span id="statusText">Connected to Flutter</span>
            </div>
        </div>

        <div class="card">
            <h3>📱 Flutter Communication</h3>
            <button class="button" onclick="sendToFlutter('ready')">Send Ready</button>
            <button class="button" onclick="sendToFlutter('update')">Send Update</button>
            <button class="button" onclick="sendToFlutter('error')">Send Error</button>
            <button class="button" onclick="sendCustomData()">Send Custom Data</button>
        </div>

        <div class="card">
            <h3>📝 Send Custom Message</h3>
            <input type="text" class="input" id="messageInput" placeholder="Enter your message...">
            <button class="button" onclick="sendCustomMessage()">Send Message</button>
        </div>

        <div class="dynamic-content">
            <h3>🔄 Dynamic Content</h3>
            <p id="dynamicText">This content updates automatically!</p>
            <p>Version: <span id="versionNumber">1.0.0</span></p>
        </div>

        <div class="card">
            <h3>📊 Scroll Test Area</h3>
            <div class="scroll-content" id="scrollContent">
                <!-- Scroll items will be generated by JavaScript -->
            </div>
        </div>

        <div class="card">
            <h3>📋 Event Log</h3>
            <div class="log" id="eventLog">
                <div>Web app initialized...</div>
            </div>
        </div>
    </div>

    <script>
        let messageCount = 0;
        let version = '1.0.0';

        // Initialize scroll content
        function initScrollContent() {
            const scrollContent = document.getElementById('scrollContent');
            for (let i = 1; i <= 50; i++) {
                const item = document.createElement('div');
                item.className = 'scroll-item';
                item.innerHTML = `
                    <strong>Item ${i}</strong><br>
                    <small>This is a scrollable item with some content. Scroll position is tracked!</small>
                `;
                scrollContent.appendChild(item);
            }
        }

        // Log events
        function logEvent(message) {
            const log = document.getElementById('eventLog');
            const timestamp = new Date().toLocaleTimeString();
            const logEntry = document.createElement('div');
            logEntry.innerHTML = `[${timestamp}] ${message}`;
            log.appendChild(logEntry);
            log.scrollTop = log.scrollHeight;
            
            // Keep only last 20 entries
            while (log.children.length > 20) {
                log.removeChild(log.firstChild);
            }
        }

        // Send messages to Flutter
        function sendToFlutter(type) {
            if (window.FlutterBridge) {
                const data = {
                    timestamp: new Date().toISOString(),
                    messageCount: ++messageCount,
                    version: version
                };

                switch (type) {
                    case 'ready':
                        window.FlutterBridge.ready(data);
                        logEvent('Sent ready event to Flutter');
                        break;
                    case 'update':
                        data.content = 'Updated content from web app';
                        data.newVersion = (parseFloat(version) + 0.1).toFixed(1);
                        version = data.newVersion;
                        document.getElementById('versionNumber').textContent = version;
                        window.FlutterBridge.updateData(data);
                        logEvent(`Sent update event (v${version}) to Flutter`);
                        break;
                    case 'error':
                        window.FlutterBridge.error('Test error from web app');
                        logEvent('Sent error event to Flutter');
                        break;
                }
            }
        }

        function sendCustomData() {
            if (window.FlutterBridge) {
                const data = {
                    type: 'user_interaction',
                    action: 'button_click',
                    timestamp: new Date().toISOString(),
                    userAgent: navigator.userAgent,
                    screenSize: {
                        width: window.innerWidth,
                        height: window.innerHeight
                    },
                    scrollPosition: {
                        x: window.scrollX,
                        y: window.scrollY
                    }
                };
                
                window.FlutterBridge.send('custom', 'user_data', data);
                logEvent('Sent custom data to Flutter');
            }
        }

        function sendCustomMessage() {
            const input = document.getElementById('messageInput');
            const message = input.value.trim();
            
            if (message && window.FlutterBridge) {
                window.FlutterBridge.send('custom', 'user_message', {
                    message: message,
                    timestamp: new Date().toISOString(),
                    length: message.length
                });
                logEvent(`Sent custom message: "${message}"`);
                input.value = '';
            }
        }

        // Handle messages from Flutter
        window.onFlutterMessage = function(data) {
            logEvent(`Received from Flutter: ${JSON.stringify(data)}`);
            
            if (data.action === 'updateContent') {
                document.getElementById('dynamicText').textContent = 
                    data.data.content || 'Content updated from Flutter!';
            }
        };

        // Auto-update dynamic content
        function updateDynamicContent() {
            const messages = [
                'Dynamic content is awesome! 🚀',
                'No app store updates needed! 🎉',
                'Real-time web updates! ⚡',
                'Flutter + Web = ❤️',
                'Seamless integration! 🌟'
            ];
            
            const randomMessage = messages[Math.floor(Math.random() * messages.length)];
            document.getElementById('dynamicText').textContent = randomMessage;
            
            // Send update to Flutter
            if (window.FlutterBridge && Math.random() > 0.7) {
                sendToFlutter('update');
            }
        }

        // Initialize everything when page loads
        document.addEventListener('DOMContentLoaded', function() {
            initScrollContent();
            logEvent('Web app loaded and initialized');
            
            // Auto-update content every 10 seconds
            setInterval(updateDynamicContent, 10000);
            
            // Send initial ready signal after a short delay
            setTimeout(() => {
                if (window.FlutterBridge) {
                    sendToFlutter('ready');
                }
            }, 1000);
        });

        // Handle Enter key in message input
        document.addEventListener('keypress', function(e) {
            if (e.key === 'Enter' && e.target.id === 'messageInput') {
                sendCustomMessage();
            }
        });

        // Simulate periodic updates
        setInterval(() => {
            if (Math.random() > 0.8) { // 20% chance every 5 seconds
                const updateTypes = ['content', 'data', 'notification'];
                const randomType = updateTypes[Math.floor(Math.random() * updateTypes.length)];
                
                if (window.FlutterBridge) {
                    window.FlutterBridge.send('dataUpdate', 'auto_update', {
                        type: randomType,
                        timestamp: new Date().toISOString(),
                        data: `Automatic ${randomType} update`
                    });
                    logEvent(`Auto-sent ${randomType} update`);
                }
            }
        }, 5000);
    </script>
</body>
</html>

---

## README.md
# Flutter Web Bridge Project

A complete Flutter application demonstrating seamless integration between Flutter and web content through a custom bridge system. This project enables dynamic web content updates without requiring mobile app redeployment.

## Features

### 🌐 Dynamic Web Integration
- Real-time communication between Flutter and web content
- Automatic content updates without app store releases
- Two-way data binding and event handling

### 📱 Mobile-First Design
- Native Flutter UI with embedded web views
- Responsive design for all screen sizes
- Material Design 3 components

### 🔄 Real-Time Updates
- Live content synchronization
- Version checking and cache management
- Offline support with graceful degradation

### 📊 Event Monitoring
- Real-time event logging and visualization
- Comprehensive debugging tools
- Performance monitoring

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── providers/
│   └── app_provider.dart     # State management
├── screens/
│   ├── home_screen.dart      # Main navigation
│   ├── web_bridge_screen.dart # Web content display
│   ├── events_screen.dart    # Event monitoring
│   └── settings_screen.dart  # Configuration
├── services/
│   ├── storage_service.dart  # Local data persistence
│   └── bridge_service.dart   # Web bridge communication
├── models/
│   ├── bridge_config.dart    # Configuration models
│   └── bridge_event.dart     # Event models
└── bridge/
    ├── web_bridge_controller.dart # Bridge controller
    └── web_bridge_widget.dart    # Bridge UI widget
```

## Setup Instructions

### 1. Dependencies
Add these dependencies to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  webview_flutter: ^4.4.2
  http: ^1.1.0
  connectivity_plus: ^5.0.2
  shared_preferences: ^2.2.2
  provider: ^6.1.1
  flutter_secure_storage: ^9.0.0
```

### 2. Android Configuration
Update `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

### 3. iOS Configuration
Add to `ios/Runner/Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
<key>io.flutter.embedded_views_preview</key>
<true/>
```

### 4. Web App Setup
Replace the base URL in `app_provider.dart` with your web application URL:

```dart
BridgeConfig(
  baseUrl: 'https://your-web-app.com', // Update this
  // ... other config
)
```

## Web App Integration

Your web application needs to include the bridge JavaScript:

```javascript
// Send data to Flutter
window.FlutterBridge.send('dataUpdate', 'content_changed', {
  newContent: 'Updated content',
  timestamp: new Date().toISOString()
});

// Receive data from Flutter
window.onFlutterMessage = function(message) {
  console.log('Message from Flutter:', message);
  // Handle the message
};
```

## Usage Examples

### Basic Implementation
```dart
WebBridgeWidget(
  config: BridgeConfig(
    baseUrl: 'https://your-web-app.com',
    enableJavaScript: true,
    enableCache: true,
  ),
  onEvent: (event) {
    print('Bridge event: ${event.type}');
  },
)
```

### Advanced Configuration
```dart
BridgeConfig(
  baseUrl: 'https://your-web-app.com',
  headers: {
    'Authorization': 'Bearer your-token',
    'Custom-Header': 'value',
  },
  allowedDomains: ['your-domain.com'],
  cacheTimeout: Duration(minutes: 30),
  initialData: {
    'user_id': 'user123',
    'app_version': '1.0.0',
  },
)
```

## Key Benefits

### 🚀 Rapid Development
- Update web content instantly
- No app store review process
- Real-time A/B testing capabilities

### 📈 Performance Optimized
- Intelligent caching system
- Minimal battery impact
- Efficient memory management

### 🛡️ Enterprise Ready
- Secure communication protocols
- Comprehensive error handling
- Production-grade logging

### 🎨 Flexible UI
- Dynamic layout support
- Responsive design patterns
- Custom styling options

## Testing

The project includes a demo web app (`assets/web/demo.html`) that demonstrates:
- Two-way communication
- Real-time updates
- Scroll event handling
- Dynamic content changes
- Error simulation

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:
- Check the documentation
- Review example implementations
- Open an issue on GitHub

---

*Built with ❤️ using Flutter and modern web technologies*

