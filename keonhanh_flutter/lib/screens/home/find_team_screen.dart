import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../services/auth_provider.dart';
import '../../config/api.dart';

/// Màn hình "Tìm Đội Bóng" (Xem danh sách các đội đang tuyển và gửi yêu cầu xin vào đội)
class FindTeamScreen extends StatefulWidget {
  const FindTeamScreen({super.key});

  @override
  State<FindTeamScreen> createState() => _FindTeamScreenState();
}

class _FindTeamScreenState extends State<FindTeamScreen> {
  // ===========================================================================
  // PHẦN 1: CÁC BIẾN QUẢN LÝ DỮ LIỆU (STATE)
  // ===========================================================================

  List<dynamic> _teams = []; // Danh sách tất cả đội bóng trên hệ thống
  bool _loading = true; // Trạng thái đang tải dữ liệu
  String? _myProfileId; // ID hồ sơ của người dùng hiện tại
  List<String> _myTeamIds = []; // Danh sách các ID đội bóng mà người dùng đã là thành viên
  Map<String, String> _requestStatus = {}; // Trạng thái xin vào từng đội: 'none', 'sending', 'pending'

  // ===========================================================================
  // PHẦN 2: CÁC HÀM XỬ LÝ (GỌI API VỀ MÁY CHỦ)
  // ===========================================================================

  @override
  void initState() {
    super.initState();
    _fetchData(); // Tải danh sách đội khi vừa mở màn hình
  }

