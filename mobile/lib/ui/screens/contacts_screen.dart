import 'package:flutter/material.dart';
import '../../models/contact.dart';
import '../../services/contact_book.dart';
import '../../services/storage.dart';
import '../theme.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({required this.storage, super.key});

  final Storage storage;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  Future<void> _showContactDialog([int? index]) async {
    final book = ContactBook(widget.storage.contacts());
    final existing = index == null ? null : book.contacts[index];
    final nameController = TextEditingController(text: existing?.name);
    final phoneController = TextEditingController(text: existing?.phone);
    String? errorMessage;

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: SafeHelmTheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(
                  index == null ? Icons.person_add_alt_1 : Icons.edit,
                  color: SafeHelmTheme.primaryLight,
                ),
                const SizedBox(width: 10),
                Text(index == null ? 'Add Emergency Contact' : 'Edit Contact'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Contact Name (e.g. Mom, Brother)',
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone (+ country code, e.g. +91...)',
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    errorMessage!,
                    style: const TextStyle(color: SafeHelmTheme.emergencyRed, fontSize: 12),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel', style: TextStyle(color: SafeHelmTheme.textMuted)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: SafeHelmTheme.primary),
                onPressed: () async {
                  final contact = EmergencyContact(
                    name: nameController.text.trim(),
                    phone: phoneController.text.trim(),
                    enabled: existing?.enabled ?? true,
                    priority: (index ?? book.contacts.length) + 1,
                  );
                  errorMessage = book.validate(contact, replacing: index);
                  if (errorMessage != null) {
                    setDialogState(() {});
                    return;
                  }
                  if (index == null) {
                    book.add(contact);
                  } else {
                    book.replace(index, contact);
                  }
                  await widget.storage.saveContacts(book.contacts);
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  setState(() {});
                },
                child: const Text('Save Contact'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _removeContact(int index) async {
    final book = ContactBook(widget.storage.contacts());
    book.remove(index);
    await widget.storage.saveContacts(book.contacts);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.storage.contacts();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'EMERGENCY RECIPIENTS (${all.length}/5)',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
              if (all.length < 5)
                TextButton.icon(
                  onPressed: () => _showContactDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Contact'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (all.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.contact_phone_outlined, size: 64, color: SafeHelmTheme.textMuted.withOpacity(0.5)),
                    const SizedBox(height: 16),
                    const Text(
                      'No Emergency Contacts Configured',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add up to 5 priority contacts who will receive your GPS coordinates during severe impacts.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: SafeHelmTheme.textMuted),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => _showContactDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add First Contact'),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: all.length,
                itemBuilder: (context, i) {
                  final x = all[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: CircleAvatar(
                        backgroundColor: SafeHelmTheme.surfaceHighlight,
                        child: Text(
                          '#${x.priority}',
                          style: const TextStyle(
                            color: SafeHelmTheme.primaryLight,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(x.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(x.phone, style: const TextStyle(color: SafeHelmTheme.textMuted)),
                      onTap: () => _showContactDialog(i),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: x.enabled,
                            activeColor: SafeHelmTheme.successGreen,
                            onChanged: (v) async {
                              final book = ContactBook(all);
                              book.setEnabled(i, v);
                              await widget.storage.saveContacts(book.contacts);
                              setState(() {});
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: SafeHelmTheme.emergencyRed),
                            tooltip: 'Delete contact',
                            onPressed: () => _removeContact(i),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
