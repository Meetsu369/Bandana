import 'package:flutter/material.dart';

import 'package:bandana/src/core/theme/app_colors.dart';
import 'package:bandana/src/core/theme/app_radius.dart';
import 'package:bandana/src/core/theme/app_spacing.dart';
import 'package:bandana/src/core/theme/app_typography.dart';
import 'package:bandana/src/features/settings/devices_screen.dart';
import 'package:bandana/src/shared/widgets/buttons/secondary_button.dart';
import 'package:bandana/src/shared/widgets/feedback/empty_state.dart';
import 'package:bandana/src/shared/widgets/section_header.dart';

/// Profile screen – lightweight entry point to settings and personal info.
///
/// Provides access to the existing SettingsScreen.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Profile',
          style: AppTypography.h2For(brightness),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            // Profile header
            SectionHeader(
              title: 'Your Profile',
              subtitle: 'Manage your personal information and preferences',
              leadingIcon: Icons.person_outline,
            ),
            const SizedBox(height: AppSpacing.md),
            // Placeholder for profile info
            EmptyState(
              icon: Icons.person_outline,
              title: 'Profile Coming Soon',
              description:
                  'Participant data, height, weight, and fitness goals will appear here.',
              action: SecondaryButton(
                label: 'My Bands',
                leadingIcon: Icons.watch_outlined,
                onPressed: () => _openDevices(context),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            // Quick actions
            SectionHeader(
              title: 'Quick Actions',
              leadingIcon: Icons.flash_on_outlined,
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildActionCard(
              context,
              title: 'My Bands',
              subtitle: 'Manage Wrist and Ankle sensors',
              icon: Icons.watch_outlined,
              onTap: () => _openDevices(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final inkColor = AppColors.ink(brightness);

    return Semantics(
      button: true,
      label: title,
      hint: subtitle,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(
            color: inkColor,
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.card,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: AppSpacing.buttonHeightSmall,
                  height: AppSpacing.buttonHeightSmall,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: AppRadius.smRadius,
                  ),
                  child: Icon(
                    icon,
                    color: theme.colorScheme.primary,
                    size: AppSpacing.iconSizeLarge,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTypography.bodyMediumFor(brightness).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        subtitle,
                        style: AppTypography.bodySmallFor(brightness),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openDevices(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const DevicesScreen(),
      ),
    );
  }
}