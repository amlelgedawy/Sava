import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme.dart';
import '../../models/user_models.dart';
import '../../services/mock_service.dart';

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});
  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<AppUser> _all = [];

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

  void _load() {
    setState(() => _all = MockService.instance.getAllUsers().toList());
  }

  List<CaregiverUser> get _caregivers =>
      _all.whereType<CaregiverUser>().toList();
  List<RelativeUser> get _relatives =>
      _all.whereType<RelativeUser>().toList();

  void _confirmDelete(AppUser user) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete User',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Delete ${user.name}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: SovaColors.sage)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              MockService.instance.deleteUser(user.id);
              _load();
            },
            child: const Text('Delete',
                style: TextStyle(color: SovaColors.danger)),
          ),
        ],
      ),
    );
  }

  void _changeRelativeType(RelativeUser rel) {
    final newType = rel.relativeType == RelativeType.primary
        ? RelativeType.secondary
        : RelativeType.primary;
    MockService.instance.changeRelativeType(rel.id, newType);
    _load();
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
                  Text('ADMIN', style: SovaTheme.textTheme.labelMedium),
                  Text('Users', style: SovaTheme.textTheme.displayMedium),
                  Text('${_all.length} registered users',
                      style: TextStyle(
                          color: SovaColors.sage, fontSize: 14)),
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
              child: TabBarView(
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

  Widget _userList(List<AppUser> users) {
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
          onChangeType: u is RelativeUser
              ? () => _changeRelativeType(u)
              : null,
        ).animate().fadeIn(delay: (i * 60).ms).slideY(begin: 0.08);
      },
    );
  }
}

class _UserCard extends StatelessWidget {
  final AppUser user;
  final VoidCallback onDelete;
  final VoidCallback? onChangeType;
  const _UserCard(
      {required this.user,
      required this.onDelete,
      this.onChangeType});

  Color get _roleColor {
    switch (user.role) {
      case UserRole.caregiver:
        return SovaColors.navy;
      case UserRole.relative:
        return SovaColors.coral;
      case UserRole.admin:
        return SovaColors.charcoal;
    }
  }

  String get _roleLabel {
    switch (user.role) {
      case UserRole.caregiver:
        final cg = user as CaregiverUser;
        return cg.cvVerified ? 'Caregiver ✓' : 'Caregiver (pending)';
      case UserRole.relative:
        final rel = user as RelativeUser;
        return rel.relativeType == RelativeType.primary
            ? 'Primary Relative'
            : 'Secondary Relative';
      case UserRole.admin:
        return 'Admin';
    }
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
              color: _roleColor.withValues(alpha: 0.1),
              shape: BoxShape.circle),
          child: Icon(Icons.person, color: _roleColor, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: SovaColors.charcoal)),
                Text(user.email,
                    style: const TextStyle(
                        color: SovaColors.sage, fontSize: 12)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
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
        if (user.role != UserRole.admin)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert,
                color: SovaColors.sage, size: 20),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            onSelected: (v) {
              if (v == 'delete') onDelete();
              if (v == 'type') onChangeType?.call();
            },
            itemBuilder: (_) => [
              if (onChangeType != null)
                const PopupMenuItem(
                  value: 'type',
                  child: Row(children: [
                    Icon(Icons.swap_horiz, size: 18, color: SovaColors.navy),
                    SizedBox(width: 8),
                    Text('Change Type'),
                  ]),
                ),
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
