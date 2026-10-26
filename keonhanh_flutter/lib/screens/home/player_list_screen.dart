import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../services/auth_provider.dart';
import '../../config/api.dart';

/// Màn hình "Tuyển Quân / Danh Sách Cầu Thủ"
/// Cho phép duyệt tìm cầu thủ tự do, lọc vị trí/khu vực và Đội trưởng gửi lời mời vào đội.
class PlayerListScreen extends StatefulWidget {
  const PlayerListScreen({super.key});

  @override
  State<PlayerListScreen> createState() => _PlayerListScreenState();
}

class _PlayerListScreenState extends State<PlayerListScreen> {
  // ===========================================================================
  // PHẦN 1: CÁC BIẾN QUẢN LÝ DỮ LIỆU (STATE)
  // ===========================================================================

  List<dynamic> _players = []; // Danh sách toàn bộ cầu thủ đang tìm đội
  bool _loading = true; // Trạng thái đang tải danh sách

  // Thông tin nhận diện người dùng hiện tại & đội bóng làm đội trưởng
  String? _myProfileId; // ID hồ sơ cá nhân của mình
  List<dynamic> _myCaptainTeams = []; // Danh sách các đội mà mình làm đội trưởng
  final Set<String> _myTeamMemberProfileIds = {}; // Tập hợp các ID thành viên đã ở trong đội của mình

  // Bộ lọc
  String _filterPosition = "Tất cả"; // Vị trí thi đấu cần lọc
  final TextEditingController _filterLocationController = TextEditingController(); // Khu vực cần lọc
  bool _hideMyProfile = false; // Tùy chọn ẩn hồ sơ của chính mình

  // ===========================================================================
  // PHẦN 2: CÁC HÀM XỬ LÝ (GỌI API VỀ MÁY CHỦ)
  // ===========================================================================

  @override
  void initState() {
    super.initState();
    _fetchPlayers(); // Tải danh sách cầu thủ khi vừa mở màn hình
  }

  @override
  void dispose() {
    _filterLocationController.dispose();
    super.dispose();
  }

