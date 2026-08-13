import 'enums.dart';

/// Represents the child/person (spec 9.1). Never stores today's visit
/// reason or vitals — that data belongs to [Visit] and vitals records.
class Patient {
  final String id;
  final String patientNumber;
  final String firstName;
  final String middleName;
  final String lastName;
  final DateTime birthdate;
  final Sex sex;
  final String address;
  final String guardianName;
  final String guardianContact;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String updatedBy;

  Patient({
    required this.id,
    required this.patientNumber,
    required this.firstName,
    this.middleName = '',
    required this.lastName,
    required this.birthdate,
    required this.sex,
    required this.address,
    required this.guardianName,
    required this.guardianContact,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  String get fullName {
    final middle = middleName.trim().isEmpty ? '' : ' ${middleName.trim()[0]}.';
    return '$firstName$middle $lastName';
  }

  /// Initials only — used on staff-facing queue lists so full names are not
  /// repeated unnecessarily (spec section 7, "LLM Rule 7").
  String get initials {
    final f = firstName.isNotEmpty ? firstName[0] : '';
    final l = lastName.isNotEmpty ? lastName[0] : '';
    return '$f$l'.toUpperCase();
  }

  int get ageInYears {
    final now = DateTime.now();
    var age = now.year - birthdate.year;
    if (now.month < birthdate.month ||
        (now.month == birthdate.month && now.day < birthdate.day)) {
      age--;
    }
    return age;
  }

  int get ageInMonths {
    final now = DateTime.now();
    return (now.year - birthdate.year) * 12 + (now.month - birthdate.month);
  }

  String get ageDisplay {
    final months = ageInMonths;
    if (months < 24) return '$months mo';
    return '$ageInYears yr';
  }

  Patient copyWith({
    String? firstName,
    String? middleName,
    String? lastName,
    DateTime? birthdate,
    Sex? sex,
    String? address,
    String? guardianName,
    String? guardianContact,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return Patient(
      id: id,
      patientNumber: patientNumber,
      firstName: firstName ?? this.firstName,
      middleName: middleName ?? this.middleName,
      lastName: lastName ?? this.lastName,
      birthdate: birthdate ?? this.birthdate,
      sex: sex ?? this.sex,
      address: address ?? this.address,
      guardianName: guardianName ?? this.guardianName,
      guardianContact: guardianContact ?? this.guardianContact,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}
