import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../services/auth_provider.dart';
import '../../config/api.dart';

// Danh sách các vị trí thi đấu trên sân bóng
const List<String> POSITIONS = ["Thủ môn", "Hậu vệ", "Tiền vệ", "Tiền đạo"];

/// Màn hình "Cài Đặt Hồ Sơ Cá Nhân"
/// Cho phép cập nhật ảnh đại diện, họ tên, số điện thoại, vị trí sở trường, khu vực sinh sống
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  // ===========================================================================
  // PHẦN 1: CÁC BIẾN QUẢN LÝ DỮ LIỆU (STATE)
  // ===========================================================================

  final TextEditingController _avatarController = TextEditingController(); // Đường link ảnh đại diện
  final TextEditingController _fullNameController = TextEditingController(); // Họ và tên
  final TextEditingController _phoneController = TextEditingController(); // Số điện thoại
  final TextEditingController _locationController = TextEditingController(); // Địa chỉ / Khu vực hoạt động

  String _position = POSITIONS[0]; // Vị trí thi đấu sở trường (mặc định: Thủ môn)
  bool _isLookingForTeam = true; // Trạng thái đang tìm đội

  String _errorMessage = ""; // Thông báo lỗi khi nhập liệu không hợp lệ
  bool _isSubmitting = false; // Trạng thái đang bấm nút lưu

  @override
  void initState() {
    super.initState();
    _fetchProfile(); // Tải dữ liệu hồ sơ cá nhân hiện tại từ máy chủ
  }

  @override
  void dispose() {
    _avatarController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // PHẦN 2: CÁC HÀM XỬ LÝ (GỌI API VỀ MÁY CHỦ & KIỂM TRA ĐẦU VÀO)
  // ===========================================================================

  /// 1. Tải thông tin hồ sơ hiện có từ máy chủ
  Future<void> _fetchProfile() async {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) return;

    try {
      final response = await http.get(Uri.parse('$API_BASE_URL/api/user-profiles/$userId'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['profile'] != null) {
          final p = data['profile'];
          if (mounted) {
            setState(() {
              _avatarController.text = p['avatar'] ?? "";
              _fullNameController.text = p['fullName'] ?? "";
              _phoneController.text = p['phone'] ?? "";
              _position = p['position'] ?? POSITIONS[0];
              _locationController.text = p['location'] ?? "";
              _isLookingForTeam = p['isLookingForTeam'] ?? true;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Lỗi tải thông tin hồ sơ: $e");
    }
  }

  /// 2. Kiểm tra tính hợp lệ của dữ liệu trước khi lưu
  bool _validateInput() {
    final fullName = _fullNameController.text.trim();
    final phone = _phoneController.text.trim();
    final location = _locationController.text.trim();

    final phoneRegex = RegExp(r'^(0|84|\+84)(3|5|7|8|9)([0-9]{8})$');
    final invalidNameCharsRegex = RegExp(r'[0-9!@#$%^&*()_+\-=\[\]{};'':"\\|,.<>/?]');

    // Kiểm tra họ tên
    if (fullName.isEmpty) {
      setState(() => _errorMessage = "Vui lòng nhập họ và tên của bạn.");
      return false;
    }
    if (fullName.length < 4 || fullName.length > 50) {
      setState(() => _errorMessage = "Họ tên phải có độ dài từ 4 đến 50 ký tự.");
      return false;
    }
    final words = fullName.split(RegExp(r'\s+'));
    if (words.length < 2 || invalidNameCharsRegex.hasMatch(fullName)) {
      setState(() => _errorMessage = "Vui lòng nhập đầy đủ cả họ và tên (tối thiểu 2 từ, không chứa số/ký tự lạ).");
      return false;
    }

    // Kiểm tra số điện thoại
    if (phone.isEmpty) {
      setState(() => _errorMessage = "Vui lòng nhập số điện thoại.");
      return false;
    }
    if (!phoneRegex.hasMatch(phone)) {
      setState(() => _errorMessage = "Số điện thoại không đúng định dạng (Ví dụ: 0912345678).");
      return false;
    }

    // Kiểm tra địa chỉ
    if (location.isEmpty) {
      setState(() => _errorMessage = "Vui lòng nhập địa chỉ / khu vực bạn thường đá bóng.");
      return false;
    }
    if (location.length < 5) {
      setState(() => _errorMessage = "Địa chỉ quá ngắn. Vui lòng nhập chi tiết hơn (tối thiểu 5 ký tự).");
      return false;
    }

    return true;
  }

  /// 3. Lưu thông tin hồ sơ lên máy chủ
  Future<void> _handleSaveProfile() async {
    if (_isSubmitting) return;
    setState(() => _errorMessage = "");

    if (!_validateInput()) return;

    setState(() => _isSubmitting = true);

    try {
      final userId = context.read<AuthProvider>().userId;
      if (userId == null) throw Exception("Không tìm thấy thông tin tài khoản đăng nhập");

      final response = await http.post(
        Uri.parse('$API_BASE_URL/api/user-profiles'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          "avatar": _avatarController.text.trim(),
          "fullName": _fullNameController.text.trim(),
          "phone": _phoneController.text.trim(),
          "position": _position,
          "location": _locationController.text.trim(),
          "isLookingForTeam": _isLookingForTeam,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        final data = jsonDecode(response.body);
        throw Exception(data['message'] ?? "Lưu thông tin thất bại");
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cập nhật hồ sơ thành công!'),
            backgroundColor: Color(0xFF16A34A),
          ),
        );
        context.go('/'); // Về trang chủ
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString().replaceAll("Exception: ", ""));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// 4. Đăng xuất tài khoản
  void _handleLogout() {
    context.read<AuthProvider>().logout();
    context.go('/');
  }

  // ===========================================================================
  // PHẦN 3: GIAO DIỆN CHÍNH (BUILD)
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final username = context.read<AuthProvider>().username ?? "Người dùng";

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F4),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 36),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Tiêu đề chào mừng
              _buildHeader(username),

              // 2. Khung ảnh đại diện (Avatar)
              _buildAvatarCard(username),

              // 3. Khung nhập Họ tên & Số điện thoại
              const Text('Họ và tên', style: TextStyle(color: Color(0xFF2F3B33), fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              _buildInputField(_fullNameController, 'Nguyễn Văn An'),

              const Text('Số điện thoại', style: TextStyle(color: Color(0xFF2F3B33), fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              _buildInputField(_phoneController, '09xx xxx xxx', keyboardType: TextInputType.phone),

              // 4. Khung chọn vị trí thi đấu
              const Text('Vị trí thi đấu sở trường', style: TextStyle(color: Color(0xFF2F3B33), fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              _buildPositionSelector(),
              const SizedBox(height: 16),

              // 5. Khung nhập địa chỉ / khu vực
              const Text('Địa chỉ / Khu vực', style: TextStyle(color: Color(0xFF2F3B33), fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              _buildInputField(_locationController, 'vd: Quận 7, TP.HCM'),

              // 6. Thông báo lỗi (nếu có)
              if (_errorMessage.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Text(_errorMessage, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],

              // 7. Các nút bấm (Lưu hồ sơ & Đăng xuất)
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // PHẦN 4: CÁC WIDGET CON (TÁCH NHỎ CODE ĐỂ ĐƠN GIẢN VÀ DỄ HIỂU)
  // ===========================================================================

  /// Tiêu đề trên cùng
  Widget _buildHeader(String username) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Xin chào, $username 👋', style: const TextStyle(color: Color(0xFF22C55E), fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Hồ sơ cầu thủ', style: TextStyle(color: Color(0xFF17201A), fontSize: 28, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  /// Khung ảnh đại diện (Avatar)
  Widget _buildAvatarCard(String username) {
    final avatarText = _avatarController.text.trim();
    final firstLetter = username.isNotEmpty ? username.substring(0, 1).toUpperCase() : 'U';

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDFE7DF)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: const Color(0xFFE7F2E5),
              borderRadius: BorderRadius.circular(34),
            ),
            clipBehavior: Clip.hardEdge,
            alignment: Alignment.center,
            child: avatarText.isNotEmpty
                ? Image.network(
                    avatarText,
                    fit: BoxFit.cover,
                    width: 68,
                    height: 68,
                    errorBuilder: (ctx, error, stackTrace) => Text(firstLetter, style: const TextStyle(color: Color(0xFF22C55E), fontSize: 24, fontWeight: FontWeight.w900)),
                  )
                : Text(firstLetter, style: const TextStyle(color: Color(0xFF22C55E), fontSize: 24, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Link ảnh đại diện (URL)', style: TextStyle(color: Color(0xFF2F3B33), fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                TextField(
                  controller: _avatarController,
                  onChanged: (_) => setState(() {}), // Cập nhật xem trước ảnh
                  style: const TextStyle(fontSize: 14, color: Color(0xFF17201A)),
                  decoration: InputDecoration(
                    hintText: 'Dán đường dẫn ảnh...',
                    hintStyle: const TextStyle(color: Color(0xFF8B98A5), fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFFF9FBF8),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD7E1D8))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF22C55E))),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Khung chọn vị trí thi đấu (4 vị trí bóng đá)
  Widget _buildPositionSelector() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: POSITIONS.map((pos) {
        final isSelected = _position == pos;
        return GestureDetector(
          onTap: () {
            setState(() {
              _position = pos;
              _errorMessage = "";
            });
          },
          child: Container(
            width: (MediaQuery.of(context).size.width - 44 - 10) / 2, // Chia đều 2 cột
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF22C55E) : Colors.white,
              border: Border.all(color: isSelected ? const Color(0xFF22C55E) : const Color(0xFFD7E1D8)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              pos,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF2F3B33),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Ô nhập liệu chuẩn
  Widget _buildInputField(TextEditingController controller, String hintText, {TextInputType? keyboardType}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: (_) {
          if (_errorMessage.isNotEmpty) setState(() => _errorMessage = "");
        },
        style: const TextStyle(fontSize: 15, color: Color(0xFF17201A)),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: Color(0xFF8B98A5), fontSize: 14),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFD7E1D8))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF22C55E))),
        ),
      ),
    );
  }

  /// Nút bấm Lưu hồ sơ và Nút Đăng xuất
  Widget _buildActionButtons() {
    return Column(
      children: [
        ElevatedButton(
          onPressed: _isSubmitting ? null : _handleSaveProfile,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF22C55E),
            disabledBackgroundColor: const Color(0xFF86EFAC),
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: _isSubmitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Lưu thông tin hồ sơ', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _handleLogout,
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFEF4444)),
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Đăng xuất tài khoản', style: TextStyle(color: Color(0xFFEF4444), fontSize: 15, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
