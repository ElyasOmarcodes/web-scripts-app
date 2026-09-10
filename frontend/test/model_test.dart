import 'package:flutter_test/flutter_test.dart';
import 'package:web_scripts/models/script.dart';

void main() {
  group('StepModel', () {
    test('parses a recorded click step', () {
      final step = StepModel.fromJson({
        'id': 'stp_1',
        'action': 'click',
        'targets': [
          {'type': 'css', 'value': '[aria-label="Settings"]', 'kind': 'aria'}
        ],
        'label': 'Settings',
        'delay_ms': 800,
        'frame_path': [1],
      });

      expect(step.action, 'click');
      expect(step.targets.single.value, '[aria-label="Settings"]');
      expect(step.framePath, [1]);
      expect(step.description, contains('Settings'));
    });

    test('hides the value of a secret step', () {
      final step = StepModel.fromJson({
        'id': 'stp_2',
        'action': 'type',
        'value': '{{password}}',
        'secret': true,
        'targets': [
          {'type': 'css', 'value': '#pass'}
        ],
      });

      expect(step.description, contains('••••••'));
      expect(step.description, isNot(contains('password')));
    });

    test('round-trips through json', () {
      final original = StepModel.fromJson({
        'id': 'stp_3',
        'action': 'select',
        'value': 'تیاره',
        'option_value': 'dark',
        'targets': [
          {'type': 'css', 'value': 'select[name="theme"]'}
        ],
      });

      final copy = StepModel.fromJson(original.toJson());

      expect(copy.value, 'تیاره');
      expect(copy.optionValue, 'dark');
      expect(copy.action, 'select');
    });
  });

  group('WebScript', () {
    test('reads the summary payload', () {
      final script = WebScript.fromJson({
        'id': 'scr_1',
        'name': 'فیسبوک تم',
        'start_url': 'https://facebook.com',
        'step_count': 5,
        'last_run_ok': true,
      });

      expect(script.stepCount, 5);
      expect(script.steps, isEmpty);
      expect(script.lastRunOk, isTrue);
    });

    test('counts enabled steps when no summary field is present', () {
      final script = WebScript.fromJson({
        'id': 'scr_2',
        'name': 'x',
        'steps': [
          {'id': 'a', 'action': 'click', 'enabled': true},
          {'id': 'b', 'action': 'click', 'enabled': false},
        ],
      });

      expect(script.stepCount, 1);
      expect(script.steps.length, 2);
    });
  });

  group('AppEvent', () {
    test('marks step errors as errors', () {
      final event = AppEvent.fromJson({
        'type': 'step_error',
        'message': 'عنصر ونه موندل شو',
      });

      expect(event.isError, isTrue);
    });

    test('builds a message for events that carry none', () {
      final event = AppEvent.fromJson({'type': 'run_finished', 'status': 'ok'});

      expect(event.message, contains('ok'));
    });
  });

  group('optional steps', () {
    test('a step is required unless it says otherwise', () {
      final step = StepModel.fromJson({'id': 's1', 'action': 'click'});

      expect(step.optional, isFalse);
    });

    test('optional survives the round trip to the backend', () {
      final step = StepModel.fromJson(
        {'id': 's1', 'action': 'click', 'optional': true},
      );

      expect(step.optional, isTrue);
      expect(step.toJson()['optional'], true);
    });
  });

  group('script pacing', () {
    test('a script without its own pacing follows the app setting', () {
      final script = WebScript.fromJson({'id': 's', 'name': 'یو'});

      expect(script.gapMinMs, isNull);
      expect(script.gapMaxMs, isNull);
    });

    test('a script can carry its own random gap', () {
      final script = WebScript.fromJson(
        {'id': 's', 'name': 'یو', 'gap_min_ms': 800, 'gap_max_ms': 2500},
      );

      expect(script.gapMinMs, 800);
      expect(script.gapMaxMs, 2500);
    });
  });
}
