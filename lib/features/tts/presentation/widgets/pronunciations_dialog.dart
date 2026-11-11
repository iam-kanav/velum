import 'package:flutter/material.dart';
import 'package:velum/core/theme/app_colors.dart';
import '../../data/models/pronunciation.dart';
import '../providers/tts_notifier.dart';
import 'package:velum/core/motion/motion.dart';

const Color _accent = AppColors.accent;

/// List of words read aloud differently from how they're written, where the
/// reader adds, edits and removes them.
Future<void> showPronunciationsDialog(
  BuildContext context,
  TtsNotifier tts, {
  required Color textColor,
  required Color backgroundColor,
}) {
  return showMotionDialog<void>(
    context: context,
    builder: (ctx) => ListenableBuilder(
      listenable: tts,
      builder: (ctx, _) {
        final rules = tts.pronunciations;

        Future<void> edit([int? index]) async {
          final result = await _showRuleEditor(
            ctx,
            index == null ? null : rules[index],
            textColor: textColor,
            backgroundColor: backgroundColor,
          );
          if (result == null) return;
          final updated = [...rules];
          if (index == null) {
            updated.add(result);
          } else {
            updated[index] = result;
          }
          await tts.updatePronunciations(updated);
        }

        return AlertDialog(
          backgroundColor: backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            'Pronunciations',
            style: TextStyle(
              color: textColor,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'These words are read aloud as you set them here. '
                  'The book itself doesn\'t change.',
                  style: TextStyle(
                    color: textColor.withAlpha(150),
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 12),
                if (rules.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No words yet.',
                      style: TextStyle(color: textColor.withAlpha(150)),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: rules.length,
                      itemBuilder: (_, i) => _RuleRow(
                        rule: rules[i],
                        textColor: textColor,
                        onTap: () => edit(i),
                        onRemove: () =>
                            tts.updatePronunciations([...rules]..removeAt(i)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: edit,
              icon: const Icon(Icons.add, size: 18, color: _accent),
              label: const Text('Add word', style: TextStyle(color: _accent)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Done'),
            ),
          ],
        );
      },
    ),
  );
}

class _RuleRow extends StatelessWidget {
  final Pronunciation rule;
  final Color textColor;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _RuleRow({
    required this.rule,
    required this.textColor,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: rule.written),
                    TextSpan(
                      text: '  →  ',
                      style: TextStyle(color: textColor.withAlpha(120)),
                    ),
                    TextSpan(
                      text: rule.spoken,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                style: TextStyle(color: textColor, fontSize: 14),
              ),
            ),
            IconButton(
              onPressed: onRemove,
              tooltip: 'Remove',
              icon: Icon(
                Icons.close,
                size: 18,
                color: textColor.withAlpha(150),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Add a word (when [rule] is null) or edit one. Returns null on cancel.
Future<Pronunciation?> _showRuleEditor(
  BuildContext context,
  Pronunciation? rule, {
  required Color textColor,
  required Color backgroundColor,
}) {
  return showMotionDialog<Pronunciation>(
    context: context,
    builder: (ctx) => _RuleEditor(
      rule: rule,
      textColor: textColor,
      backgroundColor: backgroundColor,
    ),
  );
}

/// A widget rather than a builder, so the text controllers are disposed of
/// once the dialog has closed.
class _RuleEditor extends StatefulWidget {
  final Pronunciation? rule;
  final Color textColor;
  final Color backgroundColor;

  const _RuleEditor({
    required this.rule,
    required this.textColor,
    required this.backgroundColor,
  });

  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late final _written = TextEditingController(text: widget.rule?.written);
  late final _spoken = TextEditingController(text: widget.rule?.spoken);
  late final _fields = Listenable.merge([_written, _spoken]);

  @override
  void dispose() {
    _written.dispose();
    _spoken.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, String hint) => InputDecoration(
    labelText: label,
    hintText: hint,
    hintStyle: TextStyle(color: widget.textColor.withAlpha(90)),
    labelStyle: TextStyle(color: widget.textColor.withAlpha(150)),
    floatingLabelStyle: const TextStyle(color: _accent),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: widget.textColor.withAlpha(60)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _accent, width: 2),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final rule = widget.rule;
    final textColor = widget.textColor;
    return ListenableBuilder(
      listenable: _fields,
      builder: (ctx, _) {
        final result = Pronunciation(
          _written.text.trim(),
          _spoken.text.trim(),
        );
        void submit() {
          if (result.isComplete) Navigator.of(ctx).pop(result);
        }

        return AlertDialog(
          backgroundColor: widget.backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            rule == null ? 'Add word' : 'Edit word',
            style: TextStyle(
              color: textColor,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _written,
                autofocus: rule == null,
                textInputAction: TextInputAction.next,
                style: TextStyle(color: textColor, fontSize: 15.5),
                decoration: _decoration('Written as', 'majestic'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _spoken,
                onSubmitted: (_) => submit(),
                style: TextStyle(color: textColor, fontSize: 15.5),
                decoration: _decoration('Read as', 'beautiful'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: textColor.withAlpha(170)),
              ),
            ),
            FilledButton(
              onPressed: result.isComplete ? submit : null,
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
              ),
              child: Text(rule == null ? 'Add' : 'Save'),
            ),
          ],
        );
      },
    );
  }
}
