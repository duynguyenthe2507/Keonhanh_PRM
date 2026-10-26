import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../services/auth_provider.dart';
import '../../config/api.dart';

/// Màn hình: TẠO ĐỘI BÓNG MỚI (CreateTeamScreen)
/// Chức năng: Cho phép người dùng nhập thông tin để thành lập một đội bóng mới.
/// Người tạo sẽ tự động trở thành Đội trưởng (Captain).
class CreateTeamScreen extends StatefulWidget {
  const CreateTeamScreen({super.key});

  @override
  State<CreateTeamScreen> createState() => _CreateTeamScreenState();
}

class _CreateTeamScreenState extends State<CreateTeamScreen> {
  // ===========================================================================
  // PHẦN 1: CÁC BIẾN QUẢN LÝ DỮ LIỆU (STATE)
  // ===========================================================================

  // Bộ điều khiển nhập liệu cho Tên đội bóng
  final TextEditingController _nameController = TextEditingController();

  // Bộ điều khiển nhập liệu cho Địa điểm hoạt động của đội
  final TextEditingController _locationController = TextEditingController();

  // Bộ điều khiển nhập liệu cho đường link ảnh Logo đội (URL)
  final TextEditingController _logoController = TextEditingController();

  // Trình độ của đội bóng (Mặc định là Sơ cấp)
  String _skillLevel = 'Sơ cấp';

  // Trạng thái: Đội có đang tuyển thành viên mới hay không?
  bool _isRecruiting = true;

  // Bản đồ lưu trữ các lỗi nhập liệu (Key là tên trường, Value là câu thông báo lỗi)
  Map<String, String> _errors = {};

  // Trạng thái đang tải dữ liệu / đang gọi API tạo đội
  bool _loading = false;

  // Bảng màu tương ứng với từng cấp độ kỹ năng
  final Map<String, Color> _skillColors = {
    'Sơ cấp': const Color(0xFF22C55E),       // Xanh lá
    'Trung cấp': const Color(0xFFF59E0B),    // Vàng cam
    'Chuyên nghiệp': const Color(0xFFEF4444), // Đỏ
  };

  @override
  void dispose() {
    // Giải phóng bộ nhớ khi rời khỏi màn hình
    _nameController.dispose();
    _locationController.dispose();
    _logoController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // PHẦN 2: CÁC HÀM XỬ LÝ (GỌI API VỀ MÁY CHỦ / VALIDATION)
  // ===========================================================================

  /// Hàm xóa thông báo lỗi khi người dùng bắt đầu gõ chữ vào ô nhập
  void _handleChange(String field, String value) {
    if (_errors.containsKey(field)) {
      setState(() => _errors.remove(field));
    }
    setState(() {}); // Cập nhật lại giao diện (ví dụ xem trước ảnh logo khi nhập URL)
  }

  /// Hàm kiểm tra tính hợp lệ của dữ liệu trước khi gửi lên máy chủ
  bool _validate() {
    Map<String, String> newErrors = {};

    if (_nameController.text.trim().isEmpty) {
      newErrors['name'] = 'Vui lòng nhập tên đội';
    }
    if (_locationController.text.trim().isEmpty) {
      newErrors['location'] = 'Vui lòng nhập địa điểm';
    }

    // Kiểm tra xem người dùng đã đăng nhập chưa
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) {
      newErrors['captain'] = 'Bạn phải đăng nhập để tạo đội';
    }

    setState(() => _errors = newErrors);
    return newErrors.isEmpty;
  }

