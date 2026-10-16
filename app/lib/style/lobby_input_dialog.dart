import 'package:flutter/material.dart';

import 'lobby_theme.dart';

class LobbyInput {
  const LobbyInput({
    required this.label,
    this.value = '',
    this.maxLength = 40,
    this.lines = 1,
    this.keyboard,
    this.validator,
  });
  final String label, value;
  final int maxLength, lines;
  final TextInputType? keyboard;
  final String? Function(String?)? validator;
}

Future<List<String>?> showLobbyInputs({
  required BuildContext context,
  required String title,
  required String confirm,
  required String cancel,
  required List<LobbyInput> fields,
}) => showLobbyDialog<List<String>>(
  context: context,
  builder: (_) => _InputDialog(
    title: title,
    confirm: confirm,
    cancel: cancel,
    fields: fields,
  ),
);

class _InputDialog extends StatefulWidget {
  const _InputDialog({
    required this.title,
    required this.confirm,
    required this.cancel,
    required this.fields,
  });
  final String title, confirm, cancel;
  final List<LobbyInput> fields;
  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  final form = GlobalKey<FormState>();
  late final controllers = [
    for (final field in widget.fields) TextEditingController(text: field.value),
  ];
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.fields.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                child: TextFormField(
                  controller: controllers[i],
                  maxLength: widget.fields[i].maxLength,
                  maxLines: widget.fields[i].lines,
                  keyboardType: widget.fields[i].keyboard,
                  validator: widget.fields[i].validator,
                  decoration: InputDecoration(
                    labelText: widget.fields[i].label,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.cancel),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(
              context,
              controllers.map((c) => c.text.trim()).toList(),
            );
          }
        },
        child: Text(widget.confirm),
      ),
    ],
  );
  @override
  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
