import 'package:flutter/material.dart';

import '../theme.dart';

/// Name cell with the design's gold initials avatar.
Widget saNameCell(String name) {
  return Row(
    children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: SuperAdminTheme.goldSoft,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Center(
          child: Text(
            saInitials(name),
            style: SuperAdminTheme.inter(
              11,
              weight: FontWeight.w700,
              color: SuperAdminTheme.goldDim,
            ),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          name,
          overflow: TextOverflow.ellipsis,
          style: SuperAdminTheme.inter(12.8, weight: FontWeight.w600),
        ),
      ),
    ],
  );
}

/// Plain text cell with ellipsis.
Widget saTextCell(String value) {
  return Text(
    value,
    overflow: TextOverflow.ellipsis,
    style: SuperAdminTheme.inter(12.8),
  );
}
