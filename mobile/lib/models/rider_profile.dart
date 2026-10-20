class RiderProfile {
  const RiderProfile({
    this.name = '',
    this.bloodGroup = '',
    this.allergies = '',
    this.medicalConditions = '',
    this.vehicleNumber = '',
    this.emergencyNotes = '',
  });

  final String name;
  final String bloodGroup;
  final String allergies;
  final String medicalConditions;
  final String vehicleNumber;
  final String emergencyNotes;

  bool get isEmpty =>
      name.isEmpty &&
      bloodGroup.isEmpty &&
      allergies.isEmpty &&
      medicalConditions.isEmpty &&
      vehicleNumber.isEmpty;

  Map<String, dynamic> toJson() => {
        'name': name,
        'bloodGroup': bloodGroup,
        'allergies': allergies,
        'medicalConditions': medicalConditions,
        'vehicleNumber': vehicleNumber,
        'emergencyNotes': emergencyNotes,
      };

  factory RiderProfile.fromJson(Map<String, dynamic> json) => RiderProfile(
        name: json['name'] as String? ?? '',
        bloodGroup: json['bloodGroup'] as String? ?? '',
        allergies: json['allergies'] as String? ?? '',
        medicalConditions: json['medicalConditions'] as String? ?? '',
        vehicleNumber: json['vehicleNumber'] as String? ?? '',
        emergencyNotes: json['emergencyNotes'] as String? ?? '',
      );

  RiderProfile copyWith({
    String? name,
    String? bloodGroup,
    String? allergies,
    String? medicalConditions,
    String? vehicleNumber,
    String? emergencyNotes,
  }) =>
      RiderProfile(
        name: name ?? this.name,
        bloodGroup: bloodGroup ?? this.bloodGroup,
        allergies: allergies ?? this.allergies,
        medicalConditions: medicalConditions ?? this.medicalConditions,
        vehicleNumber: vehicleNumber ?? this.vehicleNumber,
        emergencyNotes: emergencyNotes ?? this.emergencyNotes,
      );
}
