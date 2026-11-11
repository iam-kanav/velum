import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/library_notifier.dart';

/// Ask for the storage access a scan needs. If it's refused, says so on
/// screen and returns false.
Future<bool> requestStorageAccess(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final library = context.read<LibraryNotifier>();
  if (await library.requestStoragePermission()) return true;
  messenger.showSnackBar(
    const SnackBar(
      content: Text('Storage permission is required to scan for books'),
      behavior: SnackBarBehavior.floating,
    ),
  );
  return false;
}
