import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velum/features/settings/data/models/reader_settings.dart';
import 'package:velum/features/settings/presentation/providers/settings_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(SettingsNotifier, SharedPreferences)> open(
    Map<String, Object> saved,
  ) async {
    SharedPreferences.setMockInitialValues(saved);
    final prefs = await SharedPreferences.getInstance();
    return (SettingsNotifier(prefs), prefs);
  }

  String fonts(List<Object?> entries) => jsonEncode(entries);
  Map<String, String> font(String id) => {
    'id': id,
    'name': 'Font $id',
    'path': '/nowhere/$id.ttf',
  };

  test('a theme is only saved once the user picks it', () async {
    final (notifier, prefs) = await open({});

    notifier.updateFont(ReaderFont.sans);
    notifier.updateTextAlignment(TextAlignment.justify);
    notifier.updateFontSize(20);
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(prefs.getInt('font'), ReaderFont.sans.index);
    expect(prefs.getDouble('font_size'), 20);
    // Still following the system.
    expect(prefs.getInt('app_theme'), isNull);
    expect(prefs.getInt('reader_theme'), isNull);

    notifier.updateAppTheme(ReaderTheme.sepia);
    await pumpEventQueue();
    expect(notifier.settings.appTheme, ReaderTheme.sepia);
    expect(prefs.getInt('app_theme'), ReaderTheme.sepia.index);
    expect(prefs.getInt('reader_theme'), isNull);

    notifier.updateReaderTheme(ReaderTheme.dark);
    await pumpEventQueue();
    expect(prefs.getInt('reader_theme'), ReaderTheme.dark.index);
  });

  test('removing the last custom font leaves none selected', () async {
    final (notifier, prefs) = await open({
      'font': ReaderFont.custom.index,
      'custom_fonts_list': fonts([font('a'), font('b')]),
      'selected_custom_font_id': 'b',
    });

    await notifier.removeCustomFont('b');
    expect(notifier.settings.selectedCustomFontId, 'a');
    expect(notifier.settings.font, ReaderFont.custom);

    await notifier.removeCustomFont('a');
    expect(notifier.settings.customFonts, isEmpty);
    expect(notifier.settings.selectedCustomFontId, isNull);
    expect(notifier.settings.font, ReaderFont.serif);
    expect(prefs.getString('selected_custom_font_id'), isNull);
  });

  test('copyWith keeps the selected custom font unless told otherwise', () {
    const settings = ReaderSettings(selectedCustomFontId: 'a');
    expect(settings.copyWith(fontSize: 20).selectedCustomFontId, 'a');
    expect(
      settings.copyWith(selectedCustomFontId: 'b').selectedCustomFontId,
      'b',
    );
    expect(
      settings.copyWith(selectedCustomFontId: null).selectedCustomFontId,
      isNull,
    );
  });

  test('a custom font that cannot be read does not take the others', () async {
    final (notifier, prefs) = await open({
      'custom_fonts_list': fonts([
        font('a'),
        {'id': 'broken'},
        'junk',
        font('b'),
      ]),
    });
    expect(notifier.settings.customFonts.map((f) => f.id), ['a', 'b']);

    // A later save keeps the readable ones.
    notifier.updateFont(ReaderFont.mono);
    await pumpEventQueue();
    expect(
      (jsonDecode(prefs.getString('custom_fonts_list')!) as List).map(
        (f) => f['id'],
      ),
      ['a', 'b'],
    );
  });
}
