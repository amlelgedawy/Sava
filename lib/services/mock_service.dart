import 'dart:math';
import '../models/user_models.dart';

class MockService {
  static final MockService instance = MockService._internal();
  MockService._internal() {
    _seedData();
  }

  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;

  final List<AppUser> _users = [];
  final List<Patient> _patients = [];

  void _seedData() {
    _users.add(AdminUser(
      id: 'admin-1',
      name: 'Admin',
      email: 'admin@sava.com',
      password: 'admin123',
    ));
    _users.add(CaregiverUser(
      id: 'cg-1',
      name: 'Ahmed Hassan',
      email: 'ahmed@sava.com',
      password: 'pass123',
      age: 32,
      nationalId: '29001011234567',
      cvFileName: 'ahmed_cv.pdf',
      cvVerified: true,
      salary: 3500,
      yearsExperience: 5,
      assignedPatientIds: ['p-1'],
    ));
    _users.add(CaregiverUser(
      id: 'cg-2',
      name: 'Sara Khalil',
      email: 'sara@sava.com',
      password: 'pass123',
      age: 28,
      nationalId: '29501021234568',
      cvFileName: 'sara_cv.pdf',
      cvVerified: false,
      yearsExperience: 2,
    ));
    _users.add(CaregiverUser(
      id: 'cg-3',
      name: 'Omar Fathy',
      email: 'omar@sava.com',
      password: 'pass123',
      age: 35,
      nationalId: '29201031234569',
      cvFileName: 'omar_cv.pdf',
      cvVerified: true,
      salary: 4200,
      yearsExperience: 8,
    ));
    _users.add(RelativeUser(
      id: 'rel-1',
      name: 'Mohamed Ali',
      email: 'mohamed@sava.com',
      password: 'pass123',
      relativeType: RelativeType.primary,
      patientId: 'p-1',
    ));
    _patients.add(Patient(
      id: 'p-1',
      name: 'Hassan Ali',
      primaryRelativeId: 'rel-1',
      assignedCaregiverId: 'cg-1',
    ));
  }

  String _genId(String prefix) =>
      '$prefix-${Random().nextInt(99999).toString().padLeft(5, '0')}';

  // ── AUTH ──────────────────────────────────────────────────────────────────

