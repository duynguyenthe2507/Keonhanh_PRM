import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../services/auth_provider.dart';
import '../../config/api.dart';

/// Màn hình "Đội của tôi" (Quản lý đội bóng, lời mời, thành viên và yêu cầu gia nhập)
class MyTeamScreen extends StatefulWidget {
  const MyTeamScreen({super.key});

  @override
  State<MyTeamScreen> createState() => _MyTeamScreenState();
}

class _MyTeamScreenState extends State<MyTeamScreen> {
  // ===========================================================================
  // PHẦN 1: CÁC BIẾN QUẢN LÝ DỮ LIỆU (STATE)
  // ===========================================================================

  bool _loading = true; // Đang tải dữ liệu ban đầu
  String? _myProfileId; // ID hồ sơ cá nhân của người dùng

  // Dữ liệu đội bóng
  List<dynamic> _teams = []; // Danh sách các đội bóng mà người dùng đã tham gia
  String? _selectedTeamId; // ID đội bóng đang bấm vào xem chi tiết (nếu có)

  // Getter lấy nhanh thông tin của đội đang xem chi tiết
  dynamic get _selectedTeam => _selectedTeamId != null
      ? _teams.firstWhere((t) => t['_id'] == _selectedTeamId, orElse: () => null)
      : null;

  // Lời mời và yêu cầu
  List<dynamic> _invitations = []; // Các lời mời từ đội khác gửi đến cho mình
  List<dynamic> _sentRequests = []; // Các yêu cầu xin vào đội mà mình đã gửi đi
  List<dynamic> _joinRequests = []; // Các yêu cầu của người khác xin vào đội (dành cho Đội trưởng)

  // Trạng thái xử lý thao tác (để hiển thị vòng quay loading ở nút bấm tương ứng)
  String? _processingId;
  String? _processingAction; // 'approve' hoặc 'reject'
  String? _kickingId; // ID thành viên đang bấm kick
  bool _togglingRecruiting = false; // Đang bấm nút bật/tắt tuyển quân

  // ===========================================================================
  // PHẦN 2: KHỞI TẠO VÀ CÁC HÀM GỌI API
  // ===========================================================================

  @override
  void initState() {
    super.initState();
    _fetchData(); // Tải dữ liệu khi vừa mở màn hình
  }

  /// Tải toàn bộ dữ liệu: Đội bóng của tôi + Lời mời tham gia
  Future<void> _fetchData() async {
    setState(() => _loading = true);
    await _fetchMyTeam();
    await _fetchInvitations();
    if (mounted) setState(() => _loading = false);
  }

  /// Kéo màn hình để làm mới (Pull-to-refresh)
  Future<void> _handleRefresh() async {
    await _fetchMyTeam();
    await _fetchInvitations();
  }

  /// 1. Tải danh sách đội bóng của tôi từ máy chủ
  Future<void> _fetchMyTeam() async {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) return;

