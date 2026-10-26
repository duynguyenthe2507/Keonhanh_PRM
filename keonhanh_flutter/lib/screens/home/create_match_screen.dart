import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../services/auth_provider.dart';
import '../../config/api.dart';
import 'dart:async';

/// Màn hình: TẠO KÈO ĐẤU MỚI (CreateMatchScreen)
/// Chức năng: Cho phép đội trưởng/người dùng tạo một trận đấu mới,
/// chọn thời gian, địa điểm, tìm kiếm sân trên bản đồ OpenStreetMap để ghim tọa độ.
class CreateMatchScreen extends StatefulWidget {
  const CreateMatchScreen({super.key});

  @override
  State<CreateMatchScreen> createState() => _CreateMatchScreenState();
}

class _CreateMatchScreenState extends State<CreateMatchScreen> {
  // ===========================================================================
  // PHẦN 1: CÁC BIẾN QUẢN LÝ DỮ LIỆU (STATE)
  // ===========================================================================

  // Bộ điều khiển nhập liệu cho Địa điểm (Quận/Huyện, Thành phố)
  final TextEditingController _locationController = TextEditingController();

  // Bộ điều khiển nhập liệu cho Tên sân bóng cụ thể
  final TextEditingController _fieldNameController = TextEditingController();

  // Ngày thi đấu đã chọn
  DateTime? _selectedDate;

  // Giờ thi đấu đã chọn
  TimeOfDay? _selectedTime;

  // Trạng thái đang gửi yêu cầu tạo kèo lên máy chủ
  bool _loading = false;

  // Lưu trữ các câu thông báo lỗi cho từng trường nhập liệu
  Map<String, String> _errors = {};

  // --- Các biến liên quan đến tính năng Tìm kiếm sân trên bản đồ (OpenStreetMap) ---
  bool _showMapSearch = false; // Ẩn/Hiện hộp thoại tìm kiếm bản đồ
  final TextEditingController _mapSearchController = TextEditingController();
  List<dynamic> _searchResults = []; // Danh sách các địa điểm tìm thấy
  Timer? _searchTimer; // Bộ đếm thời gian debounce (chờ người dùng gõ xong mới tìm)
  Map<String, double>? _mapCoordinate; // Tọa độ ghim {latitude, longitude}

  @override
  void dispose() {
    // Hủy các controller và bộ đếm giờ để giải phóng bộ nhớ
    _locationController.dispose();
    _fieldNameController.dispose();
    _mapSearchController.dispose();
    _searchTimer?.cancel();
    super.dispose();
  }

  // ===========================================================================
  // PHẦN 2: CÁC HÀM XỬ LÝ (GỌI API VỀ MÁY CHỦ / VALIDATION / THỜI GIAN)
  // ===========================================================================

  /// Hàm tìm kiếm địa chỉ sân qua OpenStreetMap Nominatim API khi người dùng gõ phím
  void _onSearchChange(String text) {
    if (_searchTimer?.isActive ?? false) _searchTimer!.cancel();
    if (text.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    // Đợi 800ms sau khi người dùng ngừng gõ để tránh gửi quá nhiều yêu cầu mạng
    _searchTimer = Timer(const Duration(milliseconds: 800), () async {
      try {
        final res = await http.get(
          Uri.parse(
            'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(text)}&addressdetails=1&limit=5',
          ),
          headers: {'User-Agent': 'KeonhanhApp/1.0'},
        );
        if (res.statusCode == 200) {
          setState(() => _searchResults = jsonDecode(res.body));
        }
      } catch (e) {
        debugPrint('Lỗi tìm kiếm bản đồ: $e');
      }
    });
  }

  /// Hàm xử lý khi người dùng chọn một sân bóng từ kết quả tìm kiếm bản đồ
  void _selectSearchResult(dynamic item) {
    final lat = double.tryParse(item['lat'].toString());
    final lon = double.tryParse(item['lon'].toString());
    if (lat != null && lon != null) {
      _mapCoordinate = {'latitude': lat, 'longitude': lon};
    }

    final name = item['display_name'].split(',')[0];
    _fieldNameController.text = name;

    if (item['address'] != null) {
      final address = item['address'];
      final loc = address['city'] ?? address['state'] ?? address['county'];
      if (loc != null) _locationController.text = loc;
    }

    // Đóng hộp thoại tìm kiếm và dọn dẹp kết quả
    setState(() {
      _showMapSearch = false;
      _mapSearchController.clear();
      _searchResults = [];
    });
  }

  /// Xóa lỗi khi người dùng gõ vào ô nhập liệu
  void _handleChange(String field, String value) {
    if (_errors.containsKey(field)) {
      setState(() => _errors.remove(field));
    }
  }

  /// Kiểm tra dữ liệu nhập có hợp lệ không trước khi tạo kèo
  bool _validate() {
    Map<String, String> newErrors = {};
    if (_locationController.text.trim().isEmpty) {
      newErrors['location'] = 'Vui lòng nhập địa điểm';
    }
    if (_fieldNameController.text.trim().isEmpty) {
      newErrors['fieldName'] = 'Vui lòng nhập tên sân';
    }

    if (_selectedDate == null || _selectedTime == null) {
      newErrors['playTime'] = 'Vui lòng chọn ngày và giờ thi đấu';
    } else {
      final date = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );
      if (date.isBefore(DateTime.now())) {
        newErrors['playTime'] = 'Thời gian thi đấu phải lớn hơn hiện tại';
      }
    }

    setState(() => _errors = newErrors);
    return newErrors.isEmpty;
  }

