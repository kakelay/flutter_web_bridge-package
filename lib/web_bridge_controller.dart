import 'dart:async';
import 'package:flutter_web_bridge/flutter_web_bridge.dart';
import 'package:webview_flutter/webview_flutter.dart';
 

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