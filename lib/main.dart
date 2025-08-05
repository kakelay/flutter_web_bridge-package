import 'package:flutter/material.dart';
import 'package:flutter_web_bridge/flutter_web_bridge.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Web Bridge Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: WebBridgeScreen(),
      debugShowCheckedModeBanner: true,
    );
  }
}

class WebBridgeScreen extends StatefulWidget {
  const WebBridgeScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _WebBridgeScreenState createState() => _WebBridgeScreenState();
}

class _WebBridgeScreenState extends State<WebBridgeScreen> {
  int _currentIndex = 0;

  final config = BridgeConfig(
    headers: {'Authorization': 'Bearer token'},
    baseUrl: 'http://10.0.2.2:5500/assets/demo.html',
    allowedDomains: ['10.0.2.2'],
    enableCache: true,
  );

  Widget _buildBody() {
    if (_currentIndex == 0) {
      return WebBridgeWidget(
        config: config,
        showRefreshButton: false,
        onEvent: (event) {
          print('Bridge event: ${event.type} - ${event.data}');
          if (event.type == BridgeEventType.dataUpdate) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Content updated!'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        },
        onUrlChanged: (url) {
          print('URL changed: $url');
        },
      );
    } else {
      return StaticPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? 'Web Bridge' : 'Static Info'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [Icon(Icons.notifications)],
      ),
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.web), label: 'Web'),
          BottomNavigationBarItem(icon: Icon(Icons.info), label: 'Static'),
        ],
      ),
    );
  }
}

class StaticPage extends StatelessWidget {
  const StaticPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 100, color: Colors.deepPurple),
            SizedBox(height: 20),
            Text(
              'Static Info Page',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            SizedBox(height: 10),
            Text(
              'This is a static page where you can show\nFAQs, App Info, Versioning, or anything else.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
