import 'package:flutter_test/flutter_test.dart';
import 'package:web_scripts/models/task.dart';

void main() {
  group('WebTask', () {
    test('reads what the backend sends', () {
      final task = WebTask.fromJson({
        'id': 'tsk_1',
        'name': 'د ایکس پوستونه',
        'script_id': 'scr_1',
        'account_ids': ['a1', 'a2', 'a3'],
        'concurrency': 2,
        'status': 'partial',
        'done_count': 1,
        'failed_count': 1,
        'pending_count': 2,
        'runs': [
          {'account_id': 'a1', 'status': 'ok', 'completed': 5, 'total': 5},
          {'account_id': 'a2', 'status': 'failed', 'error': 'ونه موندل شو'},
          {'account_id': 'a3', 'status': 'pending'},
        ],
      });

      expect(task.name, 'د ایکس پوستونه');
      expect(task.concurrency, 2);
      expect(task.runFor('a1')!.done, isTrue);
      expect(task.runFor('a2')!.failed, isTrue);
      expect(task.runFor('a2')!.error, 'ونه موندل شو');
      expect(task.runFor('nope'), isNull);
    });

    test('a task stopped half way offers to carry on', () {
      final task = WebTask.fromJson({
        'id': 't',
        'status': 'partial',
        'pending_count': 2,
      });

      expect(task.canResume, isTrue);
    });

    test('a finished task has nothing to resume', () {
      final task = WebTask.fromJson({
        'id': 't',
        'status': 'done',
        'pending_count': 0,
      });

      expect(task.canResume, isFalse);
    });

    test('a draft is not resumable even with accounts waiting', () {
      final task = WebTask.fromJson({
        'id': 't',
        'status': 'draft',
        'pending_count': 3,
      });

      expect(task.canResume, isFalse);
    });

    test('round-trips the fields the backend accepts', () {
      const task = WebTask(
        id: 't',
        name: 'کار',
        scriptId: 'scr_1',
        accountIds: ['a1'],
        concurrency: 3,
        gapSeconds: 5,
        stopOnError: true,
      );

      final json = task.toJson();

      expect(json['account_ids'], ['a1']);
      expect(json['concurrency'], 3);
      expect(json['stop_on_error'], true);
      expect(json['gap_seconds'], 5.0);
      // The id is the route, never part of the body.
      expect(json.containsKey('id'), isFalse);
    });

    test('copyWith keeps the results while changing the settings', () {
      final task = WebTask.fromJson({
        'id': 't',
        'runs': [
          {'account_id': 'a1', 'status': 'ok'}
        ],
        'done_count': 1,
      });

      final edited = task.copyWith(name: 'نوی نوم', concurrency: 4);

      expect(edited.name, 'نوی نوم');
      expect(edited.concurrency, 4);
      expect(edited.runFor('a1')!.done, isTrue);
    });
  });

  group('TaskBook', () {
    test('finds a task by id and carries the overview', () {
      final book = TaskBook.fromJson({
        'tasks': [
          {'id': 't1', 'name': 'یو'},
          {'id': 't2', 'name': 'دوه'},
        ],
        'overview': {'total': 2, 'done': 1, 'failed': 0, 'partial': 1},
      });

      expect(book.total, 2);
      expect(book.byId('t2')!.name, 'دوه');
      expect(book.byId('nope'), isNull);
      expect(book.overview['partial'], 1);
    });
  });
}
