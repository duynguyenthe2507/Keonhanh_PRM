import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../config/api.dart';

/// Màn hình "Đăng Ký Tài Khoản"
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // ===========================================================================
  // PHẦN 1: CÁC BIẾN QUẢN LÝ DỮ LIỆU (STATE)
  // ===========================================================================

  final TextEditingController _usernameController = TextEditingController(); // Ô nhập tên tài khoản
  final TextEditingController _passwordController = TextEditingController(); // Ô nhập mật khẩu

  String _errorMessage = ""; // Thông báo lỗi hiển thị cho người dùng
  bool _isSubmitting = false; // Trạng thái đang gửi yêu cầu tạo tài khoản

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // PHẦN 2: CÁC HÀM XỬ LÝ (KIỂM TRA DỮ LIỆU & GỌI API)
  // ===========================================================================

  /// Kiểm tra dữ liệu đầu vào trước khi gửi đi
  bool _validateInput() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty) {
      setState(() => _errorMessage = "Vui lòng nhập tên đăng nhập");
      return false;
    }
    if (username.length < 3) {
      setState(() => _errorMessage = "Tên đăng nhập phải có ít nhất 3 ký tự");
      return false;
    }
    if (password.isEmpty) {
      setState(() => _errorMessage = "Vui lòng nhập mật khẩu");
      return false;
    }
    if (password.length < 6) {
      setState(() => _errorMessage = "Mật khẩu phải có tối thiểu 6 ký tự");
      return false;
    }
    return true;
  }

  /// Gửi thông tin đăng ký lên máy chủ
  Future<void> _handleRegister() async {
    if (_isSubmitting) return;
    if (!_validateInput()) return;

    setState(() {
      _errorMessage = "";
      _isSubmitting = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$API_BASE_URL/api/auth/register'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": _usernameController.text.trim(),
          "password": _passwordController.text,
        }),
      );

      final data = jsonDecode(response.body);

      // Nếu máy chủ báo lỗi (ví dụ: tài khoản đã tồn tại)
      if (response.statusCode != 200 && response.statusCode != 201) {
        if (mounted) {
          setState(() {
            _errorMessage = data['message'] ?? "Đăng ký không thành công. Vui lòng thử lại!";
            _isSubmitting = false;
          });
        }
        return;
      }

      // Đăng ký thành công -> Hiện thông báo thành công và chuyển sang màn hình Đăng nhập
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đăng ký tài khoản thành công! Vui lòng đăng nhập.'),
            backgroundColor: Color(0xFF16A34A),
          ),
        );
        context.go('/login');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Không thể kết nối tới máy chủ. Vui lòng thử lại!";
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
              // Tiêu đề giới thiệu
              _buildHeaderTitle(),

              const SizedBox(height: 28),
              // Khung biểu mẫu nhập tài khoản & mật khẩu
              _buildRegisterForm(),

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

  /// Nút quay lại
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

  /// Tiêu đề giới thiệu
  Widget _buildHeaderTitle() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'KeoNhanh ⚽',
          style: TextStyle(color: Color(0xFF22C55E), fontSize: 17, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 10),
        Text(
          'Đăng ký tài khoản',
          style: TextStyle(color: Color(0xFF17201A), fontSize: 30, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 6),
        Text(
          'Tạo tài khoản để bắt đầu tìm kèo bóng đá và tham gia đội bóng.',
          style: TextStyle(color: Color(0xFF5D6B63), fontSize: 15, height: 1.4),
        ),
      ],
    );
  }

  /// Khung biểu mẫu đăng ký
  Widget _buildRegisterForm() {
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
          // 1. Tên đăng nhập
          const Text('Tên đăng nhập', style: TextStyle(color: Color(0xFF2F3B33), fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _usernameController,
            style: const TextStyle(fontSize: 16, color: Color(0xFF17201A)),
            decoration: _inputDecoration('vd: ronaldocr7'),
          ),
          const SizedBox(height: 16),

          // 2. Mật khẩu
          const Text('Mật khẩu', style: TextStyle(color: Color(0xFF2F3B33), fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordController,
            obscureText: true,
            style: const TextStyle(fontSize: 16, color: Color(0xFF17201A)),
            decoration: _inputDecoration('Tối thiểu 6 ký tự'),
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

          // 4. Nút bấm Tạo tài khoản
          ElevatedButton(
            onPressed: _isSubmitting ? null : _handleRegister,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              disabledBackgroundColor: const Color(0xFF86EFAC),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _isSubmitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Tạo tài khoản', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
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
