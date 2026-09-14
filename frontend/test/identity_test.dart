import 'package:flutter_test/flutter_test.dart';
import 'package:web_scripts/models/account.dart';
import 'package:web_scripts/models/fingerprint.dart';

Map<String, dynamic> _identity(String id, {int usedBy = 0, String tier = 'safe'}) => {
      'id': id,
      'label': 'ویندوز · کروم ۱۴۵',
      'tier': tier,
      'tier_label': 'ډېر خوندي',
      'ua': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/145.0.0.0',
      'brand': 'Google Chrome',
      'version': 145,
      'platform': 'Windows',
      'mobile': false,
      'screen': '1920×1080',
      'cores': 8,
      'memory': 8,
      'gpu': 'ANGLE (NVIDIA, RTX 3060)',
      'used_by': usedBy,
    };

void main() {
  group('BrowserIdentity', () {
    test('reads the whole device, not just the user agent', () {
      final identity = BrowserIdentity.fromJson(_identity('win-chrome-145'));
      expect(identity.brand, 'Google Chrome');
      expect(identity.version, 145);
      expect(identity.screen, '1920×1080');
      expect(identity.gpu, contains('NVIDIA'));
      expect(identity.mobile, isFalse);
    });

    test('a Safari identity may report no memory at all', () {
      final json = _identity('mac-safari-26')..['memory'] = null;
      expect(BrowserIdentity.fromJson(json).memory, isNull);
    });

    test('knows when more than one account wears it', () {
      expect(BrowserIdentity.fromJson(_identity('a', usedBy: 1)).shared, isFalse);
      expect(BrowserIdentity.fromJson(_identity('a', usedBy: 2)).shared, isTrue);
    });
  });

  group('IdentityBook', () {
    final book = IdentityBook.fromJson({
      'profiles': [
        _identity('win-chrome-145', usedBy: 1),
        _identity('mac-chrome-140', tier: 'fair'),
        _identity('iphone-18-6', tier: 'bold', usedBy: 3),
      ],
      'tiers': [
        {'id': 'safe', 'label': 'ډېر خوندي', 'note': 'ویندوز ډیسکټاپ'},
      ],
    });

    test('finds one by id, and copes with none', () {
      expect(book.byId('mac-chrome-140')!.tier, 'fair');
      expect(book.byId('nope'), isNull);
    });

    test('splits the catalogue by risk tier', () {
      expect(book.ofTier('safe'), hasLength(1));
      expect(book.ofTier('bold'), hasLength(1));
    });

    test('offers the identities nobody is using yet', () {
      expect(book.free.map((p) => p.id), ['mac-chrome-140']);
    });

    test('carries the tier notes the sheet explains itself with', () {
      expect(book.tiers.first.note, 'ویندوز ډیسکټاپ');
    });
  });

  group('Account', () {
    test('carries its own identity', () {
      final account = Account.fromJson({
        'id': 'acc_1',
        'category': 'facebook',
        'label': 'فیسبوک ۱',
        'fingerprint_id': 'win-chrome-145',
        'fingerprint': _identity('win-chrome-145'),
      });
      expect(account.fingerprintId, 'win-chrome-145');
      expect(account.fingerprint!.cores, 8);
    });

    test('an account from before identities existed simply has none', () {
      final account = Account.fromJson({'id': 'acc_1', 'category': 'x'});
      expect(account.fingerprintId, '');
      expect(account.fingerprint, isNull);
    });
  });

  group('AccountBook', () {
    Map<String, dynamic> account(String id, String fingerprint) => {
          'id': id,
          'category': 'facebook',
          'label': id,
          'status': 'ready',
          'has_cookies': true,
          'fingerprint_id': fingerprint,
        };

    test('names the accounts that share one browser identity', () {
      final book = AccountBook.fromJson({
        'accounts': [
          account('a', 'win-chrome-145'),
          account('b', 'win-chrome-145'),
          account('c', 'win-chrome-144'),
        ],
      });
      expect(book.twins.map((a) => a.id), containsAll(['a', 'b']));
      expect(book.twins.map((a) => a.id), isNot(contains('c')));
    });

    test('nobody is a twin when every account differs', () {
      final book = AccountBook.fromJson({
        'accounts': [
          account('a', 'win-chrome-145'),
          account('b', 'win-chrome-144'),
        ],
      });
      expect(book.twins, isEmpty);
    });

    test('reads the shared-address warning the backend sends', () {
      final book = AccountBook.fromJson({
        'accounts': const [],
        'sharing_proxy': [
          {
            'category': 'facebook',
            'proxy_id': 'prx_1',
            'accounts': ['a', 'b'],
            'labels': ['فیسبوک ۱', 'فیسبوک ۲'],
          }
        ],
      });
      expect(book.sharingProxy, hasLength(1));
      expect(book.sharingProxy.first.labels, hasLength(2));
    });
  });
}