  /// 1. Tải danh sách cầu thủ từ server và thông tin đội trưởng của mình
  Future<void> _fetchPlayers() async {
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final currentUserId = auth.userId;

    try {
      // 1.1 Tải danh sách các cầu thủ đang có nhu cầu tìm đội (isLookingForTeam != false)
      final res = await http.get(Uri.parse('$API_BASE_URL/api/players'));
      final json = jsonDecode(res.body);

      if (res.statusCode == 200) {
        final List<dynamic> playersData = json['players'] ?? [];
        final filteredPlayers = playersData.where((p) => p['isLookingForTeam'] != false).toList();
        _players = filteredPlayers;
      }

      // 1.2 Nếu người dùng đã đăng nhập, tải profile & đội của họ để nhận diện Đội trưởng
      if (auth.isLoggedIn && currentUserId != null) {
        try {
          final profileRes = await http.get(Uri.parse('$API_BASE_URL/api/user-profiles/$currentUserId'));
          if (profileRes.statusCode == 200) {
            final profileJson = jsonDecode(profileRes.body);
            if (profileJson['profile'] != null) {
              _myProfileId = profileJson['profile']['_id']?.toString();

              if (_myProfileId != null) {
                final teamRes = await http.get(Uri.parse('$API_BASE_URL/api/teams/my-team/$_myProfileId'));
                if (teamRes.statusCode == 200) {
                  final teamJson = jsonDecode(teamRes.body);
                  if (teamJson['success'] == true && teamJson['data'] is List) {
                    final teams = teamJson['data'] as List;

                    // Lọc ra các đội mà tài khoản này làm Đội trưởng
                    final captainTeams = teams.where((t) {
                      final capId = t['captainId'];
                      if (capId is Map) {
                        return capId['_id']?.toString().toLowerCase() == currentUserId.toLowerCase();
                      }
                      return capId?.toString().toLowerCase() == currentUserId.toLowerCase();
                    }).toList();

                    _myCaptainTeams = captainTeams;
                    _myTeamMemberProfileIds.clear();

                    // Thu thập ID tất cả thành viên trong đội của mình để tránh mời trùng
                    for (final team in captainTeams) {
                      final players = team['players'] as List? ?? [];
                      for (final p in players) {
                        if (p is Map && p['_id'] != null) {
                          _myTeamMemberProfileIds.add(p['_id'].toString().toLowerCase());
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        } catch (e) {
          debugPrint("Lỗi tải thông tin đội trưởng: $e");
        }
      }
    } catch (e) {
      debugPrint("Lỗi tải danh sách cầu thủ: $e");
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// 2. Xử lý khi nhấn nút "Mời Đá Ngay"
  Future<void> _handleInviteClick(dynamic targetPlayer) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      _showAlert("Chưa đăng nhập", "Bạn cần đăng nhập tài khoản để mời cầu thủ.");
      return;
    }

    final currentUserId = auth.userId;
    final targetUserId = targetPlayer['userId']?.toString();
    final targetProfileId = targetPlayer['_id']?.toString();
    final targetName = targetPlayer['fullName'] ?? 'Cầu thủ';

    // 2.1 Kiểm tra nghiêm ngặt: KHÔNG THỂ TỰ MỜI CHÍNH MÌNH
    final isMe = (currentUserId != null && targetUserId != null && currentUserId.toLowerCase() == targetUserId.toLowerCase()) ||
        (_myProfileId != null && targetProfileId != null && _myProfileId!.toLowerCase() == targetProfileId.toLowerCase());

    if (isMe) {
      _showAlert("Không thể thực hiện", "Bạn là đội trưởng của đội, không thể tự mời chính mình vào đội!");
      return;
    }

    // 2.2 Kiểm tra nếu cầu thủ đã là thành viên trong đội của mình
    if (targetProfileId != null && _myTeamMemberProfileIds.contains(targetProfileId.toLowerCase())) {
      _showAlert("Thông báo", "$targetName đã là thành viên trong đội bóng của bạn.");
      return;
    }

    // 2.3 Kiểm tra quyền Đội trưởng: Phải có đội bóng mới được tuyển quân
    if (_myCaptainTeams.isEmpty) {
      _showNeedCreateTeamDialog();
      return;
    }

    // 2.4 Nếu có 1 đội: Mở xác nhận gửi lời mời
    if (_myCaptainTeams.length == 1) {
      final team = _myCaptainTeams[0];
      _confirmAndSendInvite(team, targetPlayer);
      return;
    }

    // 2.5 Nếu có nhiều đội: Cho phép Đội trưởng chọn đội bóng muốn mời vào
    _showSelectTeamBottomSheet(targetPlayer);
  }

  /// Hộp thoại nhắc nhở cần tạo đội bóng trước
  void _showNeedCreateTeamDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Color(0xFFF59E0B)),
            SizedBox(width: 8),
            Text('Bạn chưa có đội bóng', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Chỉ đội trưởng mới có quyền tuyển quân và gửi lời mời tham gia đội. Bạn hãy tạo đội bóng của riêng mình trước nhé!',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Để sau', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              context.push('/createTeam');
            },
            child: const Text('Tạo đội ngay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Bottom sheet chọn đội bóng để mời cầu thủ vào (khi Đội trưởng có nhiều hơn 1 đội)
  void _showSelectTeamBottomSheet(dynamic targetPlayer) {
    final targetName = targetPlayer['fullName'] ?? 'Cầu thủ';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Mời $targetName vào đội',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
            const SizedBox(height: 6),
            const Text('Chọn đội bóng bạn muốn mời cầu thủ này gia nhập:', style: TextStyle(fontSize: 14, color: Color(0xFF64748B))),
            const SizedBox(height: 16),
            ..._myCaptainTeams.map((team) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: ListTile(
                  title: Text(team['name'] ?? 'Đội bóng', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF166534))),
                  subtitle: Text('📍 ${team['location'] ?? "Chưa rõ địa điểm"}'),
                  trailing: const Icon(Icons.send, color: Color(0xFF16A34A)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmAndSendInvite(team, targetPlayer);
                  },
                ),
              );
            }),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  /// Hộp thoại xác nhận gửi lời mời
  void _confirmAndSendInvite(dynamic team, dynamic targetPlayer) {
    final teamId = team['_id'];
    final teamName = team['name'] ?? 'Đội bóng';
    final targetName = targetPlayer['fullName'] ?? 'Cầu thủ';
    final targetProfileId = targetPlayer['_id'];
    final currentUserId = context.read<AuthProvider>().userId;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Xác nhận gửi lời mời', style: TextStyle(fontWeight: FontWeight.bold)),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 15, color: Color(0xFF1E293B), height: 1.5),
            children: [
              const TextSpan(text: 'Bạn có chắc chắn muốn mời cầu thủ '),
              TextSpan(text: '$targetName ', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
              const TextSpan(text: 'gia nhập đội '),
              TextSpan(text: '$teamName ', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
              const TextSpan(text: 'không?'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _sendInviteApi(teamId, targetProfileId, currentUserId);
            },
            child: const Text('Gửi lời mời', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Gửi API lời mời lên máy chủ
  Future<void> _sendInviteApi(String teamId, String targetProfileId, String? currentUserId) async {
    try {
      final res = await http.post(
        Uri.parse('$API_BASE_URL/api/invitations'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'teamId': teamId,
          'playerProfileId': targetProfileId,
          'captainUserId': currentUserId,
        }),
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        _showAlert('Thành công', data['message'] ?? 'Đã gửi lời mời tham gia đội bóng thành công!');
      } else {
        _showAlert('Không thể gửi', data['message'] ?? 'Có lỗi xảy ra khi gửi lời mời.');
      }
    } catch (e) {
      _showAlert('Lỗi', 'Không thể kết nối đến máy chủ: $e');
    }
  }

  /// Hộp thoại thông báo tiện ích
  void _showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message, style: const TextStyle(fontSize: 15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK", style: TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Mở Bottom Sheet Lọc cầu thủ (Vị trí, Khu vực, Ẩn hồ sơ của tôi)
  void _showFilterModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32)),
            ),
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Lọc Cầu Thủ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const Icon(Icons.close, size: 26, color: Color(0xFF1F293B)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  const Text('Vị trí thi đấu', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: ["Tất cả", "Tiền đạo", "Tiền vệ", "Hậu vệ", "Thủ môn", "Tự do"].map((pos) {
                      final isActive = _filterPosition == pos;
                      return GestureDetector(
                        onTap: () {
                          setModalState(() => _filterPosition = pos);
                          setState(() => _filterPosition = pos);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isActive ? const Color(0xFF22C55E) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: isActive ? const Color(0xFF16A34A) : const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            pos,
                            style: TextStyle(
                              color: isActive ? Colors.white : const Color(0xFF475569),
                              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  const Text('Khu vực / Tỉnh thành', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _filterLocationController,
                    decoration: InputDecoration(
                      hintText: 'Nhập khu vực...',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.all(14),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF22C55E))),
                    ),
                    onChanged: (val) => setState(() {}),
                  ),
                  const SizedBox(height: 16),

                  // Tùy chọn: Ẩn hồ sơ của chính mình
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      title: const Text('Ẩn hồ sơ của tôi khỏi danh sách', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF14532D))),
                      subtitle: const Text('Chỉ hiển thị các cầu thủ khác cần tuyển', style: TextStyle(fontSize: 12, color: Color(0xFF16A34A))),
                      value: _hideMyProfile,
                      activeThumbColor: const Color(0xFF16A34A),
                      onChanged: (val) {
                        setModalState(() => _hideMyProfile = val);
                        setState(() => _hideMyProfile = val);
                      },
                    ),
                  ),

                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: ElevatedButton(
                          onPressed: () {
                            setModalState(() {
                              _filterPosition = "Tất cả";
                              _filterLocationController.clear();
                              _hideMyProfile = false;
                            });
                            setState(() {
                              _filterPosition = "Tất cả";
                              _hideMyProfile = false;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF1F5F9),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: const Text('Xóa lọc', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700, fontSize: 16)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF16A34A),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: const Text('Áp dụng', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // PHẦN 3: GIAO DIỆN CHÍNH (BUILD)
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final currentUserId = auth.userId;

    // Lọc danh sách theo Vị trí, Địa điểm và Tùy chọn Ẩn bản thân
    final displayedPlayers = _players.where((player) {
      final matchPosition = _filterPosition == "Tất cả" || (player['position'] != null && player['position'].contains(_filterPosition));
      final locationText = _filterLocationController.text.toLowerCase();
      final matchLocation = locationText.isEmpty || (player['location'] != null && player['location'].toLowerCase().contains(locationText));

      if (_hideMyProfile) {
        final targetUserId = player['userId']?.toString();
        final targetProfileId = player['_id']?.toString();
        final isMe = (currentUserId != null && targetUserId != null && currentUserId.toLowerCase() == targetUserId.toLowerCase()) ||
            (_myProfileId != null && targetProfileId != null && _myProfileId!.toLowerCase() == targetProfileId.toLowerCase());
        if (isMe) return false;
      }

      return matchPosition && matchLocation;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4FDF4),
      body: SafeArea(
        child: Column(
          children: [
            // Thanh tiêu đề Header xanh lá
            _buildHeader(),

            // Thanh thông báo khi đang bật "Ẩn hồ sơ của bạn"
            if (_hideMyProfile) _buildQuickFilterBanner(),

            // Danh sách cầu thủ
            Expanded(
              child: _loading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Color(0xFF22C55E)),
                          SizedBox(height: 16),
                          Text('Đang tải danh sách...', style: TextStyle(color: Color(0xFF16A34A), fontSize: 16, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: const Color(0xFF16A34A),
                      onRefresh: _fetchPlayers,
                      child: displayedPlayers.isEmpty
                          ? ListView(
                              children: [
                                SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                                Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDCFCE7),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: const Color(0xFFBBF7D0), width: 2),
                                        ),
                                        child: const Icon(Icons.people, size: 44, color: Color(0xFF86EFAC)),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text('Chưa có cầu thủ nào phù hợp',
                                          style: TextStyle(color: Color(0xFF15803D), fontSize: 16, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                              itemCount: displayedPlayers.length,
                              itemBuilder: (context, index) => _buildPlayerCard(displayedPlayers[index]),
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

  /// Header trên cùng
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      decoration: const BoxDecoration(
        color: Color(0xFF16A34A),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
        boxShadow: [BoxShadow(color: Color(0x4D14532D), offset: Offset(0, 6), blurRadius: 10)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TUYỂN QUÂN ⚽', style: TextStyle(fontSize: 15, color: Color(0xFFDCFCE7), fontWeight: FontWeight.w600, letterSpacing: 1)),
              SizedBox(height: 4),
              Text('Tìm Đồng Đội', style: TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.w900)),
            ],
          ),
          GestureDetector(
            onTap: _showFilterModal,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black26, offset: Offset(0, 2), blurRadius: 4)],
              ),
              child: Icon(
                _hideMyProfile || _filterPosition != "Tất cả" || _filterLocationController.text.isNotEmpty
                    ? Icons.filter_alt
                    : Icons.tune,
                color: const Color(0xFF16A34A),
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Banner thông báo nhanh khi đang ẩn hồ sơ
  Widget _buildQuickFilterBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.visibility_off, size: 16, color: Color(0xFF2563EB)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Đang ẩn hồ sơ của bạn khỏi danh sách tìm kiếm.',
                style: TextStyle(fontSize: 13, color: Color(0xFF1E40AF), fontWeight: FontWeight.w600)),
          ),
          GestureDetector(
            onTap: () => setState(() => _hideMyProfile = false),
            child: const Text('Hiện lại',
                style: TextStyle(fontSize: 13, color: Color(0xFF2563EB), fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
          ),
        ],
      ),
    );
  }

  /// Thẻ thông tin một cầu thủ
  Widget _buildPlayerCard(dynamic item) {
    final avatarUrl = item['avatar'] ?? "";
    final hasAvatar = avatarUrl.startsWith('http') || avatarUrl.startsWith('data:image');

    final auth = context.read<AuthProvider>();
    final currentUserId = auth.userId;
    final targetUserId = item['userId']?.toString();
    final targetProfileId = item['_id']?.toString();

    // Xác định vai trò: Đây có phải là chính bạn hay không?
    final bool isMe = auth.isLoggedIn &&
        ((currentUserId != null && targetUserId != null && currentUserId.toLowerCase() == targetUserId.toLowerCase()) ||
            (_myProfileId != null && targetProfileId != null && _myProfileId!.toLowerCase() == targetProfileId.toLowerCase()));

    // Cầu thủ này đã ở trong đội của mình chưa?
    final bool isInMyTeam = targetProfileId != null && _myTeamMemberProfileIds.contains(targetProfileId.toLowerCase());
    final bool isCaptain = _myCaptainTeams.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isMe ? const Color(0xFF93C5FD) : const Color(0xFFDCFCE7), width: isMe ? 2 : 1),
        boxShadow: [
          BoxShadow(
            color: isMe ? const Color(0x1A2563EB) : const Color(0x1A16A34A),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                margin: const EdgeInsets.only(right: 14),
                decoration: BoxDecoration(
                  color: isMe ? const Color(0xFFEFF6FF) : const Color(0xFFF0FDF4),
                  shape: BoxShape.circle,
                  border: Border.all(color: isMe ? const Color(0xFF3B82F6) : const Color(0xFF4ADE80), width: 2.5),
                ),
                clipBehavior: Clip.hardEdge,
                child: hasAvatar
                    ? Image.network(avatarUrl, fit: BoxFit.cover)
                    : Image.network("https://cdn-icons-png.flaticon.com/512/149/149071.png", fit: BoxFit.cover),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item['fullName'] ?? "",
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF14532D)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Badge hiển thị nhận diện Bạn / Bạn (Đội trưởng)
                        if (isMe) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDBEAFE),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF3B82F6)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(isCaptain ? Icons.shield : Icons.person, size: 12, color: const Color(0xFF1D4ED8)),
                                const SizedBox(width: 4),
                                Text(
                                  isCaptain ? 'Bạn (Đội trưởng)' : 'Bạn',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF1E40AF)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildDetailRow(Icons.sports_soccer, item['position'] ?? "Cầu thủ tự do", const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
                    _buildDetailRow(Icons.location_on, item['location'] ?? "Chưa cập nhật", const Color(0xFFF0FDF4), const Color(0xFF22C55E)),
                    if (item['phone'] != null && item['phone'].toString().isNotEmpty)
                      _buildDetailRow(Icons.phone, item['phone'], const Color(0xFFF8FAFC), const Color(0xFF475569)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // NÚT HÀNH ĐỘNG (Xử lý riêng cho Chính mình, Thành viên đã trong đội, và Cầu thủ khác)
          _buildCardActionButton(
            isMe: isMe,
            isInMyTeam: isInMyTeam,
            isCaptain: isCaptain,
            onInviteTap: () => _handleInviteClick(item),
          ),
        ],
      ),
    );
  }

  /// Nút hành động trên thẻ cầu thủ
  Widget _buildCardActionButton({
    required bool isMe,
    required bool isInMyTeam,
    required bool isCaptain,
    required VoidCallback onInviteTap,
  }) {
    // 1. Nếu là chính mình: Vô hiệu hóa hoàn toàn, ghi rõ trạng thái
    if (isMe) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isCaptain ? Icons.shield : Icons.person, size: 16, color: const Color(0xFF64748B)),
            const SizedBox(width: 8),
            Text(
              isCaptain ? 'Bạn là Đội trưởng (Không thể tự mời)' : 'Hồ sơ của bạn (Không thể tự mời)',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
    }

    // 2. Nếu cầu thủ này đã ở trong đội của mình: Không cần mời lại
    if (isInMyTeam) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 16, color: Color(0xFF16A34A)),
            SizedBox(width: 8),
            Text(
              'Đã là thành viên trong đội của bạn',
              style: TextStyle(color: Color(0xFF166534), fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
    }

    // 3. Nếu là cầu thủ khác: Nút mời đá ngay màu xanh lá
    return ElevatedButton.icon(
      onPressed: onInviteTap,
      icon: const Icon(Icons.mail, size: 16, color: Colors.white),
      label: const Text('Mời Đá Ngay', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF16A34A),
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 2,
      ),
    );
  }

  /// Dòng hiển thị chi tiết (icon + text)
  Widget _buildDetailRow(IconData icon, String text, Color bgColor, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6)),
            alignment: Alignment.center,
            margin: const EdgeInsets.only(right: 8),
            child: Icon(icon, size: 13, color: iconColor),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: Color(0xFF166534), fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
