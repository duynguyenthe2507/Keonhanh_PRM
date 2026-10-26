import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../services/auth_provider.dart';
import '../../config/api.dart';

/// Màn hình: CHI TIẾT KÈO ĐẤU (MatchDetailScreen)
/// Chức năng: Hiển thị đầy đủ thông tin về một trận đấu:
/// - 2 đội đối đầu (Đội nhà vs Đội khách/đang tìm)
/// - Thời gian, ngày đá, tên sân, khu vực
/// - Nút "Bắt Kèo Ngay" cho đội trưởng đội khác
/// - Nút "Hủy Kèo" / "Xóa Kèo" cho đội trưởng đội tạo kèo
class MatchDetailScreen extends StatefulWidget {
  final String matchId;
  const MatchDetailScreen({super.key, required this.matchId});

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  // ===========================================================================
  // PHẦN 1: CÁC BIẾN QUẢN LÝ DỮ LIỆU (STATE)
  // ===========================================================================

  // Dữ liệu chi tiết của trận đấu lấy từ Server
  dynamic _match;

  // Danh sách các đội mà người dùng hiện tại đang tham gia
  List<dynamic> _myTeams = [];

  // Trạng thái đang tải dữ liệu ban đầu
  bool _loading = true;

  // Trạng thái đang thực hiện hành động (Bắt kèo / Hủy kèo / Xóa kèo)
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    // Khởi chạy lấy dữ liệu chi tiết kèo và danh sách đội của tôi
    _fetchData();
  }

  // ===========================================================================
  // PHẦN 2: CÁC HÀM XỬ LÝ (GỌI API VỀ MÁY CHỦ / NGHIỆP VỤ)
  // ===========================================================================

  /// Tải thông tin trận đấu và thông tin đội bóng của người dùng
  Future<void> _fetchData() async {
    setState(() => _loading = true);
    final userId = context.read<AuthProvider>().userId;
    await _fetchMatchDetails();

    if (userId != null) {
      await _fetchMyTeam(userId);
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  /// Lấy thông tin chi tiết của kèo từ API
  Future<void> _fetchMatchDetails() async {
    try {
      final res = await http.get(Uri.parse('$API_BASE_URL/api/matches/${widget.matchId}'));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _match = (decoded is Map && decoded['data'] != null) ? decoded['data'] : decoded;
          });
        }
      } else {
        _showAlert('Lỗi', 'Không tìm thấy kèo.');
      }
    } catch (e) {
      debugPrint('Lỗi tải chi tiết kèo: $e');
    }
  }

  /// Lấy danh sách đội mà người dùng đang tham gia
  Future<void> _fetchMyTeam(String userId) async {
    try {
      final profileRes = await http.get(Uri.parse('$API_BASE_URL/api/user-profiles/$userId'));
      if (profileRes.statusCode == 200) {
        final profileData = jsonDecode(profileRes.body);
        final profileId = profileData['profile']['_id'];

        final teamRes = await http.get(Uri.parse('$API_BASE_URL/api/teams/my-team/$profileId'));
        if (teamRes.statusCode == 200) {
          final teamData = jsonDecode(teamRes.body);
          if (teamData['success'] == true && mounted) {
            setState(() => _myTeams = teamData['data'] ?? []);
          }
        }
      }
    } catch (e) {
      debugPrint('Lỗi tải đội của tôi: $e');
    }
  }

  /// Xử lý khi Đội trưởng bấm BẮT KÈO với đội tạo
  Future<void> _handleMatch() async {
    if (_myTeams.isEmpty) {
      _showAlert('Lỗi', 'Bạn chưa có đội bóng. Vui lòng tạo hoặc tham gia đội bóng trước!');
      return;
    }

    final userId = context.read<AuthProvider>().userId;

    // Tìm xem người dùng có làm đội trưởng của đội nào không
    final ledTeam = _myTeams.firstWhere((t) {
      final capId = t['captainId'];
      return (capId is Map ? capId['_id'] : capId) == userId;
    }, orElse: () => null);

    if (ledTeam == null) {
      _showAlert('Lỗi', 'Chỉ đội trưởng mới có quyền bắt kèo với đội khác.');
      return;
    }

    if (_match['creatorTeamId']?['_id'] == ledTeam['_id']) {
      _showAlert('Lỗi', 'Bạn không thể bắt kèo của chính đội mình.');
      return;
    }

    // Hộp thoại xác nhận nhận kèo
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận nhận kèo'),
        content: const Text('Bạn có chắc chắn muốn bắt kèo này với đội của mình không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _processing = true);
              try {
                final res = await http.patch(
                  Uri.parse('$API_BASE_URL/api/matches/${widget.matchId}/match'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'matchedWithTeamId': ledTeam['_id'],
                    'userId': userId,
                  }),
                );
                final data = jsonDecode(res.body);
                if (res.statusCode == 200) {
                  _showAlert('🎉 Thành công', 'Bắt kèo thành công!');
                  await _fetchMatchDetails();
                } else {
                  _showAlert('Lỗi', data['message'] ?? 'Không thể bắt kèo.');
                }
              } catch (e) {
                _showAlert('Lỗi', 'Lỗi kết nối tới máy chủ.');
              } finally {
                if (mounted) setState(() => _processing = false);
              }
            },
            child: const Text('Bắt kèo', style: TextStyle(color: Color(0xFF22C55E))),
          )
        ],
      ),
    );
  }

  /// Xử lý khi Đội trưởng muốn HỦY KÈO (quay về trạng thái đang mở tìm đối)
  Future<void> _handleCancelMatch() async {
    if (_myTeams.isEmpty) return;

    final userId = context.read<AuthProvider>().userId;
    final ledTeam = _myTeams.firstWhere((t) {
      final capId = t['captainId'];
      return (capId is Map ? capId['_id'] : capId) == userId;
    }, orElse: () => null);

    if (ledTeam == null) {
      _showAlert('Lỗi', 'Chỉ đội trưởng mới có quyền hủy kèo.');
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận hủy kèo'),
        content: const Text(
          'Bạn có chắc chắn muốn hủy kèo này không? Kèo sẽ trở lại trạng thái Đang mở.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Không')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _processing = true);
              try {
                final res = await http.patch(
                  Uri.parse('$API_BASE_URL/api/matches/${widget.matchId}/cancel'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({'userId': userId}),
                );
                if (res.statusCode == 200) {
                  _showAlert('Thành công', 'Hủy kèo thành công!');
                  await _fetchMatchDetails();
                } else {
                  _showAlert('Lỗi', 'Không thể hủy kèo.');
                }
              } catch (e) {
                _showAlert('Lỗi', 'Lỗi kết nối.');
              } finally {
                if (mounted) setState(() => _processing = false);
              }
            },
            child: const Text('Hủy kèo', style: TextStyle(color: Colors.red)),
          )
        ],
      ),
    );
  }

  /// Xử lý khi Đội trưởng đội tạo muốn XÓA HẲN KÈO ĐẤU
  Future<void> _handleDeleteMatch() async {
    final userId = context.read<AuthProvider>().userId;
    final ledTeam = _myTeams.firstWhere((t) {
      final capId = t['captainId'];
      return (capId is Map ? capId['_id'] : capId) == userId;
    }, orElse: () => null);

    if (ledTeam == null) {
      _showAlert('Lỗi', 'Chỉ đội trưởng mới có quyền xóa kèo.');
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa kèo'),
        content: const Text(
          'Bạn có chắc chắn muốn xóa kèo đấu này không? Hành động này không thể hoàn tác.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _processing = true);
              try {
                final res = await http.delete(
                  Uri.parse('$API_BASE_URL/api/matches/${widget.matchId}'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({'userId': userId}),
                );
                if (res.statusCode == 200) {
                  if (!mounted) return;
                  _showAlert('Thành công', 'Đã xóa kèo đấu!');
                  context.pop();
                } else {
                  _showAlert('Lỗi', 'Không thể xóa kèo.');
                }
              } catch (e) {
                _showAlert('Lỗi', 'Lỗi kết nối.');
              } finally {
                if (mounted) setState(() => _processing = false);
              }
            },
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          )
        ],
      ),
    );
  }

  /// Hiển thị thông báo Dialog đơn giản
  void _showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          )
        ],
      ),
    );
  }

  // ===========================================================================
  // PHẦN 3: GIAO DIỆN CHÍNH (BUILD)
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    // Nếu đang tải dữ liệu ban đầu
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF1F5F9),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF22C55E)),
        ),
      );
    }

    // Nếu không tìm thấy thông tin trận đấu
    if (_match == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(
          backgroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.black),
        ),
        body: const Center(
          child: Text(
            'Không có thông tin kèo.',
            style: TextStyle(fontSize: 16, color: Color(0xFF64748B)),
          ),
        ),
      );
    }

    // Định dạng chuỗi ngày giờ
    final date = DateTime.tryParse(_match['playTime'] ?? '')?.toLocal() ?? DateTime.now();
    final timeStr =
        "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
    final dateStr =
        "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";

    // Phân quyền người dùng xem kèo
    final userId = context.read<AuthProvider>().userId;
    final isMyTeamCreator = _myTeams.any((t) => t['_id'] == _match['creatorTeamId']?['_id']);

    final isCaptainOfCreatorTeam = _myTeams.any((t) =>
        t['_id'] == _match['creatorTeamId']?['_id'] &&
        ((t['captainId'] is Map ? t['captainId']['_id'] : t['captainId']) == userId));

    final isCaptainOfMatchedTeam = _myTeams.any((t) =>
        t['_id'] == _match['matchedWithTeamId']?['_id'] &&
        ((t['captainId'] is Map ? t['captainId']['_id'] : t['captainId']) == userId));

    final isCaptainOfAnyTeam = _myTeams.any((t) =>
        (t['captainId'] is Map ? t['captainId']['_id'] : t['captainId']) == userId);

    final status = _match['status'];

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Thanh tiêu đề đầu trang
            _buildHeader(),

            // 2. Nội dung chi tiết cuộn được
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Thẻ đối đầu (Đội nhà VS Đội khách)
                    _buildVersusCard(status),

                    // Thẻ chi tiết thông tin trận đấu (ngày, giờ, sân, địa chỉ)
                    _buildMatchInfoCard(dateStr, timeStr),

                    // Nhóm các nút thao tác (Bắt kèo, Chờ đối thủ, Xóa kèo, Hủy kèo)
                    _buildActionButtons(
                      status: status,
                      isMyTeamCreator: isMyTeamCreator,
                      isCaptainOfCreatorTeam: isCaptainOfCreatorTeam,
                      isCaptainOfMatchedTeam: isCaptainOfMatchedTeam,
                      isCaptainOfAnyTeam: isCaptainOfAnyTeam,
                    ),
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

  /// Widget 1: Thanh tiêu đề đầu trang
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: const Icon(Icons.chevron_left, size: 32, color: Color(0xFF1F2937)),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Chi Tiết Kèo Đấu',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ),
          const SizedBox(width: 32),
        ],
      ),
    );
  }

  /// Widget 2: Thẻ hiển thị 2 đội đối đầu và trạng thái kèo
  Widget _buildVersusCard(String? status) {
    String statusVN = status ?? '';
    if (status == 'open') statusVN = 'ĐANG TÌM ĐỐI';
    if (status == 'matched') statusVN = 'ĐÃ CHỐT KÈO';
    if (status == 'finished') statusVN = 'ĐÃ KẾT THÚC';
    if (status == 'cancelled') statusVN = 'ĐÃ HỦY';

    final creatorLogo = _match['creatorTeamId']?['logo'];
    final matchedLogo = _match['matchedWithTeamId']?['logo'];
    final hasCreatorLogo = creatorLogo != null &&
        (creatorLogo.toString().startsWith('http') ||
            creatorLogo.toString().startsWith('data:image'));
    final hasMatchedLogo = matchedLogo != null &&
        (matchedLogo.toString().startsWith('http') ||
            matchedLogo.toString().startsWith('data:image'));

    return Container(
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          )
        ],
      ),
      child: Row(
        children: [
          // Đội Chủ Nhà
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFBBF7D0), width: 2),
                  ),
                  clipBehavior: Clip.hardEdge,
                  alignment: Alignment.center,
                  child: hasCreatorLogo
                      ? Image.network(creatorLogo, fit: BoxFit.cover)
                      : const Icon(Icons.security, size: 40, color: Color(0xFF22C55E)),
                ),
                Text(
                  _match['creatorTeamId']?['name'] ?? 'Đội chủ nhà',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),

          // Chữ VS và nhãn trạng thái ở giữa
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: [
                const Text(
                  'VS',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFCBD5E1),
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: status == 'open'
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusVN,
                    style: TextStyle(
                      color: status == 'open'
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFDC2626),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              ],
            ),
          ),

          // Đội Khách / Đang tìm
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: _match['matchedWithTeamId'] != null
                        ? const Color(0xFFF0FDF4)
                        : const Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _match['matchedWithTeamId'] != null
                          ? const Color(0xFFBBF7D0)
                          : const Color(0xFFE2E8F0),
                      width: 2,
                    ),
                  ),
                  clipBehavior: Clip.hardEdge,
                  alignment: Alignment.center,
                  child: hasMatchedLogo
                      ? Image.network(matchedLogo, fit: BoxFit.cover)
                      : Icon(
                          _match['matchedWithTeamId'] != null
                              ? Icons.security
                              : Icons.help_outline,
                          size: 40,
                          color: _match['matchedWithTeamId'] != null
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF94A3B8),
                        ),
                ),
                Text(
                  _match['matchedWithTeamId']?['name'] ?? 'Đang tìm...',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _match['matchedWithTeamId'] != null
                        ? const Color(0xFF1E293B)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Widget 3: Thẻ thông tin thời gian và địa điểm thi đấu
  Widget _buildMatchInfoCard(String dateStr, String timeStr) {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 5,
            offset: Offset(0, 1),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Thông tin trận đấu',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoRow(Icons.calendar_today, 'Ngày thi đấu', dateStr, const Color(0xFF3B82F6)),
          _buildInfoRow(Icons.access_time, 'Thời gian', timeStr, const Color(0xFFF59E0B)),
          _buildInfoRow(Icons.location_on, 'Khu vực', _match['location'] ?? "", const Color(0xFFEF4444)),
          _buildInfoRow(
            Icons.business,
            'Tên sân / Địa chỉ cụ thể',
            _match['fieldName'] ?? "",
            const Color(0xFF8B5CF6),
            noBorder: true,
          ),
        ],
      ),
    );
  }

  /// Widget 4: Từng dòng thông tin (Icon + Nhãn + Giá trị)
  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value,
    Color iconColor, {
    bool noBorder = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.only(bottom: noBorder ? 0 : 16),
      decoration: BoxDecoration(
        border: noBorder
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  /// Widget 5: Nhóm các nút thao tác tương ứng theo trạng thái và vai trò
  Widget _buildActionButtons({
    required String? status,
    required bool isMyTeamCreator,
    required bool isCaptainOfCreatorTeam,
    required bool isCaptainOfMatchedTeam,
    required bool isCaptainOfAnyTeam,
  }) {
    return Column(
      children: [
        // Trường hợp 1: Kèo đang mở & Không phải đội tạo & Người xem là Đội trưởng -> Bắt kèo
        if (status == 'open' && !isMyTeamCreator && isCaptainOfAnyTeam)
          ElevatedButton.icon(
            onPressed: _processing ? null : _handleMatch,
            icon: _processing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.flash_on, color: Colors.white),
            label: const Text(
              'Bắt Kèo Ngay',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 4,
            ),
          ),

        // Trường hợp 2: Kèo đang mở & Người xem thuộc đội tạo kèo -> Chờ đối thủ / Xóa kèo
        if (status == 'open' && isMyTeamCreator)
          Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Color(0xFF22C55E),
                        strokeWidth: 2,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Đang chờ đối thủ nhận kèo...',
                      style: TextStyle(
                        color: Color(0xFF166534),
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCaptainOfCreatorTeam)
                OutlinedButton(
                  onPressed: _processing ? null : _handleDeleteMatch,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFEE2E2), width: 2),
                    backgroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _processing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Color(0xFFEF4444),
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Xóa Kèo',
                          style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
            ],
          ),

        // Trường hợp 3: Kèo đã chốt & Người xem là Đội trưởng của một trong 2 đội -> Nút Hủy Kèo
        if (status == 'matched' && (isCaptainOfCreatorTeam || isCaptainOfMatchedTeam))
          OutlinedButton(
            onPressed: _processing ? null : _handleCancelMatch,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFFEE2E2), width: 2),
              backgroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _processing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Color(0xFFEF4444),
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Hủy Kèo',
                    style: TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
      ],
    );
  }
}
