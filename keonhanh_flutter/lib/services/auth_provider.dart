import 'package:flutter/material.dart';

class AuthProvider with ChangeNotifier {
  bool _isLoading = false;
  bool _isLoggedIn = false;
  
  // Lưu thêm thông tin user cơ bản
  String? _userId;
  String? _username;

  bool get isLoading => _isLoading;
  bool get isLoggedIn => _isLoggedIn;
  String? get userId => _userId;
  String? get username => _username;

  void login({String? id, String? name}) {
    _isLoggedIn = true;
    _userId = id;
    _username = name;
    notifyListeners();
  }

  void logout() {
    _isLoggedIn = false;
    _userId = null;
    _username = null;
    notifyListeners();
  }
}
