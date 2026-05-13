enum UserRole { caregiver, relative, admin }

enum RelativeType { primary, secondary }

class AppUser {
  final String id;
  final String name;
  final String email;
  final String password;
  final UserRole role;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.password,
    required this.role,
  });
}

class CaregiverUser extends AppUser {
  final int age;
  final String nationalId;
  final String? cvFileName;
  final String? nationalIdPhotoName;
  final bool cvVerified;
  final double salary;
  final int yearsExperience;
  final List<String> assignedPatientIds;

  CaregiverUser({
    required super.id,
    required super.name,
    required super.email,
    required super.password,
    required this.age,
    required this.nationalId,
    this.cvFileName,
    this.nationalIdPhotoName,
    this.cvVerified = false,
    this.salary = 0.0,
    this.yearsExperience = 0,
    List<String>? assignedPatientIds,
  }) : assignedPatientIds = assignedPatientIds ?? const [],
       super(role: UserRole.caregiver);

  CaregiverUser copyWith({
    bool? cvVerified,
    double? salary,
    int? yearsExperience,
    List<String>? assignedPatientIds,
    String? cvFileName,
    String? nationalIdPhotoName,
  }) {
    return CaregiverUser(
      id: id,
      name: name,
      email: email,
      password: password,
      age: age,
      nationalId: nationalId,
      cvFileName: cvFileName ?? this.cvFileName,
      nationalIdPhotoName: nationalIdPhotoName ?? this.nationalIdPhotoName,
      cvVerified: cvVerified ?? this.cvVerified,
      salary: salary ?? this.salary,
      yearsExperience: yearsExperience ?? this.yearsExperience,
      assignedPatientIds: assignedPatientIds ?? this.assignedPatientIds,
    );
  }
}

class RelativeUser extends AppUser {
  final RelativeType relativeType;
  final String? patientId;

  RelativeUser({
    required super.id,
    required super.name,
    required super.email,
    required super.password,
    required this.relativeType,
    this.patientId,
  }) : super(role: UserRole.relative);

  RelativeUser copyWith({RelativeType? relativeType, String? patientId}) {
    return RelativeUser(
      id: id,
      name: name,
      email: email,
      password: password,
      relativeType: relativeType ?? this.relativeType,
      patientId: patientId ?? this.patientId,
    );
  }
}

class AdminUser extends AppUser {
  AdminUser({
    required super.id,
    required super.name,
    required super.email,
    required super.password,
  }) : super(role: UserRole.admin);
}

class Patient {
  final String id;
  final String name;
  final String primaryRelativeId;
  final String? assignedCaregiverId;
  final List<String> secondaryRelativeIds;
  final String? proofOfRelation;

  Patient({
    required this.id,
    required this.name,
    required this.primaryRelativeId,
    this.assignedCaregiverId,
    List<String>? secondaryRelativeIds,
    this.proofOfRelation,
  }) : secondaryRelativeIds = secondaryRelativeIds ?? const [];

  Patient copyWith({
    String? assignedCaregiverId,
    List<String>? secondaryRelativeIds,
    String? proofOfRelation,
    bool clearCaregiver = false,
  }) {
    return Patient(
      id: id,
      name: name,
      primaryRelativeId: primaryRelativeId,
      assignedCaregiverId: clearCaregiver
          ? null
          : (assignedCaregiverId ?? this.assignedCaregiverId),
      secondaryRelativeIds: secondaryRelativeIds ?? this.secondaryRelativeIds,
      proofOfRelation: proofOfRelation ?? this.proofOfRelation,
    );
  }
}