    try {
      // Lấy ID hồ sơ cá nhân (UserProfileId) từ UserId đăng nhập
      final profileRes = await http.get(Uri.parse('$API_BASE_URL/api/user-profiles/$userId'));
      if (profileRes.statusCode != 200) {
        _showAlert('Chưa có hồ sơ', 'Bạn cần tạo hồ sơ cá nhân trước khi quản lý đội bóng.', true);
        return;
      }

      final profileData = jsonDecode(profileRes.body);
      if (profileData['profile'] == null) {
        _showAlert('Chưa có hồ sơ', 'Bạn cần tạo hồ sơ cá nhân trước khi quản lý đội bóng.', true);
        return;
      }

      final profileId = profileData['profile']['_id'];
      _myProfileId = profileId;

      // Lấy danh sách đội bóng mà profile này tham gia
      final res = await http.get(Uri.parse('$API_BASE_URL/api/teams/my-team/$profileId'));
      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && data['success']) {
        setState(() => _teams = data['data'] ?? []);

        // Kiểm tra xem mình có làm đội trưởng của đội nào không
        final bool isCaptainOfAny = _teams.any((t) {
          final capId = t['captainId'];
          if (capId is Map) return capId['_id'] == userId;
          return capId == userId;
        });

        // Nếu là đội trưởng, tải thêm danh sách các yêu cầu xin vào đội
        if (isCaptainOfAny) {
          await _fetchCaptainJoinRequests(userId);
        }
      } else {
        setState(() => _teams = []);
        // Nếu chưa có đội, tải các yêu cầu mà mình đã gửi đi để người dùng theo dõi
        await _fetchSentJoinRequests(profileId);
      }
    } catch (e) {
      _showAlert("Lỗi", e.toString().replaceAll("Exception: ", ""));
    }
  }

  /// 2. Lấy danh sách yêu cầu xin vào đội gửi tới Đội trưởng
  Future<void> _fetchCaptainJoinRequests(String userId) async {
    try {
      final res = await http.get(Uri.parse('$API_BASE_URL/api/join-requests/captain/$userId'));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success']) {
        setState(() => _joinRequests = data['data'] ?? []);
      } else {
        setState(() => _joinRequests = []);
      }
    } catch (e) {
      debugPrint("Lỗi tải yêu cầu xin vào đội: $e");
    }
  }

  /// 3. Lấy danh sách yêu cầu mà chính mình đã gửi xin vào các đội khác
  Future<void> _fetchSentJoinRequests(String profileId) async {
    try {
      final res = await http.get(Uri.parse('$API_BASE_URL/api/join-requests/player/$profileId'));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success']) {
        setState(() => _sentRequests = data['data'] ?? []);
      } else {
        setState(() => _sentRequests = []);
      }
    } catch (e) {
      debugPrint("Lỗi tải yêu cầu đã gửi: $e");
    }
  }

  /// 4. Lấy danh sách lời mời gia nhập đội gửi tới tài khoản của tôi
  Future<void> _fetchInvitations() async {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) return;
    try {
      final res = await http.get(Uri.parse('$API_BASE_URL/api/invitations/user/$userId'));
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() => _invitations = data['data'] ?? []);
      }
    } catch (e) {
      debugPrint("Lỗi tải lời mời tham gia: $e");
    }
  }

  /// 5. Chấp nhận lời mời gia nhập đội bóng
  Future<void> _handleAcceptInvitation(String id) async {
    setState(() {
      _processingId = id;
      _processingAction = 'approve';
    });
    try {
      final res = await http.patch(Uri.parse('$API_BASE_URL/api/invitations/$id/accept'));
      final data = jsonDecode(res.body);
      if (data['success'] != true) {
        _showAlert("Lỗi", data['message'] ?? "Có lỗi xảy ra");
        return;
      }
      _showAlert("Thành công", "Bạn đã tham gia vào đội bóng!");
      await _fetchInvitations();
      await _fetchMyTeam();
    } catch (e) {
      _showAlert("Lỗi", "Không thể kết nối tới máy chủ");
    } finally {
      if (mounted) {
        setState(() {
          _processingId = null;
          _processingAction = null;
        });
      }
    }
  }

  /// 6. Từ chối lời mời gia nhập đội bóng
  Future<void> _handleRejectInvitation(String id) async {
    setState(() {
      _processingId = id;
      _processingAction = 'reject';
    });
    try {
      final res = await http.patch(Uri.parse('$API_BASE_URL/api/invitations/$id/reject'));
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        await _fetchInvitations();
      } else {
        _showAlert("Lỗi", data['message'] ?? "Có lỗi xảy ra");
      }
    } catch (e) {
      _showAlert("Lỗi", "Không thể kết nối tới máy chủ");
    } finally {
      if (mounted) {
        setState(() {
          _processingId = null;
          _processingAction = null;
        });
      }
    }
  }

  /// 7. Đội trưởng phê duyệt người xin gia nhập đội
  Future<void> _handleApproveRequest(String requestId) async {
    setState(() {
      _processingId = requestId;
      _processingAction = 'approve';
    });
    try {
      final res = await http.patch(Uri.parse('$API_BASE_URL/api/join-requests/$requestId/approve'));
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (res.statusCode == 200 && data['success']) {
        _showAlert('✅ Đã phê duyệt', data['message'] ?? 'Thành viên đã được thêm vào đội.');
        await _fetchMyTeam();
      } else {
        _showAlert('Lỗi', data['message'] ?? 'Không thể phê duyệt');
      }
    } catch (e) {
      if (mounted) _showAlert('Lỗi', 'Không thể kết nối tới máy chủ.');
    } finally {
      if (mounted) {
        setState(() {
          _processingId = null;
          _processingAction = null;
        });
      }
    }
  }

  /// 8. Đội trưởng từ chối người xin gia nhập đội
  Future<void> _handleRejectRequest(String requestId) async {
    setState(() {
      _processingId = requestId;
      _processingAction = 'reject';
    });
    try {
      final res = await http.patch(Uri.parse('$API_BASE_URL/api/join-requests/$requestId/reject'));
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (res.statusCode == 200 && data['success']) {
        setState(() => _joinRequests.removeWhere((r) => r['_id'] == requestId));
        _showAlert('Đã từ chối', data['message'] ?? 'Đã từ chối yêu cầu.');
      } else {
        _showAlert('Lỗi', data['message'] ?? 'Không thể từ chối');
      }
    } catch (e) {
      if (mounted) _showAlert('Lỗi', 'Không thể kết nối tới máy chủ.');
    } finally {
      if (mounted) {
        setState(() {
          _processingId = null;
          _processingAction = null;
        });
      }
    }
  }

  /// 9. Đội trưởng đóng hoặc mở tuyển thành viên
  Future<void> _handleToggleRecruiting() async {
    if (_selectedTeam == null) return;
    final bool isRecruiting = _selectedTeam['isRecruiting'] ?? true;
    final userId = context.read<AuthProvider>().userId;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isRecruiting ? '🔒 Dừng tuyển quân?' : '🟢 Mở tuyển lại?'),
        content: Text(isRecruiting
            ? 'Khi dừng tuyển, người khác sẽ không thể gửi yêu cầu gia nhập đội nữa. Bạn có thể mở lại bất cứ lúc nào.'
            : 'Mở tuyển quân sẽ cho phép các cầu thủ tự do gửi yêu cầu tham gia đội bóng.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _togglingRecruiting = true);
              try {
                final res = await http.patch(
                  Uri.parse('$API_BASE_URL/api/teams/${_selectedTeam['_id']}/toggle-recruiting'),
                  headers: {"Content-Type": "application/json"},
                  body: jsonEncode({"captainUserId": userId}),
                );
                final data = jsonDecode(res.body);
                if (res.statusCode == 200 && data['success']) {
                  _showAlert(data['isRecruiting'] ? '✅ Đã mở tuyển' : '🔒 Đã dừng tuyển', data['message']);
                  await _fetchMyTeam();
                } else {
                  _showAlert('Lỗi', data['message']);
                }
              } catch (e) {
                _showAlert('Lỗi', 'Không thể kết nối tới máy chủ.');
              } finally {
                if (mounted) setState(() => _togglingRecruiting = false);
              }
            },
            child: Text(isRecruiting ? 'Dừng tuyển' : 'Mở tuyển',
                style: TextStyle(color: isRecruiting ? Colors.red : Colors.green)),
          ),
        ],
      ),
    );
  }

  /// 10. Đội trưởng xóa/kick một thành viên khỏi đội
  void _handleKick(String playerId, String playerName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận kick'),
        content: Text('Bạn có chắc muốn xóa cầu thủ "$playerName" khỏi đội bóng không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _kickingId = playerId);
              try {
                final res = await http.patch(
                  Uri.parse('$API_BASE_URL/api/teams/${_selectedTeam['_id']}/kick/$playerId'),
                );
                final data = jsonDecode(res.body);
                if (res.statusCode == 200 && data['success']) {
                  _showAlert('✅ Đã xóa thành viên', data['message']);
                  await _fetchMyTeam();
                } else {
                  _showAlert('Lỗi', data['message']);
                }
              } catch (e) {
                _showAlert('Lỗi', 'Không thể kết nối tới máy chủ.');
              } finally {
                if (mounted) setState(() => _kickingId = null);
              }
            },
            child: const Text('Xóa khỏi đội', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Hộp thoại thông báo tiện ích
  void _showAlert(String title, String message, [bool profileMissing = false]) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          if (profileMissing)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/profile');
              },
              child: const Text('Tạo hồ sơ ngay', style: TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.bold)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(profileMissing ? 'Để sau' : 'OK', style: const TextStyle(color: Color(0xFF64748B))),
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
    // 1. Nếu đang tải dữ liệu thì hiện vòng xoay
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4FDF4),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF22C55E))),
      );
    }

    final userId = context.read<AuthProvider>().userId;

    // 2. Kiểm tra xem người dùng hiện tại có phải là Đội trưởng của đội đang xem hay không
    bool isCaptain = false;
    if (_selectedTeam != null && userId != null) {
      final cap = _selectedTeam['captainId'];
      isCaptain = (cap is Map ? cap['_id'] : cap) == userId;
    }

    // 3. Lọc danh sách yêu cầu xin vào đội dành riêng cho đội đang được chọn
    final currentJoinRequests = _joinRequests.where((req) {
      final tid = req['teamId'];
      return (tid is Map ? tid['_id'] : tid) == _selectedTeam?['_id'];
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4FDF4),
      body: SafeArea(
        child: Column(
          children: [
            // Header xanh lá cây trên cùng
            _buildHeader(isCaptain: isCaptain, requestCount: currentJoinRequests.length),

            // Nội dung chính
            Expanded(
              child: RefreshIndicator(
                onRefresh: _handleRefresh,
                color: const Color(0xFF22C55E),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                  children: [
                    // TRƯỜNG HỢP A: Chưa bấm chọn xem chi tiết đội nào -> Hiện tổng quan danh sách
                    if (_selectedTeam == null) ...[
                      _buildOverviewView(),
                    ]
                    // TRƯỜNG HỢP B: Đã bấm chọn một đội cụ thể -> Hiện chi tiết & quản lý đội đó
                    else ...[
                      _buildTeamDetailView(isCaptain: isCaptain, joinRequests: currentJoinRequests),
                    ],
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
  // PHẦN 4: CÁC WIDGET CON (CHIA NHỎ ĐỂ CODE NGẮN GỌN & DỄ HIỂU)
  // ===========================================================================

  /// Header trên cùng màu xanh lá
  Widget _buildHeader({required bool isCaptain, required int requestCount}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      decoration: const BoxDecoration(
        color: Color(0xFF16A34A),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
        boxShadow: [BoxShadow(color: Color(0x4D14532D), offset: Offset(0, 6), blurRadius: 10)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (context.canPop())
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.arrow_back, color: Color(0xFF16A34A), size: 20),
                  ),
                ),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('QUẢN LÝ 🛡️', style: TextStyle(fontSize: 13, color: Color(0xFFDCFCE7), fontWeight: FontWeight.w600, letterSpacing: 1)),
                  SizedBox(height: 2),
                  Text('Đội Của Tôi', style: TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.w900)),
                ],
              ),
            ],
          ),
          // Chuông thông báo nếu có người xin vào đội (dành cho đội trưởng)
          if (isCaptain && requestCount > 0)
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: Colors.white.withAlpha(51), shape: BoxShape.circle),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.notifications, color: Colors.white, size: 24),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: const Color(0xFF16A34A), width: 1.5),
                      ),
                      child: Text('$requestCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
            )
          else
            const SizedBox(width: 40),
        ],
      ),
    );
  }

  /// GIAO DIỆN TỔNG QUAN: Danh sách lời mời, yêu cầu đã gửi và các đội bóng đã tham gia
  Widget _buildOverviewView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Danh sách lời mời gia nhập đội từ người khác gửi đến
        if (_invitations.isNotEmpty) ...[
          _buildInvitationsSection(),
          const SizedBox(height: 20),
        ],

        // 2. Danh sách yêu cầu mà chính mình đã gửi đi xin vào đội
        if (_sentRequests.isNotEmpty) ...[
          _buildSentRequestsSection(),
          const SizedBox(height: 20),
        ],

        // 3. Danh sách các đội bóng mình đang tham gia
        if (_teams.isNotEmpty) ...[
          _buildMyTeamsListSection(),
        ]
        // 4. Nếu chưa tham gia đội nào thì hiện màn hình hướng dẫn tạo đội
        else ...[
          _buildEmptyTeamsState(),
        ],
      ],
    );
  }

  /// Khối hiển thị Lời mời gia nhập đội bóng
  Widget _buildInvitationsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Lời mời tham gia đội (${_invitations.length})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF14532D))),
        const SizedBox(height: 10),
        ..._invitations.map((inv) {
          final isProcessing = _processingId == inv['_id'];
          final team = inv['teamId'] ?? {};
          final capName = inv['captainId']?['username'] ?? 'Đội trưởng';

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDCFCE7)),
              boxShadow: const [BoxShadow(color: Color(0x0D16A34A), blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(team['name'] ?? 'Đội bóng', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF14532D))),
                      const SizedBox(height: 4),
                      Text('📍 ${team['location'] ?? "Chưa rõ"}', style: const TextStyle(fontSize: 13, color: Color(0xFF166534))),
                      Text('Đội trưởng: $capName', style: const TextStyle(fontSize: 13, color: Color(0xFF166534))),
                    ],
                  ),
                ),
                if (isProcessing)
                  const CircularProgressIndicator(color: Color(0xFF22C55E))
                else
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _handleRejectInvitation(inv['_id']),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(color: const Color(0xFFFEF2F2), shape: BoxShape.circle, border: Border.all(color: const Color(0xFFFECACA))),
                          child: const Icon(Icons.close, color: Color(0xFFEF4444), size: 18),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => _handleAcceptInvitation(inv['_id']),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle),
                          child: const Icon(Icons.check, color: Colors.white, size: 18),
                        ),
                      ),
                    ],
                  )
              ],
            ),
          );
        }),
      ],
    );
  }

  /// Khối hiển thị các Yêu cầu xin vào đội mà mình đã gửi đi
  Widget _buildSentRequestsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Yêu cầu đã gửi (${_sentRequests.length})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF14532D))),
        const SizedBox(height: 10),
        ..._sentRequests.map((req) {
          final team = req['teamId'] ?? {};
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDCFCE7)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(team['name'] ?? 'Đội bóng', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF14532D))),
                      const SizedBox(height: 4),
                      Text('📍 ${team['location'] ?? "Chưa rõ"}', style: const TextStyle(fontSize: 13, color: Color(0xFF166534))),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                  child: const Text('Đang chờ duyệt', style: TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  /// Khối danh sách các đội bóng đã tham gia (Bấm vào để xem chi tiết)
  Widget _buildMyTeamsListSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Các đội bạn đã tham gia (${_teams.length})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF14532D))),
        const SizedBox(height: 12),
        ..._teams.map((t) {
          final hasLogo = t['logo'] != null && t['logo'].toString().startsWith('data:image');
          final playersCount = (t['players'] as List?)?.length ?? 0;

          return GestureDetector(
            onTap: () => setState(() => _selectedTeamId = t['_id']),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFDCFCE7)),
                boxShadow: const [BoxShadow(color: Color(0x1A16A34A), blurRadius: 8, offset: Offset(0, 3))],
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    margin: const EdgeInsets.only(right: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF4ADE80), width: 2),
                    ),
                    clipBehavior: Clip.hardEdge,
                    alignment: Alignment.center,
                    child: hasLogo
                        ? Image.network(t['logo'], fit: BoxFit.cover)
                        : const Icon(Icons.security, size: 32, color: Color(0xFF22C55E)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t['name'] ?? "", style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF14532D))),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(8)),
                          child: Text('$playersCount/14 thành viên',
                              style: const TextStyle(color: Color(0xFFD97706), fontSize: 11, fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 24, color: Color(0xFF94A3B8)),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  /// Trạng thái khi chưa tham gia đội bóng nào
  Widget _buildEmptyTeamsState() {
    return Container(
      margin: const EdgeInsets.only(top: 40),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFBBF7D0), width: 2),
            ),
            child: const Icon(Icons.security, size: 48, color: Color(0xFF86EFAC)),
          ),
          const SizedBox(height: 16),
          const Text('Bạn chưa có đội bóng', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF14532D))),
          const SizedBox(height: 8),
          const Text('Hãy tạo một đội bóng mới hoặc tìm đội để gia nhập nhé!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF166534), height: 1.4)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context.push('/createTeam'),
            icon: const Icon(Icons.add_circle, color: Colors.white, size: 20),
            label: const Text('Tạo đội ngay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 3,
            ),
          ),
        ],
      ),
    );
  }

  /// GIAO DIỆN CHI TIẾT: Hiển thị khi đã chọn 1 đội bóng cụ thể
  Widget _buildTeamDetailView({required bool isCaptain, required List<dynamic> joinRequests}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Nút quay lại danh sách đội
        GestureDetector(
          onTap: () => setState(() => _selectedTeamId = null),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back, size: 18, color: Color(0xFF475569)),
                SizedBox(width: 6),
                Text('Quay lại danh sách đội', style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
        ),

        // 1. Thẻ thông tin đội bóng (Logo, tên, trình độ, nút Vào Nhóm Chat)
        _buildTeamInfoCard(),

        // 2. Khu vực duyệt người xin vào đội (chỉ dành cho Đội trưởng)
        if (isCaptain) ...[
          _buildJoinRequestsSection(joinRequests),
          const SizedBox(height: 16),
          _buildToggleRecruitingSection(),
          const SizedBox(height: 20),
        ],

        // 3. Danh sách thành viên trong đội
        _buildTeamMembersListSection(isCaptain: isCaptain),
      ],
    );
  }

  /// Thẻ thông tin tổng quát của đội bóng
  Widget _buildTeamInfoCard() {
    final team = _selectedTeam;
    final hasLogo = team['logo'] != null && team['logo'].toString().startsWith('data:image');
    final isRecruiting = team['isRecruiting'] == true;

    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDCFCE7)),
        boxShadow: const [BoxShadow(color: Color(0x1A16A34A), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 70,
                height: 70,
                margin: const EdgeInsets.only(right: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF4ADE80), width: 3),
                ),
                clipBehavior: Clip.hardEdge,
                alignment: Alignment.center,
                child: hasLogo
                    ? Image.network(team['logo'], fit: BoxFit.cover)
                    : const Icon(Icons.security, size: 40, color: Color(0xFF22C55E)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(team['name'] ?? "", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF14532D))),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(8)),
                          margin: const EdgeInsets.only(right: 8),
                          child: Text('${team['skillLevel'] ?? "Sơ cấp"}',
                              style: const TextStyle(color: Color(0xFFD97706), fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isRecruiting ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isRecruiting ? 'Đang tuyển' : 'Đủ người',
                            style: TextStyle(
                              color: isRecruiting ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Địa điểm & Đội trưởng
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 16, color: Color(0xFF16A34A)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(team['location'] ?? "Chưa rõ", style: const TextStyle(color: Color(0xFF166534), fontSize: 14, fontWeight: FontWeight.w600))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.star, size: 16, color: Color(0xFFEAB308)),
                    const SizedBox(width: 8),
                    Builder(builder: (ctx) {
                      final capId = team['captainId'] is Map ? team['captainId']['_id'] : team['captainId'];
                      final capPlayer = (team['players'] as List).firstWhere((p) => p['userId'] == capId, orElse: () => null);
                      final capName = capPlayer?['fullName'] ?? (team['captainId'] is Map ? team['captainId']['username'] : 'Đội trưởng');
                      return Expanded(child: Text('Đội trưởng: $capName', style: const TextStyle(color: Color(0xFF166534), fontSize: 14, fontWeight: FontWeight.w600)));
                    }),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Nút Vào Nhóm Chat Đội Bóng
          ElevatedButton.icon(
            onPressed: () => context.push('/teamChat', extra: {
              'teamId': team['_id'],
              'teamName': team['name'],
            }),
            icon: const Icon(Icons.chat_bubble, color: Colors.white, size: 20),
            label: const Text('Vào Nhóm Chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  /// Khối quản lý yêu cầu xin vào đội (Dành cho Đội trưởng)
  Widget _buildJoinRequestsSection(List<dynamic> joinRequests) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_outlined, color: Color(0xFFEF4444), size: 20),
              const SizedBox(width: 8),
              Text(
                'Yêu cầu gia nhập${joinRequests.isNotEmpty ? ' (${joinRequests.length})' : ''}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: joinRequests.isNotEmpty ? const Color(0xFFEF4444) : const Color(0xFF14532D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (joinRequests.isEmpty)
            const Text('Không có yêu cầu nào đang chờ duyệt.', style: TextStyle(color: Color(0xFF64748B), fontStyle: FontStyle.italic))
          else
            ...joinRequests.map((req) {
              final p = req['requesterId'];
              final isApprove = _processingId == req['_id'] && _processingAction == 'approve';
              final isReject = _processingId == req['_id'] && _processingAction == 'reject';

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                          child: const Icon(Icons.person, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p?['fullName'] ?? 'Ẩn danh', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF7F1D1D))),
                              Text('${p?['position']} • ${p?['location']}', style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C))),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _processingId != null ? null : () => _handleApproveRequest(req['_id']),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E)),
                            child: isApprove
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('Phê duyệt', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _processingId != null ? null : () => _handleRejectRequest(req['_id']),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                            child: isReject
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('Từ chối', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  /// Khối bật/tắt tuyển quân (Dành cho Đội trưởng)
  Widget _buildToggleRecruitingSection() {
    final team = _selectedTeam;
    final bool isRecruiting = team['isRecruiting'] == true;
    final int memberCount = (team['players'] as List).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCFCE7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isRecruiting ? Icons.people : Icons.lock, color: isRecruiting ? const Color(0xFF22C55E) : const Color(0xFFEF4444), size: 20),
              const SizedBox(width: 8),
              Text(isRecruiting ? 'Đang mở tuyển thành viên' : 'Đã đóng tuyển quân',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF14532D))),
            ],
          ),
          const SizedBox(height: 6),
          Text('$memberCount/14 thành viên hiện tại', style: const TextStyle(fontSize: 13, color: Color(0xFF166534))),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: (_togglingRecruiting || memberCount >= 14) ? null : _handleToggleRecruiting,
            icon: _togglingRecruiting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Icon(isRecruiting ? Icons.lock_outline : Icons.people_outline, color: Colors.white, size: 16),
            label: Text(isRecruiting ? 'Dừng tuyển' : 'Mở tuyển lại',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            style: ElevatedButton.styleFrom(
              backgroundColor: isRecruiting ? const Color(0xFFEF4444) : const Color(0xFF22C55E),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          )
        ],
      ),
    );
  }

  /// Khối danh sách thành viên trong đội
  Widget _buildTeamMembersListSection({required bool isCaptain}) {
    final team = _selectedTeam;
    final List players = team['players'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Thành viên trong đội (${players.length}/14)',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF14532D))),
        const SizedBox(height: 12),
        if (players.isEmpty)
          const Text('Đội chưa có thành viên nào khác.', style: TextStyle(color: Color(0xFF16A34A), fontStyle: FontStyle.italic))
        else
          ...players.map((p) {
            final bool isThisCaptainsProfile = isCaptain && p['_id'] == _myProfileId;
            final bool isBeingKicked = _kickingId == p['_id'];

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF0FDF4)),
                boxShadow: const [BoxShadow(color: Color(0x0D16A34A), blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle),
                    child: const Icon(Icons.person, color: Colors.white, size: 22),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            text: p['fullName'] ?? 'Ẩn danh',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF14532D)),
                            children: [
                              if (isThisCaptainsProfile)
                                const TextSpan(text: ' 👑 Đội trưởng', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 12)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text('${p['position']} • ${p['location']}', style: const TextStyle(fontSize: 12, color: Color(0xFF166534))),
                      ],
                    ),
                  ),
                  // Đội trưởng có quyền xóa thành viên (nhưng không thể tự xóa chính mình)
                  if (isCaptain && !isThisCaptainsProfile)
                    GestureDetector(
                      onTap: isBeingKicked ? null : () => _handleKick(p['_id'], p['fullName'] ?? 'thành viên'),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(10)),
                        child: isBeingKicked
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFFEF4444), strokeWidth: 2))
                            : const Icon(Icons.remove_circle_outline, color: Color(0xFFEF4444), size: 20),
                      ),
                    ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
