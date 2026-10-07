import 'package:flutter/material.dart';

import '../theme.dart';
import 'badge.dart';

/// Row card of the design's lists (avatar + title/subtitle + badge + kebab).
class BoItemCard extends StatelessWidget {
  const BoItemCard({
    super.key,
    required this.avatarText,
    required this.title,
    required this.subtitle,
    required this.status,
    this.onKebab,
  });

  final String avatarText;
  final String title;
  final String subtitle;
  final String status;
  final VoidCallback? onKebab;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: BackofficeTheme.surface,
        border: Border.all(color: BackofficeTheme.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: BackofficeTheme.greenSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              avatarText,
              style: BackofficeTheme.inter(
                12.5,
                weight: FontWeight.w700,
                color: BackofficeTheme.green,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BackofficeTheme.inter(
                    13,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BackofficeTheme.inter(
                    11,
                    color: BackofficeTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              BoBadge(status: status),
              const SizedBox(height: 4),
              InkWell(
                onTap: onKebab,
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 26,
                  height: 22,
                  child: Icon(
                    Icons.more_horiz_rounded,
                    size: 17,
                    color: BackofficeTheme.muted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
