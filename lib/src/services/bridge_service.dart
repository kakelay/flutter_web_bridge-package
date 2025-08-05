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