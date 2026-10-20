import 'package:flutter/material.dart';
import '../../models/rider_profile.dart';
import '../../services/sms_service.dart';
import '../../services/storage.dart';
import '../theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({required this.storage, super.key});

  final Storage storage;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _allergiesController;
  late final TextEditingController _conditionsController;
  late final TextEditingController _vehicleController;
  late final TextEditingController _notesController;
  String _selectedBloodGroup = 'O+';

  static const List<String> bloodGroups = [
    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'Unknown'
  ];

  @override
  void initState() {
    super.initState();
    final profile = widget.storage.getProfile();
    _nameController = TextEditingController(text: profile.name);
    _allergiesController = TextEditingController(text: profile.allergies);
    _conditionsController = TextEditingController(text: profile.medicalConditions);
    _vehicleController = TextEditingController(text: profile.vehicleNumber);
    _notesController = TextEditingController(text: profile.emergencyNotes);
    if (bloodGroups.contains(profile.bloodGroup)) {
      _selectedBloodGroup = profile.bloodGroup;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _allergiesController.dispose();
    _conditionsController.dispose();
    _vehicleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final updated = RiderProfile(
      name: _nameController.text.trim(),
      bloodGroup: _selectedBloodGroup,
      allergies: _allergiesController.text.trim(),
      medicalConditions: _conditionsController.text.trim(),
      vehicleNumber: _vehicleController.text.trim(),
      emergencyNotes: _notesController.text.trim(),
    );
    await widget.storage.saveProfile(updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: SafeHelmTheme.successGreen,
          content: Text('Rider Medical ID & Profile saved successfully!'),
        ),
      );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: SafeHelmTheme.primary.withOpacity(0.2),
                    child: const Icon(Icons.medical_services_outlined,
                        color: SafeHelmTheme.primaryLight, size: 30),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RIDER MEDICAL ID',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Appended to autonomous emergency SMS alerts for first responders.',
                          style: TextStyle(fontSize: 12, color: SafeHelmTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Form Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),

                  // Blood Group Dropdown
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Blood Group',
                      prefixIcon: Icon(Icons.bloodtype_outlined),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedBloodGroup,
                        isDense: true,
                        dropdownColor: SafeHelmTheme.surfaceHighlight,
                        items: bloodGroups.map((bg) {
                          return DropdownMenuItem<String>(
                            value: bg,
                            child: Text(
                              bg,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedBloodGroup = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: _allergiesController,
                    decoration: const InputDecoration(
                      labelText: 'Allergies (e.g. Penicillin, None)',
                      prefixIcon: Icon(Icons.warning_amber_outlined),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: _conditionsController,
                    decoration: const InputDecoration(
                      labelText: 'Medical Conditions (e.g. Diabetic, Asthma)',
                      prefixIcon: Icon(Icons.favorite_border),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: _vehicleController,
                    decoration: const InputDecoration(
                      labelText: 'Vehicle Registration Number',
                      prefixIcon: Icon(Icons.two_wheeler_outlined),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Emergency Medical Notes',
                      prefixIcon: Icon(Icons.note_alt_outlined),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Live SMS Preview Card
          Card(
            color: SafeHelmTheme.surfaceHighlight,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.sms_outlined, color: SafeHelmTheme.primaryLight, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'LIVE EMERGENCY SMS PREVIEW',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: SafeHelmTheme.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: SafeHelmTheme.cardBorder),
                    ),
                    child: Text(
                      EmergencyMessageBuilder().build(
                        type: 'ACCIDENT',
                        time: DateTime.now(),
                        latitude: 19.0760,
                        longitude: 72.8777,
                        test: false,
                        locationSource: 'gps_fresh',
                        riderName: _nameController.text.trim().isNotEmpty
                            ? _nameController.text.trim()
                            : 'Saif (Rider)',
                        bloodGroup: _selectedBloodGroup,
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: SafeHelmTheme.textBright,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Save Button
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: SafeHelmTheme.primary,
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: _saveProfile,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save Medical Profile'),
          ),
        ],
      ),
    );
  }
}