  /// Mở hộp thoại chọn ngày
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _errors.remove('playTime');
      });
    }
  }

  /// Mở hộp thoại chọn giờ
  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
        _errors.remove('playTime');
      });
    }
  }

  /// Gọi API tạo trận đấu mới
  Future<void> _handleCreateMatch() async {
    if (!_validate()) return;
    setState(() => _loading = true);

    try {
      final date = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );

      final userId = context.read<AuthProvider>().userId;

      final res = await http.post(
        Uri.parse('$API_BASE_URL/api/matches'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'location': _locationController.text.trim(),
          'fieldName': _fieldNameController.text.trim(),
          'playTime': date.toIso8601String(),
          'latitude': _mapCoordinate?['latitude'],
          'longitude': _mapCoordinate?['longitude'],
        }),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('🎉 Thành công'),
            content: Text(data['message'] ?? 'Đăng kèo thành công!'),
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
        _showError(data['message'] ?? 'Không thể tạo kèo. Thử lại!');
      }
    } catch (e) {
      _showError('Không thể kết nối đến server. Kiểm tra lại mạng!');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Hiển thị thông báo lỗi
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
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Thanh tiêu đề phía trên
            _buildHeader(),

            // 2. Nội dung form nhập liệu cuộn được
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                child: Column(
                  children: [
                    // Banner quảng bá tạo kèo
                    _buildHeroBanner(),

                    // Khối form nhập thông tin trận đấu
                    _buildMatchFormCard(),

                    // Nhóm nút bấm Đăng kèo / Hủy bỏ
                    _buildSubmitButtons(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      // 3. Khung tìm kiếm vị trí sân trên bản đồ (hiển thị khi bấm "Tìm trên bản đồ")
      bottomSheet: _showMapSearch ? _buildMapSearchSheet() : null,
    );
  }

  // ===========================================================================
  // PHẦN 4: CÁC WIDGET CON (TÁCH NHỎ CODE, DỄ ĐỌC VÀ BẢO TRÌ)
  // ===========================================================================

  /// Widget 1: Thanh tiêu đề đầu trang
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 3,
            offset: Offset(0, 1),
          )
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.arrow_back, color: Color(0xFF22C55E)),
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Tạo kèo mới ⚽',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111111),
                ),
              ),
            ),
          ),
          const SizedBox(width: 40), // Cân bằng khoảng trống với nút quay lại
        ],
      ),
    );
  }

  /// Widget 2: Banner màu xanh nổi bật
  Widget _buildHeroBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D22C55E),
            blurRadius: 8,
            offset: Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(64),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.sports_soccer, color: Colors.white, size: 36),
          ),
          const Text(
            'Đăng kèo tìm đối thủ',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Điền thông tin trận đấu để ghép kèo ngay!',
            style: TextStyle(
              color: Colors.white.withAlpha(217),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// Widget 3: Thẻ chứa toàn bộ Form nhập thông tin trận đấu
  Widget _buildMatchFormCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Trường 1: Địa điểm
          _buildLabel(Icons.location_on, 'Địa điểm'),
          _buildTextField(_locationController, 'location', 'VD: Quận 1, TP.HCM'),
          const SizedBox(height: 18),

          // Trường 2: Tên sân bóng + Nút tìm trên bản đồ
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildLabel(Icons.business, 'Tên sân bóng'),
              GestureDetector(
                onTap: () => setState(() => _showMapSearch = true),
                child: const Row(
                  children: [
                    Icon(Icons.map, size: 14, color: Color(0xFF3B82F6)),
                    SizedBox(width: 4),
                    Text(
                      'Tìm trên bản đồ',
                      style: TextStyle(
                        color: Color(0xFF3B82F6),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          _buildTextField(_fieldNameController, 'fieldName', 'VD: Sân Phú Thọ'),

          // Đã ghim tọa độ
          if (_mapCoordinate != null)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.check_circle, size: 14, color: Color(0xFF22C55E)),
                  SizedBox(width: 4),
                  Text(
                    'Đã ghim tọa độ sân thành công',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF22C55E),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),

          // Trường 3: Thời gian thi đấu
          _buildPlayTimePicker(),
          const SizedBox(height: 18),

          // Thông tin lưu ý trạng thái kèo
          _buildStatusNotice(),
        ],
      ),
    );
  }

  /// Widget 4: Khối chọn ngày và giờ thi đấu
  Widget _buildPlayTimePicker() {
    String playTimeStr = "Chạm để chọn Ngày/Giờ";
    if (_selectedDate != null && _selectedTime != null) {
      final hour = _selectedTime!.hour.toString().padLeft(2, '0');
      final minute = _selectedTime!.minute.toString().padLeft(2, '0');
      final day = _selectedDate!.day.toString().padLeft(2, '0');
      final month = _selectedDate!.month.toString().padLeft(2, '0');
      final year = _selectedDate!.year;
      playTimeStr = "$hour:$minute - $day/$month/$year";
    }

    final hasError = _errors.containsKey('playTime');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(Icons.access_time, 'Thời gian thi đấu'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            border: Border.all(
              color: hasError ? const Color(0xFFEF4444) : const Color(0xFFE5E7EB),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            playTimeStr,
            style: TextStyle(
              color: _selectedDate != null
                  ? const Color(0xFF111111)
                  : const Color(0xFFAAAAAA),
              fontSize: 15,
              fontWeight: _selectedDate != null ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _errors['playTime']!,
              style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 16, color: Colors.white),
                label: const Text('Chọn ngày', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6B7280),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule, size: 16, color: Colors.white),
                label: const Text('Chọn giờ', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6B7280),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Widget 5: Hộp thông báo ghi chú trạng thái
  Widget _buildStatusNotice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: Color(0xFF3B82F6)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Kèo sẽ có trạng thái "Đang mở" sau khi đăng. Các đội khác có thể xem và nhận kèo của bạn.',
              style: TextStyle(fontSize: 13, color: Color(0xFF1D4ED8), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  /// Widget 6: Nhóm nút Đăng Kèo và Hủy Bỏ
  Widget _buildSubmitButtons() {
    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: _loading ? null : _handleCreateMatch,
          icon: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.sports_soccer, color: Colors.white, size: 20),
          label: const Text(
            'Đăng kèo ngay',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF22C55E),
            disabledBackgroundColor: const Color(0xFF86EFAC),
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: _loading ? 0 : 4,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => context.pop(),
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFD1D5DB), width: 1.5),
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

  /// Widget 7: Khung kéo lên phía dưới để tìm kiếm bản đồ
  Widget _buildMapSearchSheet() {
    return Container(
      height: 350,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, -2),
          )
        ],
      ),
      child: Column(
        children: [
          // Thanh tìm kiếm trong sheet
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _mapSearchController,
                    onChanged: _onSearchChange,
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm khu vực / tên sân...',
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
                      filled: true,
                      fillColor: const Color(0xFFF1F5F9),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _showMapSearch = false),
                ),
              ],
            ),
          ),
          // Danh sách các kết quả tìm thấy
          Expanded(
            child: ListView.separated(
              itemCount: _searchResults.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final item = _searchResults[i];
                return ListTile(
                  leading: const Icon(
                    Icons.location_on_outlined,
                    color: Color(0xFF64748B),
                  ),
                  title: Text(
                    item['display_name'] ?? "",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  onTap: () => _selectSearchResult(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Widget trợ giúp: Nhãn tiêu đề mục nhập
  Widget _buildLabel(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFF22C55E)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
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
    String hint,
  ) {
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
