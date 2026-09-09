import 'package:flutter_test/flutter_test.dart';
import 'package:web_scripts/models/settings.dart';

void main() {
  group('AppSettings', () {
    test('falls back to defaults for missing keys', () {
      final settings = AppSettings.fromJson({});

      expect(settings.browser, 'auto');
      expect(settings.speed, 1.0);
      expect(settings.useProfile, isTrue);
      expect(settings.theme, 'system');
    });

    test('round-trips through json with backend key names', () {
      const original = AppSettings(
        browser: 'chrome',
        speed: 2.5,
        headless: true,
        stepTimeout: 30,
        accent: 'purple',
      );

      final copy = AppSettings.fromJson(original.toJson());

      expect(copy.browser, 'chrome');
      expect(copy.speed, 2.5);
      expect(copy.headless, isTrue);
      expect(copy.stepTimeout, 30);
      expect(copy.accent, 'purple');
      // snake_case is what the Python side expects
      expect(original.toJson().containsKey('step_timeout'), isTrue);
      expect(original.toJson().containsKey('keep_open'), isTrue);
    });
  });

  group('BrowserInfo', () {
    test('extracts a short version out of the full string', () {
      const browser = BrowserInfo(
        id: 'chrome',
        name: 'Google Chrome',
        version: 'Google Chrome 141.0.7390.54',
        installed: true,
      );

      expect(browser.shortVersion, '141.0.7390.54');
    });

    test('is usable only when installed and supported', () {
      const firefox = BrowserInfo(
        id: 'firefox',
        name: 'Mozilla Firefox',
        family: 'gecko',
        installed: true,
        supported: false,
      );
      const missing = BrowserInfo(id: 'brave', name: 'Brave', installed: false);
      const edge = BrowserInfo(id: 'edge', name: 'Edge', installed: true);

      expect(firefox.usable, isFalse);
      expect(missing.usable, isFalse);
      expect(edge.usable, isTrue);
    });
  });

  group('BrowserList', () {
    final list = BrowserList.fromJson({
      'selected': 'auto',
      'active': 'edge',
      'browsers': [
        {'id': 'edge', 'name': 'Microsoft Edge', 'installed': true},
        {'id': 'chrome', 'name': 'Google Chrome', 'installed': true},
        {'id': 'brave', 'name': 'Brave', 'installed': false},
        {
          'id': 'firefox',
          'name': 'Mozilla Firefox',
          'installed': true,
          'supported': false,
        },
      ],
    });

    test('resolves the active browser', () {
      expect(list.activeBrowser?.name, 'Microsoft Edge');
    });

    test('installed hides missing and unsupported browsers', () {
      expect(list.installed.map((b) => b.id).toList(), ['edge', 'chrome']);
    });

    test('keeps every browser for the settings list', () {
      expect(list.browsers.length, 4);
    });
  });

  group('account-safety settings', () {
    test('humanising and smart skip are on out of the box', () {
      final settings = AppSettings.fromJson({});

      expect(settings.humanize, isTrue);
      expect(settings.humanMinGap, 0.5);
      expect(settings.humanMaxGap, 1.5);
      expect(settings.randomScroll, isTrue);
      expect(settings.smartSkip, isTrue);
    });

    test('round-trips the safety keys the backend uses', () {
      const original = AppSettings(
        humanize: false,
        humanMinGap: 1.0,
        humanMaxGap: 2.5,
        randomScroll: false,
        smartSkip: false,
      );

      final json = original.toJson();
      expect(json['human_min_gap'], 1.0);
      expect(json['random_scroll'], false);

      final restored = AppSettings.fromJson(json);
      expect(restored.humanize, isFalse);
      expect(restored.humanMaxGap, 2.5);
      expect(restored.smartSkip, isFalse);
    });
  });
}
