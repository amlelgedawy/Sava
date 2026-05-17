import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme.dart';
import '../../app_state.dart';
import '../../services/api_service.dart';

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});
  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ApiService.adminListUsers();
      if (mounted)
        setState(() {
          _all = list.cast<Map<String, dynamic>>();
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _caregivers => _all
      .where((u) => (u['role'] as String? ?? '').toUpperCase() == 'CAREGIVER')
      .toList();
  List<Map<String, dynamic>> get _relatives => _all
      .where((u) => (u['role'] as String? ?? '').toUpperCase() == 'RELATIVE')
      .toList();

  void _confirmDelete(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete User',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Delete ${user['name']}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancel', style: TextStyle(color: SovaColors.sage)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final adminId = AppState.userId.value ?? '';
              try {
                await ApiService.adminDeleteUser(
                    adminId: adminId, userId: user['id'].toString());
              } catch (_) {}
              _load();
            },
            child: const Text('Delete',
                style: TextStyle(color: SovaColors.danger)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SovaColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: SovaColors.softGlass,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.arrow_back,
                              color: SovaColors.charcoal, size: 18),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ADMIN',
                                style: SovaTheme.textTheme.labelMedium),
                            Text('Users',
                                style: SovaTheme.textTheme.displayMedium),
                            Text(
                                '${_loading ? '...' : _all.length} registered users',
                                style: TextStyle(
                                    color: SovaColors.sage, fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            TabBar(
              controller: _tabs,
              labelColor: SovaColors.charcoal,
              unselectedLabelColor: SovaColors.sage,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold),
              indicatorColor: SovaColors.navy,
              indicatorSize: TabBarIndicatorSize.label,
              tabs: [
                Tab(text: 'All (${_all.length})'),
                Tab(text: 'Caregivers (${_caregivers.length})'),
                Tab(text: 'Relatives (${_relatives.length})'),
              ],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _userList(_all),
                        _userList(_caregivers),
                        _userList(_relatives),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _userList(List<Map<String, dynamic>> users) {
    if (users.isEmpty) {
      return Center(
        child: Text('No users in this category',
            style: TextStyle(color: SovaColors.sage)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 110),
      itemCount: users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final u = users[i];
        return _UserCard(
          user: u,
          onDelete: () => _confirmDelete(u),
        ).animate().fadeIn(delay: (i * 60).ms).slideY(begin: 0.08);
      },
    );
  }
}

class _UserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onDelete;
  const _UserCard({required this.user, required this.onDelete});

  Color get _roleColor {
    final role = (user['role'] as String? ?? '').toUpperCase();
    if (role == 'CAREGIVER') return SovaColors.navy;
    if (role == 'RELATIVE') return SovaColors.coral;
    return SovaColors.charcoal;
  }

  String get _roleLabel {
    final role = (user['role'] as String? ?? '').toUpperCase();
    if (role == 'CAREGIVER') return 'Caregiver';
    if (role == 'RELATIVE') return 'Relative';
    return 'Admin';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: _roleColor.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(Icons.person, color: _roleColor, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user['name'] as String? ?? '',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: SovaColors.charcoal)),
            Text(user['email'] as String? ?? '',
                style: const TextStyle(color: SovaColors.sage, fontSize: 12)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: _roleColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Text(_roleLabel,
                  style: TextStyle(
                      color: _roleColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
        if ((user['role'] as String? ?? '').toUpperCase() != 'ADMIN')
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: SovaColors.sage, size: 20),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (v) {
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline,
                      size: 18, color: SovaColors.danger),
                  SizedBox(width: 8),
                  Text('Delete User',
                      style: TextStyle(color: SovaColors.danger)),
                ]),
              ),
            ],
          ),
      ]),
    );
  }
}
