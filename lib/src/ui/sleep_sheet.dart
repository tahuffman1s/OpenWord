import 'package:flutter/material.dart';

import '../data/marks.dart';
import '../model/sleep_policy.dart';

/// Choosing how new verses are timed against sleep, and when evening
/// and morning are for this reader.
Future<void> showSleepPolicySheet(BuildContext context, ReadingStore reading) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: AnimatedBuilder(
        animation: reading,
        builder: (context, _) {
          final theme = Theme.of(context);
          final policy = reading.sleepPolicy;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                  child: Text(
                    'Sleep and new verses',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    'A night’s sleep soon after learning helps memory settle: '
                    'in studies, a verse learnt in the evening and asked for '
                    'next morning is relearnt faster and kept longer. The app '
                    'can time new verses that way, and measure whether it '
                    'works for you.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                RadioGroup<SleepMode>(
                  groupValue: policy.mode,
                  onChanged: (mode) {
                    if (mode != null) {
                      reading.setSleepPolicy(policy.copyWith(mode: mode));
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final mode in SleepMode.values)
                        RadioListTile<SleepMode>(
                          value: mode,
                          title: Text(mode.label),
                          subtitle: Text(mode.description),
                        ),
                    ],
                  ),
                ),
                if (policy.mode != SleepMode.off) ...[
                  _HourTile(
                    key: const Key('evening'),
                    title: 'Evening begins',
                    subtitle: 'Night verses are offered from here.',
                    hour: policy.eveningStart,
                    hours: [for (var h = 16; h <= 23; h++) h],
                    onChanged: (h) => reading.setSleepPolicy(
                      policy.copyWith(eveningStart: h),
                    ),
                  ),
                  _HourTile(
                    key: const Key('morning'),
                    title: 'Morning ends',
                    subtitle: 'Last night’s verses are best recalled before.',
                    hour: policy.morningEnd,
                    hours: [for (var h = 7; h <= 13; h++) h],
                    onChanged: (h) =>
                        reading.setSleepPolicy(policy.copyWith(morningEnd: h)),
                  ),
                ],
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _HourTile extends StatelessWidget {
  const _HourTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.hour,
    required this.hours,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final int hour;
  final List<int> hours;
  final ValueChanged<int> onChanged;

  static String label(int hour) => hour == 0
      ? '12 am'
      : hour < 12
      ? '$hour am'
      : hour == 12
      ? '12 pm'
      : '${hour - 12} pm';

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: DropdownButton<int>(
      value: hour,
      items: [
        for (final h in hours)
          DropdownMenuItem(value: h, child: Text(label(h))),
      ],
      onChanged: (h) {
        if (h != null) onChanged(h);
      },
    ),
  );
}

/// The hour as a reader reads it: "7 pm".
String hourLabel(int hour) => _HourTile.label(hour);
