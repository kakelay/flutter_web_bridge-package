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
      headers: {'Authorization': 'Bearer token'},
      baseUrl:
          'https://v0-mobile-banking-nine.vercel.app/',
      // allowedDomains: ['https://kakelay-dev.vercel.app/'], // match the baseUrl
      enableCache: true,
    );

    return Scaffold(
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
