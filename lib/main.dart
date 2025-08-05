import 'package:flutter/material.dart';
import 'package:flutter_web_bridge/flutter_web_bridge.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Web Bridge Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: WebBridgeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class WebBridgeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final config = BridgeConfig(
      // baseUrl: 'http://10.0.2.2:5500/assets/demo.html',
      headers: {'Authorization': 'Bearer token'},
      // allowedDomains: ['10.0.2.2'],
      baseUrl: 'http://127.0.0.1:5500/assets/demo.html',
      allowedDomains: ['127.0.0.1'],
      enableCache: true,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Web Bridge'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: WebBridgeWidget(
        config: config,
        showRefreshButton: false, // Consistent appearance
        onEvent: (event) {
          print('Bridge event: ${event.type} - ${event.data}');

          // Show snackbar for important events
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
      ),
    );
  }
}

// Alternative usage without custom Scaffold
class SimpleWebBridgeApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final config = BridgeConfig(
      baseUrl: 'http://10.0.2.2:5500/assets/demo.html',
      headers: {'Authorization': 'Bearer token'},
      // allowedDomains: ['10.0.2.2'],
      enableCache: true,
    );

    return MaterialApp(
      title: 'Flutter Web Bridge',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: Text('Simple Web Bridge'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: WebBridgeWidget(
          config: config,
          showRefreshButton: false,
          onEvent: (event) {
            print('Bridge event: ${event.type} - ${event.data}');
          },
          onUrlChanged: (url) {
            print('URL changed: $url');
          },
        ),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
