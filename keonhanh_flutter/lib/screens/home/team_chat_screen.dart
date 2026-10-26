import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../services/auth_provider.dart';
import '../../config/api.dart';

class TeamChatScreen extends StatefulWidget {
  final String teamId;
  final String teamName;

  const TeamChatScreen({
    super.key,
    required this.teamId,
    required this.teamName,
  });

  @override
  State<TeamChatScreen> createState() => _TeamChatScreenState();
}

class _TeamChatScreenState extends State<TeamChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<dynamic> _messages = [];
  bool _loading = true;
  bool _sending = false;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _fetchMessages(initial: true);
    // Polling tự động mỗi 3 giây để cập nhật tin nhắn mới
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        _fetchMessages(initial: false);
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchMessages({bool initial = false}) async {
    if (widget.teamId.isEmpty) return;
    if (initial) setState(() => _loading = true);

    try {
      final res = await http.get(Uri.parse('$API_BASE_URL/api/messages/${widget.teamId}'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is List) {
          final previousCount = _messages.length;
          if (mounted) {
            setState(() {
              _messages = data;
              _loading = false;
            });
            // Nếu có tin nhắn mới thì cuộn xuống cuối
            if (data.length > previousCount || initial) {
              _scrollToBottom();
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Lỗi tải tin nhắn: $e");
    } finally {
      if (initial && mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;

    final auth = context.read<AuthProvider>();
    final currentUserId = auth.userId;

    if (!auth.isLoggedIn || currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng đăng nhập để gửi tin nhắn.')),
      );
      return;
    }

    setState(() => _sending = true);
    _messageController.clear();

    try {
      final res = await http.post(
        Uri.parse('$API_BASE_URL/api/messages'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'teamId': widget.teamId,
          'senderId': currentUserId,
          'content': text,
        }),
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        await _fetchMessages(initial: false);
        _scrollToBottom();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể gửi tin nhắn. Vui lòng thử lại.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi kết nối: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  String _formatTime(dynamic dateString) {
    if (dateString == null) return '';
    try {
      final dt = DateTime.parse(dateString.toString()).toLocal();
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final currentUserId = auth.userId?.toString().toLowerCase();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 1,
        backgroundColor: const Color(0xFF16A34A),
        foregroundColor: Colors.white,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFDCFCE7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.groups, color: Color(0xFF16A34A), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.teamName,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    'Trò chuyện nội bộ đội bóng',
                    style: TextStyle(fontSize: 12, color: Color(0xFFDCFCE7), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 22),
            tooltip: 'Làm mới',
            onPressed: () => _fetchMessages(initial: true),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Khu vực danh sách tin nhắn
            Expanded(
              child: _loading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Color(0xFF16A34A)),
                          SizedBox(height: 12),
                          Text('Đang tải tin nhắn...', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                        ],
                      ),
                    )
                  : _messages.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFDCFCE7),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.chat_bubble_outline, size: 40, color: Color(0xFF16A34A)),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Chưa có tin nhắn nào',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Hãy gửi lời chào đầu tiên đến các thành viên trong đội bóng!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 14, color: Color(0xFF64748B), height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final sender = msg['senderId'] is Map ? msg['senderId'] : {};
                            final senderUserId = sender['_id']?.toString().toLowerCase();
                            final isMe = currentUserId != null && senderUserId != null && currentUserId == senderUserId;
                            final senderName = sender['fullName'] ?? 'Ẩn danh';
                            final avatarUrl = sender['avatar'] ?? '';
                            final hasAvatar = avatarUrl.toString().startsWith('http') || avatarUrl.toString().startsWith('data:image');
                            final timeStr = _formatTime(msg['createdAt']);

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14.0),
                              child: Row(
                                mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (!isMe) ...[
                                    Container(
                                      width: 34,
                                      height: 34,
                                      margin: const EdgeInsets.only(right: 8, bottom: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE2E8F0),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: const Color(0xFFCBD5E1)),
                                      ),
                                      clipBehavior: Clip.hardEdge,
                                      child: hasAvatar
                                          ? Image.network(avatarUrl, fit: BoxFit.cover)
                                          : const Icon(Icons.person, size: 20, color: Color(0xFF64748B)),
                                    ),
                                  ],
                                  Flexible(
                                    child: Column(
                                      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                      children: [
                                        if (!isMe)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 4, bottom: 4),
                                            child: Text(
                                              senderName,
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
                                            ),
                                          ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          decoration: BoxDecoration(
                                            color: isMe ? const Color(0xFF16A34A) : Colors.white,
                                            borderRadius: BorderRadius.only(
                                              topLeft: const Radius.circular(18),
                                              topRight: const Radius.circular(18),
                                              bottomLeft: Radius.circular(isMe ? 18 : 4),
                                              bottomRight: Radius.circular(isMe ? 4 : 18),
                                            ),
                                            border: isMe ? null : Border.all(color: const Color(0xFFE2E8F0)),
                                            boxShadow: [
                                              BoxShadow(
                                                color: isMe ? const Color(0x3316A34A) : const Color(0x0A000000),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Text(
                                            msg['content'] ?? '',
                                            style: TextStyle(
                                              fontSize: 15,
                                              color: isMe ? Colors.white : const Color(0xFF0F172A),
                                              height: 1.4,
                                            ),
                                          ),
                                        ),
                                        if (timeStr.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                                            child: Text(
                                              timeStr,
                                              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),

            // Thanh nhập tin nhắn (Input Bar)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x0D000000),
                    offset: const Offset(0, -2),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextField(
                        controller: _messageController,
                        focusNode: _focusNode,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _handleSendMessage(),
                        maxLines: null,
                        decoration: const InputDecoration(
                          hintText: 'Nhập tin nhắn vào nhóm...',
                          hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      color: Color(0xFF16A34A),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Color(0x3316A34A), blurRadius: 6, offset: Offset(0, 2)),
                      ],
                    ),
                    child: IconButton(
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      onPressed: _sending ? null : _handleSendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
