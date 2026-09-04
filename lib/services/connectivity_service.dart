import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService {
  final Connectivity _connectivity;
  final Duration stabilityWindow;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _stabilityTimer;
  bool _isOnline = true;
  final _changes = StreamController<bool>.broadcast();

  ConnectivityService({
    this.stabilityWindow = const Duration(seconds: 5),
    Connectivity? connectivity,
  }) : _connectivity = connectivity ?? Connectivity();

  bool get isOnline => _isOnline;
  Stream<bool> get changes => _changes.stream;

  ConnectivityResult _lastType = ConnectivityResult.mobile;

  Future<ConnectivityResult> currentConnectionType() async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (results.isNotEmpty) {
        _lastType = results.first;
      }
    } catch (_) {}
    return _lastType;
  }

  Future<bool> checkNow() async {
    try {
      final results = await _connectivity.checkConnectivity();
      final online = !results.contains(ConnectivityResult.none);
      if (online && !_isOnline) {
        _stabilityTimer?.cancel();
        _isOnline = true;
        if (!_changes.isClosed) _changes.add(true);
      } else if (!online && _isOnline) {
        _stabilityTimer?.cancel();
        _isOnline = false;
        if (!_changes.isClosed) _changes.add(false);
      }
    } catch (_) {
      // Preserve last known state; do not fail-open to online.
    }
    return _isOnline;
  }

  void startMonitoring() {
    _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen(
      (results) {
        final online = !results.contains(ConnectivityResult.none);
        if (online == _isOnline) return;
        if (online) {
          _stabilityTimer?.cancel();
          _stabilityTimer = Timer(stabilityWindow, () {
            if (_isOnline) return;
            _isOnline = true;
            _changes.add(true);
          });
        } else {
          _stabilityTimer?.cancel();
          _isOnline = false;
          _changes.add(false);
        }
      },
      onError: (Object _) {},
    );
  }

  @visibleForTesting
  void debugEmitChange(bool online) {
    _isOnline = online;
    if (!_changes.isClosed) _changes.add(online);
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _stabilityTimer?.cancel();
    _changes.close();
  }
}