  /// Hàm gửi dữ liệu tạo đội mới lên Server
  Future<void> _handleCreateTeam() async {
    // Nếu kiểm tra dữ liệu chưa đạt yêu cầu thì dừng lại
    if (!_validate()) return;

    setState(() => _loading = true);

    try {
      final userId = context.read<AuthProvider>().userId;

      // Gửi yêu cầu POST lên API
      final res = await http.post(
        Uri.parse('$API_BASE_URL/api/teams'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': _nameController.text.trim(),
          'logo': _logoController.text.trim(),
          'captainId': userId,
          'location': _locationController.text.trim(),
          'skillLevel': _skillLevel,
          'isRecruiting': _isRecruiting,
          'players': [],
        }),
      );

      final data = jsonDecode(res.body);

      // Nếu tạo thành công (mã 200 hoặc 201)
      if (res.statusCode == 200 || res.statusCode == 201) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Thành công'),
            content: const Text('Tạo đội thành công!'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.pop(); // Quay về màn hình trước
                },
                child: const Text('OK', style: TextStyle(color: Color(0xFF22C55E))),
              )
            ],
          ),
        );
      } else {
        _showError(data['message'] ?? 'Không thể tạo đội.');
      }
    } catch (e) {
      _showError('Không thể kết nối tới server.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Hiển thị thông báo lỗi dưới chân màn hình (SnackBar)
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // ===========================================================================
  // PHẦN 3: GIAO DIỆN CHÍNH (BUILD)
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final username = context.read<AuthProvider>().username ?? 'Chưa đăng nhập';

    return Scaffold(
      backgroundColor: const Color(0xFFF4FDF4),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Thanh tiêu đề phía trên
            _buildHeader(),

            // 2. Nội dung cuộn chính
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 48),
                child: Column(
                  children: [
                    // Banner giới thiệu thành lập đội
                    _buildHeroBanner(),

                    // Thẻ thông tin Đội trưởng hiện tại
                    _buildCaptainCard(username),

                    // Khối form nhập thông tin đội bóng
                    _buildTeamFormCard(),

                    // Hộp lưu ý thông báo quyền hạn
                    _buildNoticeBox(),

                    const SizedBox(height: 8),

                    // Nút bấm xác nhận tạo đội hoặc hủy
                    _buildActionButtons(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // PHẦN 4: CÁC WIDGET CON (TÁCH NHỎ CODE, DỄ ĐỌC VÀ BẢO TRÌ)
  // ===========================================================================

  /// Widget 1: Thanh tiêu đề trên cùng với nút quay lại
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF16A34A),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x4D14532D),
            offset: Offset(0, 6),
            blurRadius: 10,
          )
        ],
      ),
      child: Row(
        children: [
          // Nút bấm quay lại
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
              ),
              child: const Icon(Icons.arrow_back, color: Color(0xFF16A34A)),
            ),
          ),
          const SizedBox(width: 12),
          // Tiêu đề trang
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GIA NHẬP LÀNG BÓNG 🌟',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFFDCFCE7),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Tạo Đội Mới',
                style: TextStyle(
                  fontSize: 24,
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Widget 2: Banner chào mừng màu xanh lá
  Widget _buildHeroBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF16A34A),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D16A34A),
            blurRadius: 8,
            offset: Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(51),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.security, color: Colors.white, size: 38),
          ),
          const Text(
            'Thành lập đội bóng',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tập hợp đồng đội và chinh phục sân cỏ!',
            style: TextStyle(
              color: Colors.white.withAlpha(217),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// Widget 3: Khối thông tin Đội trưởng
  Widget _buildCaptainCard(String username) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFDCFCE7), width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              )
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                margin: const EdgeInsets.only(right: 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF22C55E),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, color: Colors.white, size: 22),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Đội trưởng',
                      style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      username,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111111),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF9C3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.star, size: 12, color: Color(0xFFF59E0B)),
                    SizedBox(width: 4),
                    Text(
                      'Captain',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_errors.containsKey('captain'))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _errors['captain']!,
              style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
            ),
          ),
      ],
    );
  }

  /// Widget 4: Form nhập thông tin đội bóng
  Widget _buildTeamFormCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Trường 1: Tên đội bóng
          _buildLabel(Icons.security_outlined, 'Tên đội bóng', required: true),
          _buildTextField(_nameController, 'name', 'VD: FC Rồng Vàng'),
          const SizedBox(height: 18),

          // Trường 2: Link logo đội bóng (URL)
          _buildLabel(Icons.image_outlined, 'Logo đội bóng (URL)', required: false),
          _buildTextField(_logoController, 'logo', 'https://...', isOptional: true),
          
          // Khối xem trước Logo nếu người dùng đã nhập link
          if (_logoController.text.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              alignment: Alignment.center,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF22C55E), width: 3),
                ),
                clipBehavior: Clip.hardEdge,
                child: Image.network(
                  _logoController.text,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.broken_image,
                    color: Colors.grey,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 18),

          // Trường 3: Địa điểm hoạt động
          _buildLabel(Icons.location_on_outlined, 'Địa điểm', required: true),
          _buildTextField(_locationController, 'location', 'VD: Quận 1, TP.HCM'),
          const SizedBox(height: 18),

          // Trường 4: Trình độ kỹ năng của đội
          _buildLabel(Icons.emoji_events_outlined, 'Trình độ', required: false),
          _buildSkillSelector(),
          const SizedBox(height: 18),

          // Trường 5: Nút gạt chuyển trạng thái tuyển thành viên
          _buildRecruitingSwitch(),
        ],
      ),
    );
  }

  /// Widget 5: Bộ chọn trình độ kỹ năng
  Widget _buildSkillSelector() {
    return Row(
      children: ['Sơ cấp', 'Trung cấp', 'Chuyên nghiệp'].map((level) {
        final active = _skillLevel == level;
        final color = _skillColors[level]!;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _skillLevel = level),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: active ? color : const Color(0xFFF9FAFB),
                border: Border.all(
                  color: active ? color : const Color(0xFFE5E7EB),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                level,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : const Color(0xFF6B7280),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Widget 6: Cần gạt mở/đóng tuyển quân
  Widget _buildRecruitingSwitch() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.people_outline, color: Color(0xFF22C55E), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Đang tuyển thành viên',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isRecruiting ? 'Đội đang mở tuyển' : 'Đội đã đủ người',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
          ),
          Switch(
            value: _isRecruiting,
            onChanged: (v) => setState(() => _isRecruiting = v),
            activeThumbColor: const Color(0xFF22C55E),
            activeTrackColor: const Color(0xFF86EFAC),
            inactiveThumbColor: const Color(0xFF9CA3AF),
            inactiveTrackColor: const Color(0xFFD1D5DB),
          )
        ],
      ),
    );
  }

  /// Widget 7: Hộp ghi chú quyền Đội trưởng
  Widget _buildNoticeBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: Color(0xFF3B82F6)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Bạn sẽ trở thành đội trưởng. Bạn có thể thêm hoặc mời cầu thủ vào sau khi tạo đội thành công.',
              style: TextStyle(fontSize: 13, color: Color(0xFF1D4ED8), height: 1.4),
            ),
          )
        ],
      ),
    );
  }

  /// Widget 8: Nhóm nút hành động Xác nhận / Hủy
  Widget _buildActionButtons() {
    return Column(
      children: [
        // Nút Tạo Đội
        ElevatedButton.icon(
          onPressed: _loading ? null : _handleCreateTeam,
          icon: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.security, color: Colors.white, size: 20),
          label: const Text(
            'Thành lập đội ngay',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF16A34A),
            disabledBackgroundColor: const Color(0xFF86EFAC),
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: _loading ? 0 : 4,
          ),
        ),
        const SizedBox(height: 12),
        // Nút Hủy Bỏ
        OutlinedButton(
          onPressed: () => context.pop(),
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFD1D5DB), width: 1.5),
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: const Text(
            'Hủy bỏ',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  /// Widget trợ giúp: Nhãn tiêu đề cho ô nhập
  Widget _buildLabel(IconData icon, String text, {required bool required}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFF22C55E)),
          const SizedBox(width: 6),
          RichText(
            text: TextSpan(
              text: text,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
              children: [
                if (required)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: Color(0xFFEF4444)),
                  ),
                if (!required)
                  const TextSpan(
                    text: ' tuỳ chọn',
                    style: TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontWeight: FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Widget trợ giúp: Ô nhập dữ liệu Text
  Widget _buildTextField(
    TextEditingController controller,
    String field,
    String hint, {
    bool isOptional = false,
  }) {
    final hasError = _errors.containsKey(field);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          onChanged: (v) => _handleChange(field, v),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFFAAAAAA)),
            filled: true,
            fillColor: hasError ? const Color(0xFFFEF2F2) : const Color(0xFFF9FAFB),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: hasError ? const Color(0xFFEF4444) : const Color(0xFFE5E7EB),
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: hasError ? const Color(0xFFEF4444) : const Color(0xFF22C55E),
                width: 1.5,
              ),
            ),
          ),
          style: const TextStyle(fontSize: 15, color: Color(0xFF111111)),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              _errors[field]!,
              style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
            ),
          ),
      ],
    );
  }
}
