import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:velum/core/theme/app_colors.dart';
import '../../data/models/reader_settings.dart';
import '../providers/settings_notifier.dart';

// The controls for how books look, shared by the Settings screen, the
// reader's settings sheet and onboarding. `compact` is the sheet's tighter
// look; [theme] is the theme of the surface the control sits on.

const Color _accent = AppColors.accent;

/// Heading above a control.
class SettingLabel extends StatelessWidget {
  final String label;
  final ReaderTheme theme;
  final bool compact;

  const SettingLabel(
    this.label, {
    super.key,
    required this.theme,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: compact
          ? TextStyle(fontWeight: FontWeight.w600, color: theme.textColor)
          : TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: theme.textColor.withAlpha(200),
            ),
    );
  }
}

/// An "Aa" circle for each theme, with a ring around the selected one.
class ThemeCircles extends StatelessWidget {
  final ReaderTheme selected;
  final ValueChanged<ReaderTheme> onSelect;

  /// Colour of the theme names under the circles. Null leaves them out.
  final Color? labelColor;
  final double labelSize;
  final bool compact;

  const ThemeCircles({
    super.key,
    required this.selected,
    required this.onSelect,
    this.labelColor,
    this.labelSize = 11,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = this.labelColor;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: ReaderTheme.values.map((theme) {
        final isSelected = selected == theme;
        final decoration = BoxDecoration(
          color: theme.backgroundColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? _accent : Colors.grey.withAlpha(60),
            width: !isSelected
                ? 1
                : compact
                ? 2.5
                : 3,
          ),
          boxShadow: [
            if (isSelected)
              compact
                  ? BoxShadow(color: _accent.withAlpha(50), blurRadius: 8)
                  : BoxShadow(
                      color: _accent.withAlpha(60),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
          ],
        );
        final sample = Center(
          child: Text(
            'Aa',
            style: TextStyle(
              color: theme.textColor,
              fontWeight: FontWeight.bold,
              fontSize: compact ? null : 16,
            ),
          ),
        );
        return GestureDetector(
          onTap: () => onSelect(theme),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (compact)
                Container(
                  width: 56,
                  height: 56,
                  decoration: decoration,
                  child: sample,
                )
              else
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 56,
                  height: 56,
                  decoration: decoration,
                  child: sample,
                ),
              if (labelColor != null) ...[
                const SizedBox(height: 8),
                Text(
                  theme.displayName,
                  style: TextStyle(
                    fontSize: labelSize,
                    color: labelColor.withAlpha(isSelected ? 255 : 150),
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// A rounded chip that fills with the accent colour when selected.
class _Chip extends StatelessWidget {
  final bool selected;
  final ReaderTheme theme;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  const _Chip({
    required this.selected,
    required this.theme,
    required this.compact,
    required this.onTap,
    this.onLongPress,
    required this.child,
  });

  /// Text on a chip: white when selected.
  static TextStyle textStyle(bool selected, ReaderTheme theme) => TextStyle(
    fontSize: 13,
    color: selected ? Colors.white : theme.textColor,
    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
  );

  @override
  Widget build(BuildContext context) {
    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 10);
    final decoration = BoxDecoration(
      color: selected ? _accent : Colors.transparent,
      borderRadius: BorderRadius.circular(compact ? 8 : 10),
      border: Border.all(
        color: selected
            ? _accent
            : compact
            ? theme.textColor.withAlpha(60)
            : Colors.grey.withAlpha(80),
        width: compact ? 1 : 1.5,
      ),
    );
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: compact
          ? Container(padding: padding, decoration: decoration, child: child)
          : AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: padding,
              decoration: decoration,
              child: child,
            ),
    );
  }
}

/// The built-in fonts, the user's own fonts (tap to select, long-press or
/// the cross to remove) and "Add" to import one.
class FontChips extends StatefulWidget {
  final SettingsNotifier notifier;
  final ReaderTheme theme;
  final bool compact;

  const FontChips({
    super.key,
    required this.notifier,
    required this.theme,
    this.compact = false,
  });

  @override
  State<FontChips> createState() => _FontChipsState();
}

class _FontChipsState extends State<FontChips> {
  bool _importFailed = false;

  Future<void> _addFont() async {
    setState(() => _importFailed = false);
    final added = await widget.notifier.importCustomFont();
    if (mounted && !added) setState(() => _importFailed = true);
  }

  String _name(ReaderFont font) => switch (font) {
    ReaderFont.serif => 'Serif',
    ReaderFont.sans => widget.compact ? 'Sans' : 'Sans Serif',
    ReaderFont.mono => widget.compact ? 'Mono' : 'Monospace',
    ReaderFont.custom => 'Custom',
  };

  /// A built-in font's chip is written in that font.
  TextStyle _style(ReaderFont font, bool selected) {
    final style = _Chip.textStyle(selected, widget.theme);
    return switch (font) {
      ReaderFont.serif => GoogleFonts.merriweather(textStyle: style),
      ReaderFont.sans => GoogleFonts.inter(textStyle: style),
      ReaderFont.mono => GoogleFonts.robotoMono(textStyle: style),
      ReaderFont.custom => style,
    };
  }

  @override
  Widget build(BuildContext context) {
    final notifier = widget.notifier;
    final settings = notifier.settings;
    final theme = widget.theme;
    final compact = widget.compact;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final font in ReaderFont.values)
              if (font != ReaderFont.custom)
                _Chip(
                  selected: settings.font == font,
                  theme: theme,
                  compact: compact,
                  onTap: () => notifier.updateFont(font),
                  child: Text(
                    _name(font),
                    style: _style(font, settings.font == font),
                  ),
                ),
            for (final customFont in settings.customFonts)
              _customFontChip(
                customFont.id,
                customFont.name,
                settings.font == ReaderFont.custom &&
                    settings.selectedCustomFontId == customFont.id,
              ),
            // Add Font Button
            GestureDetector(
              onTap: _addFont,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: compact ? 8 : 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(compact ? 8 : 10),
                  border: Border.all(color: theme.textColor.withAlpha(60)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 16, color: theme.textColor),
                    const SizedBox(width: 4),
                    Text(
                      'Add',
                      style: TextStyle(fontSize: 13, color: theme.textColor),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_importFailed) ...[
          const SizedBox(height: 8),
          const Text(
            "Couldn't add that font. Pick a TTF or OTF file.",
            style: TextStyle(fontSize: 12, color: Colors.red),
          ),
        ],
      ],
    );
  }

  Widget _customFontChip(String id, String name, bool selected) {
    final notifier = widget.notifier;
    return _Chip(
      selected: selected,
      theme: widget.theme,
      compact: widget.compact,
      onTap: () => notifier.selectCustomFont(id),
      onLongPress: () => notifier.removeCustomFont(id),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name, style: _Chip.textStyle(selected, widget.theme)),
          if (selected) ...[
            SizedBox(width: widget.compact ? 4 : 6),
            GestureDetector(
              onTap: () => notifier.removeCustomFont(id),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }
}

/// Left-aligned or justified text.
class TextAlignmentChips extends StatelessWidget {
  final SettingsNotifier notifier;
  final ReaderTheme theme;
  final bool compact;

  const TextAlignmentChips({
    super.key,
    required this.notifier,
    required this.theme,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final current = notifier.settings.textAlignment;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final alignment in TextAlignment.values)
          _Chip(
            selected: current == alignment,
            theme: theme,
            compact: compact,
            onTap: () => notifier.updateTextAlignment(alignment),
            child: Text(
              alignment.displayName,
              style: _Chip.textStyle(current == alignment, theme),
            ),
          ),
      ],
    );
  }
}

/// A labelled slider with its current value shown on the right.
class SettingSlider extends StatelessWidget {
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ReaderTheme theme;
  final bool compact;

  const SettingSlider({
    super.key,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.theme,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SettingLabel(label, theme: theme, compact: compact),
            if (compact)
              Text(valueLabel, style: TextStyle(color: theme.textColor))
            else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme == ReaderTheme.dark
                      ? Colors.white.withAlpha(15)
                      : Colors.black.withAlpha(8),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  valueLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.textColor,
                  ),
                ),
              ),
          ],
        ),
        if (!compact) const SizedBox(height: 8),
        SliderTheme(
          data: compact
              ? SliderThemeData(
                  activeTrackColor: _accent,
                  inactiveTrackColor: theme.textColor.withAlpha(40),
                  thumbColor: _accent,
                )
              : SliderThemeData(
                  activeTrackColor: _accent,
                  inactiveTrackColor: Colors.grey.withAlpha(60),
                  thumbColor: _accent,
                  overlayColor: _accent.withAlpha(30),
                  trackHeight: 4,
                ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Font size, line height, paragraph spacing and margins.
class TypographySliders extends StatelessWidget {
  final SettingsNotifier notifier;
  final ReaderTheme theme;
  final bool compact;

  const TypographySliders({
    super.key,
    required this.notifier,
    required this.theme,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final settings = notifier.settings;
    final gap = SizedBox(height: compact ? 16 : 20);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingSlider(
          label: compact ? 'Size' : 'Font Size',
          valueLabel: '${settings.fontSize.toInt()}px',
          value: settings.fontSize,
          min: 12,
          max: 32,
          divisions: 10,
          onChanged: notifier.updateFontSize,
          theme: theme,
          compact: compact,
        ),
        gap,
        SettingSlider(
          label: 'Line Height',
          valueLabel: settings.lineHeight.toStringAsFixed(1),
          value: settings.lineHeight,
          min: 1.0,
          max: 2.5,
          divisions: 15,
          onChanged: notifier.updateLineHeight,
          theme: theme,
          compact: compact,
        ),
        gap,
        SettingSlider(
          label: 'Paragraph Spacing',
          valueLabel: settings.paragraphSpacing.toStringAsFixed(1),
          value: settings.paragraphSpacing,
          min: 0.0,
          max: 3.0,
          divisions: 30,
          onChanged: notifier.updateParagraphSpacing,
          theme: theme,
          compact: compact,
        ),
        gap,
        SettingSlider(
          label: 'Margins',
          valueLabel: '${settings.horizontalMargin.toInt()}px',
          value: settings.horizontalMargin,
          min: 0,
          max: 40,
          divisions: 8,
          onChanged: notifier.updateHorizontalMargin,
          theme: theme,
          compact: compact,
        ),
      ],
    );
  }
}
