import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../config/api.dart';

/// Màn hình: TẤT CẢ KÈO ĐẤU ĐANG TÌM ĐỐI (AllMatchesScreen)
/// Chức năng: Hiển thị toàn bộ các trận đấu đang có trạng thái "Đang mở" (open).
/// Người dùng có thể xem danh sách, lọc và bấm vào để xem chi tiết hoặc bắt kèo.
class AllMatchesScreen extends StatefulWidget {
  const AllMatchesScreen({super.key});

  @override
  State<AllMatchesScreen> createState() => _AllMatchesScreenState();
}

class _AllMatchesScreenState extends State<AllMatchesScreen> {
  // ===========================================================================
  // PHẦN 1: CÁC BIẾN QUẢN LÝ DỮ LIỆU (STATE)
  // ===========================================================================

  // Danh sách các kèo đấu đang mở được lấy từ API
  List<dynamic> _matches = [];

  // Trạng thái đang tải dữ liệu từ máy chủ
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Tự động gọi API tải danh sách kèo khi mở màn hình
    _fetchOpenMatches();
  }

  // ===========================================================================
  // PHẦN 2: CÁC HÀM XỬ LÝ (GỌI API VỀ MÁY CHỦ)
  // ===========================================================================

  /// Lấy toàn bộ các kèo có trạng thái 'open' từ Server
  Future<void> _fetchOpenMatches() async {
    setState(() => _loading = true);

    try {
      final res = await http.get(Uri.parse('$API_BASE_URL/api/matches'));
      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && data['success'] == true) {
        final matchesData = data['data'] as List? ?? [];

        // Chỉ lọc các kèo đang tìm đối (status == 'open')
        final openMatches = matchesData.where((m) => m['status'] == 'open').toList();

        // Định dạng dữ liệu hiển thị cho gọn gàng và dễ hiểu
        final formatted = openMatches.map((m) {
          final date = DateTime.tryParse(m['playTime'] ?? '')?.toLocal() ?? DateTime.now();
          final hStr = date.hour.toString().padLeft(2, '0');
          final mStr = date.minute.toString().padLeft(2, '0');

          String timeStr;
          if (date.hour == 0 && date.minute == 0) {
            timeStr = "${date.day}/${date.month}/${date.year}";
          } else {
            timeStr = "$hStr:$mStr - ${date.day}/${date.month}/${date.year}";
          }

          return {
            'id': m['_id'],
            'team': m['creatorTeamId'] != null ? m['creatorTeamId']['name'] : 'Đội ẩn danh',
            'field': m['fieldName'] ?? 'Sân chưa xác định',
            'time': timeStr,
            'status': 'Đang tìm đối',
          };
        }).toList();

        // Kèo mới nhất được xếp lên trên đầu danh sách
        if (mounted) {
          setState(() => _matches = formatted.reversed.toList());
        }
      } else {
        if (mounted) setState(() => _matches = []);
      }
    } catch (e) {
      debugPrint("Lỗi tải danh sách tất cả kèo đang mở: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ===========================================================================
  // PHẦN 3: GIAO DIỆN CHÍNH (BUILD)
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Thanh tiêu đề đầu trang
            _buildHeader(),

            // 2. Nội dung danh sách kèo hoặc trạng thái chờ
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF22C55E)),
                    )
                  : _matches.isEmpty
                      ? _buildEmptyView()
                      : _buildMatchList(),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // PHẦN 4: CÁC WIDGET CON (TÁCH NHỎ CODE, DỄ ĐỌC VÀ BẢO TRÌ)
  // ===========================================================================

  /// Widget 1: Thanh tiêu đề với nút quay lại và tên màn hình
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          // Nút quay lại màn hình trước
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
          // Tiêu đề căn giữa
          const Expanded(
            child: Center(
              child: Text(
                'Kèo đang tìm đối ⚽',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111111),
                ),
              ),
            ),
          ),
          const SizedBox(width: 40), // Cân bằng khoảng cách hai bên
        ],
      ),
    );
  }

  /// Widget 2: Giao diện hiển thị khi không có kèo nào đang mở
  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.sports_soccer, size: 48, color: Color(0xFF999999)),
          const SizedBox(height: 12),
          const Text(
            'Chưa có kèo nào đang mở',
            style: TextStyle(fontSize: 16, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  /// Widget 3: Danh sách các kèo đấu có hỗ trợ kéo vuốt làm mới
  Widget _buildMatchList() {
    return RefreshIndicator(
      onRefresh: _fetchOpenMatches,
      color: const Color(0xFF22C55E),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _matches.length,
        itemBuilder: (ctx, i) => _buildMatchCard(_matches[i]),
      ),
    );
  }

  /// Widget 4: Thẻ hiển thị một trận đấu
  Widget _buildMatchCard(dynamic item) {
    return GestureDetector(
      onTap: () => context.push('/matchDetail', extra: {'matchId': item['id']}),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEEEEE)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            )
          ],
        ),
        child: Column(
          children: [
            // Dòng trên: Tên đội và huy hiệu Đang tìm đối
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    item['team'],
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF333333),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    item['status'],
                    style: const TextStyle(
                      color: Color(0xFF16A34A),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              ],
            ),
            const SizedBox(height: 12),

            // Dòng địa điểm sân bóng
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 18, color: Color(0xFF666666)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item['field'],
                    style: const TextStyle(fontSize: 14, color: Color(0xFF666666)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Dòng thời gian thi đấu
            Row(
              children: [
                const Icon(Icons.schedule, size: 18, color: Color(0xFF666666)),
                const SizedBox(width: 8),
                Text(
                  item['time'],
                  style: const TextStyle(fontSize: 14, color: Color(0xFF666666)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Nút bấm Xem / Tham gia kèo
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Xem / Tham gia kèo',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
