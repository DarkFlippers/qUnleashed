import 'package:flutter/material.dart';

import '../../../theme.dart';

class ArchiveHeader extends StatelessWidget {
  const ArchiveHeader({
    super.key,
    required this.deviceName,
    required this.searchOpen,
    required this.searchController,
    required this.onToggleSearch,
    required this.onQueryChanged,
    required this.onSync,
    required this.syncing,
    required this.canSync,
  });

  final String deviceName;
  final bool searchOpen;
  final TextEditingController searchController;
  final VoidCallback onToggleSearch;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onSync;
  final bool syncing;
  final bool canSync;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Archive',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                deviceName,
                style: TextStyle(fontSize: 13, color: colors.textMuted),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Sync',
                onPressed: canSync && !syncing ? onSync : null,
                icon: syncing
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.accent,
                        ),
                      )
                    : Icon(Icons.sync, color: colors.textPrimary),
              ),
              IconButton(
                tooltip: 'Search',
                onPressed: onToggleSearch,
                icon: Icon(
                  searchOpen ? Icons.close : Icons.search,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          if (searchOpen) ...[
            const SizedBox(height: 4),
            TextField(
              controller: searchController,
              autofocus: true,
              onChanged: onQueryChanged,
              decoration: InputDecoration(
                hintText: 'Search keys',
                prefixIcon: Icon(Icons.search, color: colors.textMuted),
                filled: true,
                fillColor: colors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
