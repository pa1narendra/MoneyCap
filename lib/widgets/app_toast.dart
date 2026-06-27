import 'package:flutter/material.dart';

/// Show a short, non-blocking floating toast (a rounded pill with an icon).
///
/// Any currently visible OR queued message is cleared first, so toasts never
/// stack/queue behind each other (that queuing caused the perceived "delay" —
/// a new message had to wait out the previous one's full duration).
/// Floating + swipe-to-dismiss so the user can flick it away at any time.
void showToast(BuildContext context, String message, {bool isError = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 1800),
      behavior: SnackBarBehavior.floating,
      dismissDirection: DismissDirection.horizontal,
      backgroundColor: isError ? const Color(0xFFD32F2F) : const Color(0xFF2E2E33),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 6,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
  );
}
