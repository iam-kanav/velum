import 'package:flutter/material.dart';
import 'package:velum/core/theme/app_colors.dart';
import '../../data/models/pronunciation.dart';
import '../providers/tts_notifier.dart';

const Color _accent = AppColors.accent;

/// List of words read aloud differently from how they're written, where the
/// reader adds, edits and removes them.
Future<void> showPronunciationsDialog(
  BuildContext context,
  TtsNotifier tts, {
  required Color textColor,
  required Color backgroundColor,
}) {
  return showDialog<void>(
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
  final written = TextEditingController(text: rule?.written);
  final spoken = TextEditingController(text: rule?.spoken);

  InputDecoration decoration(String label, String hint) => InputDecoration(
    labelText: label,
    hintText: hint,
    hintStyle: TextStyle(color: textColor.withAlpha(90)),
    labelStyle: TextStyle(color: textColor.withAlpha(150)),
    floatingLabelStyle: const TextStyle(color: _accent),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: textColor.withAlpha(60)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _accent, width: 2),
    ),
  );

  return showDialog<Pronunciation>(
    context: context,
    builder: (ctx) => ListenableBuilder(
      listenable: Listenable.merge([written, spoken]),
      builder: (ctx, _) {
        final result = Pronunciation(written.text.trim(), spoken.text.trim());
        void submit() {
          if (result.isComplete) Navigator.of(ctx).pop(result);
        }

        return AlertDialog(
          backgroundColor: backgroundColor,
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
                controller: written,
                autofocus: rule == null,
                textInputAction: TextInputAction.next,
                style: TextStyle(color: textColor, fontSize: 15.5),
                decoration: decoration('Written as', 'majestic'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: spoken,
                onSubmitted: (_) => submit(),
                style: TextStyle(color: textColor, fontSize: 15.5),
                decoration: decoration('Read as', 'beautiful'),
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
    ),
  );
}
