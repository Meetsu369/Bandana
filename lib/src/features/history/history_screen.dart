import 'package:flutter/material.dart';

import 'package:bandana/src/core/theme/app_typography.dart';
import 'package:bandana/src/shared/widgets/feedback/empty_state.dart';
import 'package:bandana/src/shared/widgets/buttons/primary_button.dart';

/// History screen – placeholder for recorded sessions.
///
/// Displays an empty state until session history is implemented.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, this.onStartRecording});

  final VoidCallback? onStartRecording;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'History',
          style: AppTypography.h2For(brightness),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: EmptyState.noSessions(
            action: PrimaryButton(
              label: 'Start Recording',
              leadingIcon: Icons.fiber_manual_record,
              onPressed: onStartRecording,
            ),
          ),
        ),
      ),
    );
  }
}