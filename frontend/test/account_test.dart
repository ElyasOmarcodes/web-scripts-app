import 'package:flutter_test/flutter_test.dart';
import 'package:web_scripts/models/account.dart';

void main() {
  final book = AccountBook.fromJson({
    'categories': [
      {
        'id': 'facebook',
        'name': 'فیسبوک',
        'max_accounts': 2,
        'used': 2,
        'color': 'blue'
      },
      {
        'id': 'x',
        'name': 'ایکس',
        'max_accounts': 3,
        'used': 1,
        'color': 'gray'
      },
      {'id': 'instagram', 'name': 'انسټاګرام', 'max_accounts': 1, 'used': 0},
    ],
    'accounts': [
      {
        'id': 'acc_1',
        'category': 'facebook',
        'label': 'کاري',
        'status': 'ready',
        'has_cookies': true,
        'cookie_count': 14,
      },
      {
        'id': 'acc_2',
        'category': 'facebook',
        'label': 'شخصي',
        'status': 'ready',
        'has_cookies': true,
        'cookie_count': 12,
      },
      {
        'id': 'acc_3',
        'category': 'x',
        'label': 'رسمي',
        'status': 'ready',
        'has_cookies': true,
        'cookie_count': 9,
      },
      {
        // A sign-in that was never finished: no cookies, so it is not usable.
        'id': 'acc_4',
        'category': 'x',
        'label': 'نیمګړی',
        'status': 'pending',
        'has_cookies': false,
      },
    ],
  });

  group('AccountCategory', () {
    test('knows when it is full', () {
      expect(book.category('facebook')!.full, isTrue);
      expect(book.category('x')!.full, isFalse);
      expect(book.category('x')!.free, 2);
    });

    test('keeps the limits the backend sent', () {
      expect(book.category('facebook')!.maxAccounts, 2);
      expect(book.category('x')!.maxAccounts, 3);
      expect(book.category('instagram')!.maxAccounts, 1);
    });
  });

  group('AccountBook', () {
    test('lists only accounts that carry a session', () {
      expect(
          book.of('facebook').map((a) => a.label).toList(), ['کاري', 'شخصي']);
      expect(book.of('x').map((a) => a.label).toList(), ['رسمي']);
      expect(book.of('instagram'), isEmpty);
    });

    test('counts usable accounts only', () {
      expect(book.total, 3);
      expect(book.accounts.length, 4);
    });

    test('populated skips empty categories', () {
      expect(book.populated.map((c) => c.id).toList(), ['facebook', 'x']);
    });

    test('finds an account by id', () {
      expect(book.account('acc_3')!.label, 'رسمي');
      expect(book.account('acc_missing'), isNull);
    });
  });

  group('Account', () {
    test('is ready only with a stored session', () {
      expect(book.account('acc_1')!.ready, isTrue);
      expect(book.account('acc_4')!.ready, isFalse);
    });

    test('parses the backend field names', () {
      final account = Account.fromJson({
        'id': 'acc_9',
        'category': 'google',
        'label': 'جیمیل',
        'display_name': 'Inbox — Gmail',
        'cookie_count': 17,
        'has_cookies': true,
        'status': 'ready',
        'last_used_at': 1700000000000,
      });

      expect(account.displayName, 'Inbox — Gmail');
      expect(account.cookieCount, 17);
      expect(account.lastUsedAt, 1700000000000);
      expect(account.ready, isTrue);
    });

    test('missing fields fall back to safe defaults', () {
      final account = Account.fromJson({'id': 'a', 'category': 'x'});

      expect(account.label, '');
      expect(account.status, 'pending');
      expect(account.cookieCount, 0);
      expect(account.ready, isFalse);
    });
  });

  group('cookie state', () {
    test('an account with no check yet is unknown, not dead', () {
      final account = Account.fromJson({'id': 'a1', 'category': 'x'});

      expect(account.cookieState, 'unknown');
      expect(account.cookieCheckedAt, isNull);
    });

    test('reads what the checker recorded', () {
      final account = Account.fromJson({
        'id': 'a1',
        'category': 'x',
        'cookie_state': 'dead',
        'cookie_checked_at': 1730000000000,
        'cookie_note': 'د کوکیزو نېټه تېره ده',
      });

      expect(account.cookieState, 'dead');
      expect(account.cookieNote, 'د کوکیزو نېټه تېره ده');
      expect(account.cookieCheckedAt, 1730000000000);
    });
  });
}