  /// Tải dữ liệu hồ sơ cá nhân, đội đã tham gia và danh sách tất cả các đội
  Future<void> _fetchData() async {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      // 1. Lấy hồ sơ cá nhân (UserProfile)
      final profileRes = await http.get(Uri.parse('$API_BASE_URL/api/user-profiles/$userId'));
      String? profileId;
      if (profileRes.statusCode == 200) {
        final profileData = jsonDecode(profileRes.body);
        if (profileData['profile'] != null) {
          profileId = profileData['profile']['_id']?.toString();
          if (mounted) setState(() => _myProfileId = profileId);
        }
      }

      // 2. Lấy các đội mình đã tham gia & các yêu cầu xin vào đội đã gửi
      if (profileId != null) {
        // Lấy các đội mình đã ở trong đó
        final myTeamRes = await http.get(Uri.parse('$API_BASE_URL/api/teams/my-team/$profileId'));
        if (myTeamRes.statusCode == 200) {
          final myTeamData = jsonDecode(myTeamRes.body);
          if (myTeamData['success'] == true && myTeamData['data'] is List) {
            final ids = (myTeamData['data'] as List).map((t) => t['_id'].toString()).toList();
            if (mounted) setState(() => _myTeamIds = ids);
          }
        }

        // Lấy các yêu cầu mình đã gửi đi để hiện chữ "Đang chờ duyệt"
        final reqRes = await http.get(Uri.parse('$API_BASE_URL/api/join-requests/player/$profileId'));
        if (reqRes.statusCode == 200) {
          final reqData = jsonDecode(reqRes.body);
          if (reqData['success'] == true && reqData['data'] is List) {
            final Map<String, String> reqMap = {};
            for (var req in reqData['data']) {
              final tId = req['teamId'] is Map ? req['teamId']['_id'] : req['teamId'];
              if (tId != null) reqMap[tId.toString()] = 'pending';
            }
            if (mounted) setState(() => _requestStatus = reqMap);
          }
        }
      }

      // 3. Tải danh sách tất cả các đội bóng để hiển thị
      final teamsRes = await http.get(Uri.parse('$API_BASE_URL/api/teams'));
      if (teamsRes.statusCode == 200) {
        final teamsData = jsonDecode(teamsRes.body);
        if (teamsData['success'] == true) {
          if (mounted) setState(() => _teams = teamsData['data'] ?? []);
        }
      }
    } catch (e) {
      debugPrint("Lỗi tải danh sách tìm đội: $e");
      if (mounted) {
        _showAlertDialog('Lỗi', 'Không thể kết nối tới máy chủ. Vui lòng thử lại!');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Gửi yêu cầu xin gia nhập một đội bóng
  Future<void> _handleJoinRequest(dynamic team) async {
    final teamId = team['_id']?.toString();
    if (teamId == null) return;

    if (_myProfileId == null) {
      _showAlertDialog('Chưa có hồ sơ', 'Bạn cần tạo hồ sơ cá nhân trước khi xin vào đội.');
      return;
    }

    if (_myTeamIds.contains(teamId)) {
      _showAlertDialog('Đã ở trong đội', 'Bạn đã là thành viên của đội bóng này rồi.');
      return;
    }

    setState(() => _requestStatus[teamId] = 'sending');

    try {
      final res = await http.post(
        Uri.parse('$API_BASE_URL/api/join-requests'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'requesterId': _myProfileId,
          'teamId': teamId,
        }),
      );

      final data = jsonDecode(res.body);
      if (!mounted) return;

      if (res.statusCode == 200 && data['success'] == true) {
        setState(() => _requestStatus[teamId] = 'pending');
        _showAlertDialog('✅ Đã gửi yêu cầu', data['message'] ?? 'Yêu cầu của bạn đã được gửi tới Đội trưởng.');
      } else {
        setState(() => _requestStatus[teamId] = 'none');
        _showAlertDialog('Không thể gửi', data['message'] ?? 'Có lỗi xảy ra.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _requestStatus[teamId] = 'none');
        _showAlertDialog('Lỗi', 'Không thể kết nối tới máy chủ.');
      }
    }
  }

  /// Hộp thoại thông báo tiện ích
  void _showAlertDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PHẦN 3: GIAO DIỆN CHÍNH (BUILD)
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthProvider>().userId;

    // 1. Nếu chưa đăng nhập: Yêu cầu đăng nhập trước
    if (userId == null) {
      return _buildNotLoggedInView();
    }

    // 2. Màn hình chính khi đã đăng nhập
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // Thanh tiêu đề trên cùng
            _buildAppBar(),

            // Danh sách các đội bóng
            Expanded(
              child: _loading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Color(0xFF22C55E)),
                          SizedBox(height: 12),
                          Text('Đang tải danh sách đội...', style: TextStyle(fontSize: 14, color: Color(0xFF64748B))),
                        ],
                      ),
                    )
                  : _teams.isEmpty
                      ? const Center(
                          child: Text('Chưa có đội bóng nào trên hệ thống.', style: TextStyle(color: Color(0xFF64748B))),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchData,
                          color: const Color(0xFF22C55E),
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _teams.length,
                            itemBuilder: (ctx, i) => _buildTeamCard(_teams[i], userId),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // PHẦN 4: CÁC WIDGET CON (TÁCH NHỎ CODE ĐỂ ĐƠN GIẢN VÀ DỄ HIỂU)
  // ===========================================================================

  /// Thanh tiêu đề AppBar
  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(color: Color(0xFFDCFCE7), shape: BoxShape.circle),
              child: const Icon(Icons.arrow_back, color: Color(0xFF16A34A), size: 20),
            ),
          ),
          const Expanded(
            child: Center(
              child: Text('Tìm Đội Bóng', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
            ),
          ),
          const SizedBox(width: 38), // Cân đối layout hai bên
        ],
      ),
    );
  }

  /// Giao diện khi chưa đăng nhập
  Widget _buildNotLoggedInView() {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_outline, size: 68, color: Color(0xFF94A3B8)),
                      const SizedBox(height: 16),
                      const Text('Yêu cầu đăng nhập', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      const SizedBox(height: 8),
                      const Text(
                        'Bạn cần đăng nhập tài khoản để có thể tìm kiếm và xin gia nhập đội bóng.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Color(0xFF64748B), height: 1.4),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => context.push('/login'),
                        icon: const Icon(Icons.login, color: Colors.white, size: 18),
                        label: const Text('Đăng nhập ngay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Thẻ thông tin một đội bóng trong danh sách
  Widget _buildTeamCard(dynamic item, String userId) {
    final teamId = item['_id']?.toString() ?? '';
    final capId = item['captainId'] is Map ? item['captainId']['_id'] : item['captainId'];
    final isMyCaptain = capId == userId;
    final isMember = _myTeamIds.contains(teamId);
    final status = _requestStatus[teamId] ?? 'none';

    final cap = item['captainId'];
    final captainName = cap is Map ? (cap['username'] ?? cap['fullName'] ?? 'Ẩn danh') : (item['captainName'] ?? 'Ẩn danh');
    final skillLevel = item['skillLevel'] ?? item['level'] ?? 'Sơ cấp';
    final memberCount = item['players'] is List ? (item['players'] as List).length : 0;
    final hasLogo = item['logo'] != null && item['logo'].toString().startsWith('http');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        children: [
          // Phần đầu thẻ: Logo, Tên, Trình độ
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                margin: const EdgeInsets.only(right: 14),
                decoration: const BoxDecoration(color: Color(0xFFDCFCE7), shape: BoxShape.circle),
                clipBehavior: Clip.hardEdge,
                alignment: Alignment.center,
                child: hasLogo
                    ? Image.network(item['logo'], fit: BoxFit.cover)
                    : const Icon(Icons.security, size: 30, color: Color(0xFF16A34A)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['name'] ?? 'Chưa đặt tên', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(6)),
                          child: Text(skillLevel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: item['isRecruiting'] == true ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item['isRecruiting'] == true ? 'Đang tuyển' : 'Đủ người',
                            style: TextStyle(
                              color: item['isRecruiting'] == true ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Phần giữa thẻ: Địa điểm, số lượng thành viên, tên đội trưởng
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                _buildInfoLine(Icons.location_on_outlined, item['location'] ?? 'Chưa rõ địa điểm'),
                const SizedBox(height: 6),
                _buildInfoLine(Icons.people_outline, '$memberCount/14 thành viên'),
                const SizedBox(height: 6),
                _buildInfoLine(Icons.person_outline, 'Đội trưởng: $captainName'),
              ],
            ),
          ),

          // Phần nút bấm hành động (Tùy theo vai trò của người dùng đối với đội này)
          _buildActionButton(
            isMember: isMember,
            isMyCaptain: isMyCaptain,
            status: status,
            onJoinTap: () => _handleJoinRequest(item),
          ),
        ],
      ),
    );
  }

  /// Dòng thông tin phụ (icon + chữ)
  Widget _buildInfoLine(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF475569)), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  /// Nút bấm tương ứng với trạng thái (Đã là thành viên, Đội trưởng, Đang chờ duyệt, hoặc Nút Xin vào đội)
  Widget _buildActionButton({
    required bool isMember,
    required bool isMyCaptain,
    required String status,
    required VoidCallback onJoinTap,
  }) {
    if (isMember) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(12)),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 16, color: Color(0xFF16A34A)),
            SizedBox(width: 6),
            Text('Đội của bạn', style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      );
    }

    if (isMyCaptain) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(12)),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield, size: 16, color: Color(0xFFD97706)),
            SizedBox(width: 6),
            Text('Bạn là đội trưởng', style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      );
    }

    if (status == 'sending') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Color(0xFF64748B), strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Đang gửi yêu cầu...', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      );
    }

    if (status == 'pending') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time, size: 16, color: Color(0xFF64748B)),
            SizedBox(width: 6),
            Text('Đang chờ duyệt', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      );
    }

    // Mặc định: Nút bấm xin vào đội
    return ElevatedButton.icon(
      onPressed: onJoinTap,
      icon: const Icon(Icons.login, size: 16, color: Colors.white),
      label: const Text('Xin vào đội', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF16A34A),
        minimumSize: const Size.fromHeight(42),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 1,
      ),
    );
  }
}
