import 'package:flutter/material.dart';

import '../models/script.dart';

/// Asks for the script name and the page the recording should start from.
class RecordDialog extends StatefulWidget {
  const RecordDialog({super.key});

  @override
  State<RecordDialog> createState() => _RecordDialogState();
}

class RecordRequest {
  RecordRequest(this.name, this.url, this.captureScroll);

  final String name;
  final String url;
  final bool captureScroll;
}

class _RecordDialogState extends State<RecordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController(text: 'نوی سکریپټ');
  final _url = TextEditingController(text: 'https://www.facebook.com');
  bool _captureScroll = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('نوې لارښوونه ثبتول'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'نوم'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'نوم اړین دی' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _url,
                decoration: const InputDecoration(
                  labelText: 'پیل پته (URL)',
                  hintText: 'https://www.facebook.com',
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return 'پته اړینه ده';
                  final uri = Uri.tryParse(text);
                  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                    return 'سمه پته ولیکئ (http:// یا https:// سره)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _captureScroll,
                onChanged: (value) =>
                    setState(() => _captureScroll = value ?? false),
                title: const Text('سکرول هم ثبت کړه'),
                subtitle: const Text('ډېری وخت اړتیا نشته'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 4),
              const Text(
                'براوزر پرانیستل کېږي. خپل کار پکې وکړئ، بیا «ثبتول ودروه» ووهئ.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('لغوه'),
        ),
        FilledButton.icon(
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            Navigator.of(context).pop(
              RecordRequest(_name.text.trim(), _url.text.trim(), _captureScroll),
            );
          },
          icon: const Icon(Icons.fiber_manual_record),
          label: const Text('ثبتول پیل کړه'),
        ),
      ],
    );
  }
}

/// Collects values for the script's variables (passwords and friends).
class VariablesDialog extends StatefulWidget {
  const VariablesDialog({super.key, required this.variables});

  final List<VariableModel> variables;

  @override
  State<VariablesDialog> createState() => _VariablesDialogState();
}

class _VariablesDialogState extends State<VariablesDialog> {
  late final Map<String, TextEditingController> _controllers = {
    for (final variable in widget.variables)
      variable.name: TextEditingController(text: variable.defaultValue),
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('اړین ارزښتونه'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final variable in widget.variables)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _controllers[variable.name],
                  obscureText: variable.secret,
                  decoration: InputDecoration(
                    labelText: variable.label.isEmpty
                        ? variable.name
                        : '${variable.label} (${variable.name})',
                  ),
                ),
              ),
            const Text(
              'دا ارزښتونه یوازې د چلولو لپاره کارېږي او خوندي نه کېږي.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('لغوه'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _controllers.map((key, value) => MapEntry(key, value.text)),
          ),
          child: const Text('چلول'),
        ),
      ],
    );
  }
}

/// Small single-field editor used for renaming and for editing step values.
class TextPromptDialog extends StatefulWidget {
  const TextPromptDialog({
    super.key,
    required this.title,
    required this.initialValue,
    this.label = '',
  });

  final String title;
  final String initialValue;
  final String label;

  @override
  State<TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<TextPromptDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('لغوه'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('خوندي کول'),
        ),
      ],
    );
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'هو',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('نه'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
