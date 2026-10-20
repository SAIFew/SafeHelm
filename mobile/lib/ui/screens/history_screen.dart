import 'package:flutter/material.dart';
import '../../models/emergency.dart';
import '../../services/native_journal_service.dart';
import '../../services/storage.dart';
import '../theme.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({required this.storage, super.key});

  final Storage storage;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final NativeJournalService _journal = NativeJournalService();

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SafeHelmTheme.surface,
        title: const Text('Clear Incident History?'),
        content: const Text(
          'This will permanently erase all local event records and audit logs.',
          style: TextStyle(color: SafeHelmTheme.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: SafeHelmTheme.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SafeHelmTheme.emergencyRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear History'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.storage.clearHistory();
      setState(() {});
    }
  }

  Future<void> _showDispatchDetails(EventRecord item) async {
    if (item.incidentId == null) return;

    final dispatches = await _journal.getDispatches(item.incidentId!);

    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SafeHelmTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'INCIDENT DISPATCH AUDIT',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.incidentId!,
                      style: const TextStyle(fontSize: 11, color: SafeHelmTheme.textMuted, fontFamily: 'monospace'),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20, color: SafeHelmTheme.textMuted),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (dispatches.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    item.status.toLowerCase().contains('cancel')
                        ? 'Alert was cancelled before contact dispatch.'
                        : 'No individual SMS radio records found for this incident.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: SafeHelmTheme.textMuted),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: dispatches.length,
                  separatorBuilder: (_, __) => const Divider(color: SafeHelmTheme.cardBorder, height: 16),
                  itemBuilder: (context, idx) {
                    final d = dispatches[idx];
                    final isSuccess = d.status == 'SENT_RADIO_CONFIRMED';
                    final isSubmitted = d.status == 'SUBMITTED_TO_RIL';
                    final statusColor = isSuccess
                        ? SafeHelmTheme.successGreen
                        : (isSubmitted ? SafeHelmTheme.warningAmber : SafeHelmTheme.emergencyRed);

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isSuccess
                              ? Icons.cell_tower
                              : (isSubmitted ? Icons.hourglass_top : Icons.error_outline),
                          size: 20,
                          color: statusColor,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.recipientName != null && d.recipientName!.isNotEmpty
                                    ? '${d.recipientName} (${d.recipientPhone})'
                                    : d.recipientPhone,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Status: ${d.status} • Parts: ${d.partsConfirmed}/${d.partsTotal}',
                                style: TextStyle(fontSize: 11, color: statusColor),
                              ),
                              if (d.radioResultCode != null)
                                Text(
                                  'Radio Result Code: ${d.radioResultCode}',
                                  style: const TextStyle(fontSize: 10, color: SafeHelmTheme.textMuted),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.storage.history();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'INCIDENT AUDIT LOG (${history.length})',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
              if (history.isNotEmpty)
                TextButton.icon(
                  onPressed: _clearHistory,
                  icon: const Icon(Icons.delete_sweep, size: 18, color: SafeHelmTheme.textMuted),
                  label: const Text('Clear', style: TextStyle(color: SafeHelmTheme.textMuted)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (history.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history_toggle_off, size: 64, color: SafeHelmTheme.textMuted.withOpacity(0.5)),
                    const SizedBox(height: 16),
                    const Text(
                      'No Recorded Incidents',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Every triggered crash, manual SOS, cancellation, and autonomous dispatch is recorded here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: SafeHelmTheme.textMuted),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: history.length,
                itemBuilder: (context, i) {
                  final item = history[i];
                  final isCancelled = item.status.toLowerCase().contains('cancel');
                  final isDispatched = item.status.toLowerCase().contains('request') || item.status.toLowerCase().contains('success');

                  Color statusColor;
                  IconData statusIcon;

                  if (isCancelled) {
                    statusColor = SafeHelmTheme.textMuted;
                    statusIcon = Icons.cancel_outlined;
                  } else if (isDispatched) {
                    statusColor = SafeHelmTheme.successGreen;
                    statusIcon = Icons.check_circle_outline;
                  } else {
                    statusColor = SafeHelmTheme.emergencyRed;
                    statusIcon = Icons.error_outline;
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: item.incidentId != null ? () => _showDispatchDetails(item) : null,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(statusIcon, color: statusColor, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      item.type.toUpperCase(),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        item.status.toUpperCase(),
                                        style: TextStyle(
                                          color: statusColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (item.incidentId != null) ...[
                                      const SizedBox(width: 6),
                                      const Icon(Icons.chevron_right, size: 16, color: SafeHelmTheme.textMuted),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Time: ${item.time.toLocal().toString().split('.').first}',
                              style: const TextStyle(fontSize: 12, color: SafeHelmTheme.textMuted),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  'Recipients: ${item.recipients} • Location: ${item.locationSource}',
                                  style: const TextStyle(fontSize: 12, color: SafeHelmTheme.textMuted),
                                ),
                              ],
                            ),
                          ],
                        ),
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

