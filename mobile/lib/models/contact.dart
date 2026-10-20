class EmergencyContact {
  const EmergencyContact({required this.name, required this.phone, required this.enabled, required this.priority});
  final String name, phone; final bool enabled; final int priority;
  String get normalizedPhone => phone.replaceAll(RegExp(r'[ ()-]'), '');
  bool get isValid => name.trim().isNotEmpty && RegExp(r'^\+?[0-9]{7,15}$').hasMatch(normalizedPhone);
  Map<String,dynamic> toJson()=>{'name':name,'phone':phone,'enabled':enabled,'priority':priority};
  factory EmergencyContact.fromJson(Map<String,dynamic> j)=>EmergencyContact(name:j['name'] as String,phone:j['phone'] as String,enabled:j['enabled'] as bool,priority:j['priority'] as int);
}
