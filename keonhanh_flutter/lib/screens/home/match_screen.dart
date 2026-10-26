import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../services/auth_provider.dart';
import '../../config/api.dart';

/// Màn hình: KÈO CỦA TÔI (MatchScreen)
/// Chức năng: Hiển thị danh sách các trận đấu (kèo bóng) của các đội mà người dùng tham gia.
/// Người dùng có thể chọn từng đội để xem các kèo đang tìm đối, đã chốt kèo, hoặc đã thi đấu xong.
class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key});

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  // ===========================================================================
  // PHẦN 1: CÁC BIẾN QUẢN LÝ DỮ LIỆU (STATE)
  // ===========================================================================

  // Danh sách các đội của tôi và các kèo đấu tương ứng của từng đội
  // Cấu trúc: [ {'team': {...}, 'matches': [...]}, ... ]
  List<dynamic> _matchesByTeam = [];

  // Trạng thái đang tải dữ liệu từ máy chủ
  bool _loading = true;

  // ID của đội bóng đang được người dùng bấm vào để xem chi tiết các kèo đấu
  // Nếu null -> hiển thị danh sách chọn đội bóng
  String? _selectedTeamId;

  @override
  void initState() {
    super.initState();
    // Khi màn hình khởi tạo, tự động gọi API lấy danh sách kèo
    _fetchMyMatches();
  }

  // ===========================================================================
  // PHẦN 2: CÁC HÀM XỬ LÝ (GỌI API VỀ MÁY CHỦ)
  // ===========================================================================

  /// Lấy danh sách hồ sơ cá nhân -> Lấy danh sách đội -> Lấy các kèo đấu của từng đội
  Future<void> _fetchMyMatches() async {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    if (mounted) setState(() => _loading = true);

    try {
      // Bước 1: Lấy thông tin User Profile để có profileId
      final profileRes = await http.get(Uri.parse('$API_BASE_URL/api/user-profiles/$userId'));
      if (profileRes.statusCode != 200) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final profileData = jsonDecode(profileRes.body);
      final profileId = profileData['profile']['_id'];

      // Bước 2: Lấy các đội mà cầu thủ này đang tham gia
      final teamRes = await http.get(Uri.parse('$API_BASE_URL/api/teams/my-team/$profileId'));
      if (teamRes.statusCode != 200) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final teamData = jsonDecode(teamRes.body);
      final teams = teamData['data'] ?? [];

      // Bước 3: Với mỗi đội, lấy danh sách các trận đấu tương ứng
      List<dynamic> allTeamMatches = [];
      for (var t in teams) {
        final matchesRes = await http.get(Uri.parse('$API_BASE_URL/api/matches/my-matches/${t['_id']}'));
        if (matchesRes.statusCode == 200) {
          final matchesData = jsonDecode(matchesRes.body);
          allTeamMatches.add({
            'team': t,
            'matches': matchesData['data'] ?? [],
          });
        } else {
          allTeamMatches.add({'team': t, 'matches': []});
        }
      }

      // Cập nhật State để vẽ lại giao diện
      if (mounted) {
        setState(() {
          _matchesByTeam = allTeamMatches;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải danh sách kèo của tôi: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  // ===========================================================================
  // PHẦN 3: GIAO DIỆN CHÍNH (BUILD)
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    // Nếu đang tải dữ liệu, hiển thị vòng xoay chờ
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4FDF4),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF22C55E)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4FDF4),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Thanh tiêu đề phía trên
            _buildHeader(),

            // 2. Nội dung chính: Có thể kéo vuốt xuống để tải lại (RefreshIndicator)
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchMyMatches,
                color: const Color(0xFF22C55E),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
                  children: [
                    // Trường hợp 1: Người dùng chưa gia nhập đội nào
                    if (_matchesByTeam.isEmpty)
                      _buildNoTeamView()

                    // Trường hợp 2: Có đội nhưng chưa chọn đội cụ thể nào
                    else if (_selectedTeamId == null)
                      _buildTeamSelectionList()

                    // Trường hợp 3: Đã chọn một đội -> hiển thị các kèo của đội đó
                    else
                      _buildSelectedTeamMatchesView(),
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
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
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
      child: const Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LỊCH THI ĐẤU 🏟️',
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFFDCFCE7),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Kèo Của Tôi',
                style: TextStyle(
                  fontSize: 28,
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

  /// Widget 2: Giao diện khi người dùng chưa có bất kỳ đội bóng nào
  Widget _buildNoTeamView() {
    return Container(
      margin: const EdgeInsets.only(top: 60),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFBBF7D0), width: 2),
            ),
            child: const Icon(Icons.security, size: 54, color: Color(0xFF86EFAC)),
          ),
          const SizedBox(height: 20),
          const Text(
            'Chưa có đội bóng',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF14532D),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Bạn cần gia nhập hoặc tạo một đội bóng để quản lý kèo đấu.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF166534),
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: () => context.push('/createTeam'),
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text(
              'Tạo đội ngay',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
            ),
          ),
        ],
      ),
    );
  }

  /// Widget 3: Danh sách các đội để người dùng chọn xem kèo
  Widget _buildTeamSelectionList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 16),
          child: Text(
            'Chọn đội để xem kèo đấu',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF14532D),
            ),
          ),
        ),
        ..._matchesByTeam.map((group) {
          final team = group['team'];
          final matches = group['matches'] as List<dynamic>;
          final hasLogo = team['logo'] != null &&
              (team['logo'].toString().startsWith('http') ||
                  team['logo'].toString().startsWith('data:image'));

          return GestureDetector(
            onTap: () => setState(() => _selectedTeamId = team['_id']),
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFDCFCE7)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A16A34A),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  )
                ],
              ),
              clipBehavior: Clip.hardEdge,
              child: Container(
                padding: const EdgeInsets.all(16),
                color: const Color(0xFFF0FDF4),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: const BoxDecoration(
                        color: Color(0xFF14532D),
                        shape: BoxShape.circle,
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: hasLogo
                          ? Image.network(team['logo'], fit: BoxFit.cover)
                          : const Icon(Icons.security, size: 18, color: Colors.white),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            team['name'] ?? '',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF14532D),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${matches.length} kèo đấu',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF166534),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 24,
                      color: Color(0xFF16A34A),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  /// Widget 4: Hiển thị các kèo đấu của đội đã được chọn
  Widget _buildSelectedTeamMatchesView() {
    final group = _matchesByTeam.firstWhere(
      (t) => t['team']['_id'] == _selectedTeamId,
      orElse: () => {'team': {}, 'matches': []},
    );
    final team = group['team'];
    final matches = group['matches'] as List<dynamic>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Nút quay lại danh sách đội bóng
        GestureDetector(
          onTap: () => setState(() => _selectedTeamId = null),
          child: Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back, size: 20, color: Color(0xFF475569)),
                SizedBox(width: 6),
                Text(
                  'Danh sách đội',
                  style: TextStyle(
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Tiêu đề tên đội đang xem
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 16),
          child: Text(
            'Kèo của đội: ${team['name'] ?? ''}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF14532D),
            ),
          ),
        ),

        // Nếu đội chưa có kèo đấu nào
        if (matches.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDCFCE7)),
            ),
            child: Column(
              children: [
                const Text(
                  'Đội này chưa có kèo nào.',
                  style: TextStyle(
                    color: Color(0xFF16A34A),
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: () => context.push('/createMatch'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Tạo kèo ngay',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              ],
            ),
          )
        // Nếu có danh sách kèo đấu
        else
          ...matches.map((item) => _buildMatchCard(item, team)),
      ],
    );
  }

  /// Widget 5: Thẻ hiển thị một kèo đấu cụ thể
  Widget _buildMatchCard(dynamic item, dynamic currentTeam) {
    final date = DateTime.tryParse(item['playTime'] ?? '')?.toLocal() ?? DateTime.now();
    final timeStr =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} - ${date.day}/${date.month}/${date.year}';
    final isCreator = item['creatorTeamId']?['_id'] == currentTeam['_id'];
    final status = item['status'];

    // Chuyển đổi mã trạng thái sang tiếng Việt dễ hiểu
    String statusVN = status ?? '';
    if (status == 'open') statusVN = 'ĐANG TÌM ĐỐI';
    if (status == 'matched') statusVN = 'ĐÃ CHỐT KÈO';
    if (status == 'finished') statusVN = 'ĐÃ KẾT THÚC';
    if (status == 'cancelled') statusVN = 'ĐÃ HỦY';

    return GestureDetector(
      onTap: () => context.push('/matchDetail', extra: {'matchId': item['_id'] ?? item['id']}),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFDCFCE7)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A16A34A),
              blurRadius: 12,
              offset: Offset(0, 4),
            )
          ],
        ),
        child: Column(
          children: [
            // Dòng trên: Tên đội tạo kèo & Nhãn trạng thái
            Row(
              children: [
                Expanded(
                  child: Text(
                    item['creatorTeamId']?['name'] ?? 'Đội ẩn danh',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF14532D),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: status == 'matched'
                        ? const Color(0xFFFEE2E2)
                        : const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusVN,
                    style: TextStyle(
                      color: status == 'matched'
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF16A34A),
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                      letterSpacing: 0.5,
                    ),
                  ),
                )
              ],
            ),

            // Nếu đã chốt kèo -> hiển thị thông tin Đội nhận kèo (VS)
            if (status == 'matched' && item['matchedWithTeamId'] != null)
              Container(
                margin: const EdgeInsets.only(top: 16, bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: const Border(
                    left: BorderSide(color: Color(0xFFEF4444), width: 4),
                  ),
                ),
                child: Row(
                  children: [
                    const Text(
                      'VS',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFEF4444),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item['matchedWithTeamId']['name'] ?? '',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF14532D),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )
            else
              const SizedBox(height: 16),

            // Thông tin địa điểm & thời gian
            _buildDetailRow(Icons.location_on, item['fieldName'] ?? "", const Color(0xFF3B82F6)),
            _buildDetailRow(Icons.access_time_filled, timeStr, const Color(0xFFF59E0B)),

            // Dòng dưới cùng: Vai trò đội chủ nhà hay đội khách
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.only(top: 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFF0FDF4))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  RichText(
                    text: TextSpan(
                      text: 'Vai trò: ',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF166534),
                        fontWeight: FontWeight.w600,
                      ),
                      children: [
                        TextSpan(
                          text: isCreator ? 'Đội chủ nhà' : 'Đội khách',
                          style: const TextStyle(
                            color: Color(0xFF14532D),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18, color: Color(0xFFCBD5E1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Widget trợ giúp: Một dòng chi tiết có icon và chữ
  Widget _buildDetailRow(IconData icon, String text, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            margin: const EdgeInsets.only(right: 10),
            child: Icon(icon, size: 14, color: iconColor),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF166534),
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
