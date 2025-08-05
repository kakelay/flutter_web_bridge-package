import 'package:flutter/material.dart';
import 'package:flutter_web_bridge/flutter_web_bridge.dart';
import 'package:webview_flutter/webview_flutter.dart';
 

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