  Future<AppUser?> login(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 700));
    try {
      final user = _users.firstWhere(
        (u) =>
            u.email.toLowerCase() == email.trim().toLowerCase() &&
            u.password == password,
      );
      _currentUser = user;
      return user;
    } catch (_) {
      return null;
    }
  }

  Future<CaregiverUser> signupCaregiver({
    required String name,
    required String email,
    required String password,
    required int age,
    required String nationalId,
    String? cvFileName,
    String? nationalIdPhotoName,
  }) async {
    await Future.delayed(const Duration(milliseconds: 700));
    final user = CaregiverUser(
      id: _genId('cg'),
      name: name,
      email: email,
      password: password,
      age: age,
      nationalId: nationalId,
      cvFileName: cvFileName,
      nationalIdPhotoName: nationalIdPhotoName,
    );
    _users.add(user);
    _currentUser = user;
    return user;
  }

  Future<RelativeUser> signupRelative({
    required String name,
    required String email,
    required String password,
    required String patientName,
  }) async {
    await Future.delayed(const Duration(milliseconds: 700));
    final relId = _genId('rel');
    final patId = _genId('p');
    final patient = Patient(
      id: patId,
      name: patientName,
      primaryRelativeId: relId,
    );
    final user = RelativeUser(
      id: relId,
      name: name,
      email: email,
      password: password,
      relativeType: RelativeType.primary,
      patientId: patId,
    );
    _patients.add(patient);
    _users.add(user);
    _currentUser = user;
    return user;
  }

  void logout() => _currentUser = null;

  // ── CAREGIVER ─────────────────────────────────────────────────────────────

  List<Patient> getCaregiverPatients(String caregiverId) =>
      _patients.where((p) => p.assignedCaregiverId == caregiverId).toList();

  // ── RELATIVE ──────────────────────────────────────────────────────────────

  Patient? getPatient(String patientId) {
    try {
      return _patients.firstWhere((p) => p.id == patientId);
    } catch (_) {
      return null;
    }
  }

  List<CaregiverUser> getAvailableCaregivers() => _users
      .whereType<CaregiverUser>()
      .where((cg) => cg.assignedPatientIds.length < 4 && cg.cvVerified)
      .toList();

  CaregiverUser? getCaregiverById(String id) {
    try {
      return _users.whereType<CaregiverUser>().firstWhere((u) => u.id == id);
    } catch (_) {
      return null;
    }
  }

  bool assignCaregiverToPatient(String patientId, String caregiverId) {
    final pi = _patients.indexWhere((p) => p.id == patientId);
    if (pi == -1) return false;
    final patient = _patients[pi];
    if (patient.assignedCaregiverId != null) return false;
    final ci = _users.indexWhere((u) => u.id == caregiverId);
    if (ci == -1) return false;
    final cg = _users[ci] as CaregiverUser;
    if (cg.assignedPatientIds.length >= 4) return false;
    _patients[pi] = patient.copyWith(assignedCaregiverId: caregiverId);
    _users[ci] =
        cg.copyWith(assignedPatientIds: [...cg.assignedPatientIds, patientId]);
    return true;
  }

  bool removeCaregiverFromPatient(String patientId) {
    final pi = _patients.indexWhere((p) => p.id == patientId);
    if (pi == -1) return false;
    final patient = _patients[pi];
    if (patient.assignedCaregiverId == null) return false;
    final cgId = patient.assignedCaregiverId!;
    final ci = _users.indexWhere((u) => u.id == cgId);
    if (ci != -1) {
      final cg = _users[ci] as CaregiverUser;
      _users[ci] = cg.copyWith(
        assignedPatientIds:
            cg.assignedPatientIds.where((id) => id != patientId).toList(),
      );
    }
    _patients[pi] = patient.copyWith(clearCaregiver: true);
    return true;
  }

  bool addSecondaryRelative(
    String patientId, {
    required String name,
    required String email,
    required String password,
  }) {
    final pi = _patients.indexWhere((p) => p.id == patientId);
    if (pi == -1) return false;
    final relId = _genId('rel');
    final rel = RelativeUser(
      id: relId,
      name: name,
      email: email,
      password: password,
      relativeType: RelativeType.secondary,
      patientId: patientId,
    );
    _users.add(rel);
    final patient = _patients[pi];
    _patients[pi] = patient.copyWith(
        secondaryRelativeIds: [...patient.secondaryRelativeIds, relId]);
    return true;
  }

  List<RelativeUser> getPatientRelatives(String patientId) => _users
      .whereType<RelativeUser>()
      .where((r) => r.patientId == patientId)
      .toList();

  // ── ADMIN ─────────────────────────────────────────────────────────────────

  List<AppUser> getAllUsers() => List.unmodifiable(_users);

  List<CaregiverUser> getPendingCvCaregivers() => _users
      .whereType<CaregiverUser>()
      .where((cg) => !cg.cvVerified && cg.cvFileName != null)
      .toList();

  bool verifyCaregiverCv(
    String caregiverId, {
    required double salary,
    required int yearsExperience,
  }) {
    final idx = _users.indexWhere((u) => u.id == caregiverId);
    if (idx == -1) return false;
    final cg = _users[idx] as CaregiverUser;
    _users[idx] = cg.copyWith(
        cvVerified: true, salary: salary, yearsExperience: yearsExperience);
    return true;
  }

  bool deleteUser(String userId) {
    final idx = _users.indexWhere((u) => u.id == userId);
    if (idx == -1) return false;
    _users.removeAt(idx);
    return true;
  }

  bool changeRelativeType(String relativeId, RelativeType newType) {
    final idx = _users.indexWhere((u) => u.id == relativeId);
    if (idx == -1 || _users[idx] is! RelativeUser) return false;
    final rel = _users[idx] as RelativeUser;
    _users[idx] = rel.copyWith(relativeType: newType);
    return true;
  }

  int get totalUsersCount => _users.length;
  int get pendingCvCount =>
      _users.whereType<CaregiverUser>().where((cg) => !cg.cvVerified).length;
  int get totalPatientsCount => _patients.length;
}
