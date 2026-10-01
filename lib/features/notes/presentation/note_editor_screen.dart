import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:velum/core/theme/app_colors.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../library/presentation/providers/library_notifier.dart';
import '../../settings/presentation/providers/settings_notifier.dart';
import '../data/note_service.dart';

/// Paste a text ("New File") — e.g. a whole Google Doc — so it can be read
/// and listened to like a book. Pass [path] to edit an existing one.
class NoteEditorScreen extends StatefulWidget {
  final String? path;

  const NoteEditorScreen({super.key, this.path});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final WebViewController _controller;
  final _notes = const NoteService();
  Completer<Map<String, dynamic>>? _pendingDoc;
  bool _dirty = false;
  bool _saving = false;

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  @override
  void initState() {
    super.initState();
    final theme = context.read<SettingsNotifier>().settings.readerTheme;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(theme.backgroundColor)
      ..addJavaScriptChannel('Editor', onMessageReceived: _onMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _onLoaded(),
          // Links in pasted text must not navigate away from the editor.
          onNavigationRequest: (request) =>
              request.url.contains('editor.html')
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent,
        ),
      )
      ..loadFlutterAsset('assets/js/editor.html');
  }

  Future<void> _onLoaded() async {
    final theme = context.read<SettingsNotifier>().settings.readerTheme;
    await _controller.runJavaScript(
      "window.setTheme('${_hex(theme.textColor)}', "
      "'${_hex(theme.backgroundColor)}', "
      "'${_hex(theme.textColor)}73');",
    );
    final path = widget.path;
    if (path != null) {
      final note = await _notes.load(path);
      if (note != null) {
        await _controller.runJavaScript(
          'window.setDoc(${jsonEncode(note.html)});',
        );
      }
    }
    await _controller.runJavaScript('window.focusEditor();');
  }

  void _onMessage(JavaScriptMessage message) {
    final text = message.message;
    if (text == 'dirty') {
      _dirty = true;
    } else if (text.startsWith('doc:')) {
      _pendingDoc?.complete(jsonDecode(text.substring(4)) as Map<String, dynamic>);
      _pendingDoc = null;
    }
  }

  Future<void> _done() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // The page may answer before runJavaScript returns, so hold the
      // completer locally.
      final pending = _pendingDoc = Completer();
      await _controller.runJavaScript('window.getDoc();');
      final doc = await pending.future.timeout(const Duration(seconds: 5));
      final text = (doc['text'] as String? ?? '').trim();
      if (text.isEmpty) {
        _showMessage('Paste something first');
        return;
      }
      // Named after its first line, shortened.
      var title = text.split('\n').first.trim();
      if (title.length > 60) title = '${title.substring(0, 57).trimRight()}…';

      final path = await _notes.save(
        Note(title, doc['html'] as String),
        epubPath: widget.path,
      );
      if (!mounted) return;
      await context.read<LibraryNotifier>().saveNote(path, title);
      if (!mounted) return;
      _dirty = false;
      if (widget.path == null) {
        // New file: open it straight away, ready to read or listen to.
        context.pushReplacement('/reader?path=${Uri.encodeComponent(path)}');
      } else {
        context.pop(true);
      }
    } catch (e) {
      debugPrint('Saving note failed: $e');
      _showMessage("Couldn't save this file");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _confirmDiscard() async {
    final theme = context.read<SettingsNotifier>().settings.readerTheme;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.backgroundColor,
        title: Text(
          'Discard changes?',
          style: TextStyle(color: theme.textColor, fontSize: 18),
        ),
        content: Text(
          "Your changes to this file won't be saved.",
          style: TextStyle(color: theme.textColor.withAlpha(180)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      _dirty = false;
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<SettingsNotifier>().settings.readerTheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_dirty) {
          _confirmDiscard();
        } else {
          context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: theme.backgroundColor,
        appBar: AppBar(
          backgroundColor: theme.backgroundColor,
          foregroundColor: theme.textColor,
          elevation: 0,
          title: Text(
            widget.path == null ? 'New file' : 'Edit file',
            style: TextStyle(fontSize: 16, color: theme.textColor),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _saving ? null : _done,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Done'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: WebViewWidget(controller: _controller),
        ),
      ),
    );
  }
}
