import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../services/auth_provider.dart';
import '../../config/api.dart';

/// Màn hình "Đăng Nhập"
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // ===========================================================================
  // PHẦN 1: CÁC BIẾN QUẢN LÝ DỮ LIỆU (STATE)
  // ===========================================================================

  final TextEditingController _usernameController = TextEditingController(); // Ô nhập tên tài khoản
  final TextEditingController _passwordController = TextEditingController(); // Ô nhập mật khẩu

  String _errorMessage = ""; // Thông báo lỗi nếu đăng nhập thất bại
  bool _isSubmitting = false; // Trạng thái đang gửi yêu cầu đăng nhập

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // PHẦN 2: CÁC HÀM XỬ LÝ (GỌI API VỀ MÁY CHỦ)
  // ===========================================================================

  /// Gửi thông tin đăng nhập lên máy chủ
  Future<void> _handleLogin() async {
    if (_isSubmitting) return;

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = "Vui lòng nhập đầy đủ tài khoản và mật khẩu!");
      return;
    }

    setState(() {
      _errorMessage = "";
      _isSubmitting = true;
    });

    try {
      final res = await http.post(
        Uri.parse('$API_BASE_URL/api/auth/login'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": username,
          "password": password,
        }),
      );

      final data = jsonDecode(res.body);

      // Nếu máy chủ báo lỗi (ví dụ: sai tài khoản hoặc sai mật khẩu)
      if (res.statusCode != 200) {
        if (mounted) {
          setState(() {
            _errorMessage = data['message'] ?? "Đăng nhập thất bại. Vui lòng kiểm tra lại!";
            _isSubmitting = false;
          });
        }
        return;
      }

      // Đăng nhập thành công -> Lưu thông tin vào AuthProvider và chuyển về Trang chủ
      if (mounted) {
        final user = data['user'];
        context.read<AuthProvider>().login(
              id: user['id']?.toString(),
              name: user['username']?.toString(),
            );
        context.go('/'); // Chuyển về màn hình trang chủ
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Không thể kết nối tới máy chủ. Vui lòng kiểm tra lại mạng!";
          _isSubmitting = false;
        });
      }
    }
  }

  // ===========================================================================
  // PHẦN 3: GIAO DIỆN CHÍNH (BUILD)
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F4),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(horizontal: 22.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              // Nút quay lại
              _buildBackButton(),

              const SizedBox(height: 20),
              // Lời chào mừng
              _buildGreetingHeader(),

              const SizedBox(height: 28),
              // Khung biểu mẫu nhập tài khoản & mật khẩu
              _buildLoginForm(),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // PHẦN 4: CÁC WIDGET CON (TÁCH NHỎ CODE ĐỂ ĐƠN GIẢN VÀ DỄ HIỂU)
  // ===========================================================================

  /// Nút quay lại góc trên bên trái
  Widget _buildBackButton() {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => context.pop(),
        icon: const Icon(Icons.arrow_back, color: Color(0xFF22C55E), size: 20),
        label: const Text(
          'Quay lại',
          style: TextStyle(color: Color(0xFF22C55E), fontSize: 15, fontWeight: FontWeight.w700),
        ),
        style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
      ),
    );
  }

  /// Tiêu đề lời chào
  Widget _buildGreetingHeader() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'KeoNhanh ⚽',
          style: TextStyle(color: Color(0xFF22C55E), fontSize: 17, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 10),
        Text(
          'Chào mừng',
          style: TextStyle(color: Color(0xFF17201A), fontSize: 30, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 6),
        Text(
          'Đăng nhập để tiếp tục tìm kèo bóng đá và đồng đội.',
          style: TextStyle(color: Color(0xFF5D6B63), fontSize: 15, height: 1.4),
        ),
      ],
    );
  }

  /// Khung nhập liệu đăng nhập
  Widget _buildLoginForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDFE7DF)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Ô nhập Username
          const Text('Tên đăng nhập', style: TextStyle(color: Color(0xFF2F3B33), fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _usernameController,
            style: const TextStyle(fontSize: 16, color: Color(0xFF17201A)),
            decoration: _inputDecoration('vd: nguyen_van_an'),
          ),
          const SizedBox(height: 16),

          // 2. Ô nhập Mật khẩu
          const Text('Mật khẩu', style: TextStyle(color: Color(0xFF2F3B33), fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordController,
            obscureText: true,
            style: const TextStyle(fontSize: 16, color: Color(0xFF17201A)),
            decoration: _inputDecoration('Nhập mật khẩu'),
            onSubmitted: (_) => _handleLogin(),
          ),

          // 3. Thông báo lỗi (nếu có)
          if (_errorMessage.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_errorMessage, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // 4. Nút bấm Đăng nhập
          ElevatedButton(
            onPressed: _isSubmitting ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              disabledBackgroundColor: const Color(0xFF86EFAC),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _isSubmitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Đăng nhập', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  /// Tiện ích định dạng viền cho ô nhập
  InputDecoration _inputDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: Color(0xFF8B98A5), fontSize: 14),
      filled: true,
      fillColor: const Color(0xFFF9FBF8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD7E1D8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF22C55E)),
      ),
    );
  }
}
