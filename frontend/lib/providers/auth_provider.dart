import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';

class AuthProvider extends ChangeNotifier {
  User? _currentUser;
  bool _isLoading = false;
  bool _isInitializing = true;
  String? _errorMessage;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isInitializing => _isInitializing;
  bool get isGuest => _currentUser?.isGuest ?? false;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  AuthProvider() {
    _loadSession();
  }

  Future<void> _loadSession() async {
    final user = await SessionService.getUser();
    if (user == null ||
        user.isGuest ||
        (!user.isGuest && (user.token == null || user.token!.isEmpty))) {
      await SessionService.clearUser();
      _currentUser = null;
    } else {
      _currentUser = user;
    }
    _isInitializing = false;
    notifyListeners();
  }

  Future<void> startGuestSession() async {
    _currentUser = User(
      id: 0,
      name: 'Tamu',
      email: '',
      role: 'customer',
      isGuest: true,
    );
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await ApiService.login(email, password);
      _currentUser = user;
      await SessionService.saveUser(user);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(String name, String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await ApiService.register(name, email, password);
      _currentUser = user;
      await SessionService.saveUser(user);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    final token = _currentUser?.token;
    var logoutError = false;
    if (token != null && token.isNotEmpty) {
      try {
        await ApiService.logout(token);
      } catch (e) {
        logoutError = true;
      }
    }
    _currentUser = null;
    await SessionService.clearUser();
    _errorMessage = logoutError
        ? 'Sesi lokal sudah dihapus, tetapi server belum mengonfirmasi logout.'
        : null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
