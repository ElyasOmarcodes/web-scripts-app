import 'package:flutter_test/flutter_test.dart';
import 'package:web_scripts/models/security.dart';

void main() {
  group('SecurityState', () {
    test('a fresh install has no password and is not locked', () {
      const fresh = SecurityState();
      expect(fresh.configured, isFalse);
      // Nothing to unlock: the app opens on its setup page, not a password box.
      expect(fresh.locked, isFalse);
    });

    test('reads what the backend reports', () {
      final state = SecurityState.fromJson({
        'configured': true,
        'locked': true,
        'windows_user': 'Elyas',
        'windows_available': true,
        'windows_enabled': true,
        'biometric_state': 'ready',
        'biometric_message': 'چمتو',
        'biometric_enabled': true,
        'min_length': 8,
      });
      expect(state.locked, isTrue);
      expect(state.windowsUser, 'Elyas');
      expect(state.minLength, 8);
      expect(state.methods, ['password', 'windows', 'biometric']);
    });

    test('the password is always one of the ways in', () {
      const bare = SecurityState(configured: true);
      expect(bare.methods, ['password']);
    });

    test('a reader with no finger on it is offered, not hidden', () {
      final state = SecurityState.fromJson(
          {'biometric_state': 'not_enrolled', 'biometric_message': 'ثبت کړئ'});
      expect(state.biometricReady, isFalse);
      expect(state.biometricNeedsEnrolment, isTrue);
      expect(state.biometricPossible, isTrue);
    });

    test('no reader at all is neither ready nor offerable', () {
      final state = SecurityState.fromJson({'biometric_state': 'no_hardware'});
      expect(state.biometricPossible, isFalse);
    });
  });

  group('SecretSummary', () {
    test('says that something is saved without saying what', () {
      final summary = SecretSummary.fromJson(
          {'has_username': true, 'has_password': true, 'updated_at': 12});
      expect(summary.any, isTrue);
      expect(summary.hasNote, isFalse);
    });

    test('an account with nothing saved reports nothing', () {
      expect(const SecretSummary().any, isFalse);
    });
  });

  group('AccountDetail', () {
    final detail = AccountDetail.fromJson({
      'id': 'acc_1',
      'label': 'کاري حساب',
      'category': 'facebook',
      'category_name': 'فیسبوک',
      'cookie_count': 2,
      'cookie_state': 'alive',
      'cookie_names': ['c_user', 'xs'],
      'cookie_domains': ['.facebook.com'],
      'proxy_mode': 'fixed',
      'proxy': {
        'address': '203.0.113.11:6754',
        'label': '',
        'country': 'Germany',
        'city': 'Frankfurt',
      },
      'fingerprint': {
        'label': 'ویندوز · کروم 145',
        'ua': 'Mozilla/5.0',
        'screen': '1920×1080',
        'gpu': 'ANGLE (NVIDIA)',
      },
      'secrets': {'has_password': true},
    });

    test('carries the whole account', () {
      expect(detail.label, 'کاري حساب');
      expect(detail.categoryName, 'فیسبوک');
      expect(detail.cookieNames, ['c_user', 'xs']);
      expect(detail.secrets.hasPassword, isTrue);
    });

    test('falls back to the proxy address when it has no label', () {
      expect(detail.proxyTitle, '203.0.113.11:6754');
      expect(detail.proxyPlace, 'Germany · Frankfurt');
    });

    test('carries the identity for the page to show', () {
      expect(detail.fingerprintLabel, contains('کروم'));
      expect(detail.fingerprintScreen, '1920×1080');
    });

    test('an account with no proxy says so quietly', () {
      final bare = AccountDetail.fromJson({'id': 'acc_2'});
      expect(bare.proxyTitle, '');
      expect(bare.proxyPlace, '');
      expect(bare.proxyMode, 'none');
    });
  });

  group('TransferResult', () {
    test('reads an export', () {
      final result = TransferResult.fromJson({
        'folder': '/home/user/exports',
        'files': ['/home/user/exports/accounts-1.csv'],
        'count': 7,
      });
      expect(result.count, 7);
      expect(result.files, hasLength(1));
    });

    test('reads an import, problems and all', () {
      final result = TransferResult.fromJson({
        'added': 2,
        'duplicates': 1,
        'problems': ['کرښه 4: پته نشته'],
        'note': 'کوکیز په CSV کې نه راځي',
      });
      expect(result.added, 2);
      expect(result.duplicates, 1);
      expect(result.problems.single, contains('کرښه 4'));
      expect(result.note, isNotEmpty);
    });

    test('an empty answer is not an error', () {
      const empty = TransferResult();
      expect(empty.count, 0);
      expect(empty.problems, isEmpty);
    });
  });
}
