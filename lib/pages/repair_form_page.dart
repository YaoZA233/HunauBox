import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/repair_models.dart';
import '../services/repair_service.dart';
import '../models/leave_application.dart';

class RepairFormPage extends StatefulWidget {
  final RepairService service;
  final RepairCatalog catalog;
  const RepairFormPage({
    super.key,
    required this.service,
    required this.catalog,
  });
  @override
  State<RepairFormPage> createState() => _RepairFormPageState();
}

class _RepairFormPageState extends State<RepairFormPage> {
  final _form = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final _choices = <String, RepairChoice>{};
  final _attachments = <String, List<RepairAttachment>>{};
  RepairFormSession? _session;
  bool _loading = true, _busy = false;
  String? _error, _activeField;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await widget.service.loadForm(widget.catalog);
      if (!mounted) return;
      for (final c in _controllers.values) {
        c.dispose();
      }
      _controllers.clear();
      _choices.clear();
      for (final field in session.fields) {
        final value =
            session.initialValues[field.name] ??
            field.raw['value'] ??
            field.raw['defaultValue'];
        var text = value is Map
            ? '${value['display_name'] ?? value['name'] ?? ''}'
            : '${value ?? ''}';
        if (field.isChoice && text.isNotEmpty) {
          final id = value is Map
              ? '${value['id'] ?? value['name'] ?? ''}'
              : text;
          if (field.editor == 'priority') {
            text = {'1': '低', '2': '中', '3': '高'}[id] ?? text;
          }
          _choices[field.name] = RepairChoice(id, text);
        }
        _controllers[field.name] = TextEditingController(text: text);
      }
      setState(() => _session = session);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _choose(RepairField field) async {
    if (_activeField != null) return;
    setState(() => _activeField = field.name);
    try {
      List<String>? excluded;
      final selected = DateTime.tryParse(
        (_controllers['yyrq']?.text ?? '').replaceAll('/', '-'),
      );
      final now = DateTime.now();
      if (field.name == 'yywxsj' &&
          selected != null &&
          selected.year == now.year &&
          selected.month == now.month &&
          selected.day == now.day &&
          now.hour >= 12) {
        excluded = ['8_9', '9_10', '10_11', '11_12'];
      }
      final choices = field.editor == 'priority'
          ? await widget.service.lookup(
              field.referenceType ?? '51ba96d7-9f0c-4077-ac91-921e30fcde3c',
            )
          : field.referenceType != null
          ? await widget.service.lookup(
              field.referenceType!,
              notInNames: excluded,
            )
          : field.reference != null
          ? await widget.service.references(field.reference!)
          : <RepairChoice>[];
      if (!mounted) return;
      if (choices.isEmpty) {
        _message('学校未返回${field.label}选项，请稍后重试');
        return;
      }
      final choice = await showModalBottomSheet<RepairChoice>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  field.label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final choice in choices)
                ListTile(
                  title: Text(choice.label),
                  trailing: _choices[field.name]?.id == choice.id
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(context, choice),
                ),
            ],
          ),
        ),
      );
      if (choice != null && mounted) {
        setState(() {
          _choices[field.name] = choice;
          _controllers[field.name]!.text = choice.label;
        });
      }
    } catch (e) {
      if (mounted) _message('$e');
    } finally {
      if (mounted) setState(() => _activeField = null);
    }
  }

  Future<void> _pickDate(RepairField field) async {
    final now = DateTime.now(), c = _controllers[field.name]!;
    final booking = field.name == 'yyrq' || field.label.contains('预约日期');
    final first = booking
        ? DateTime(now.year, now.month, now.day)
        : DateTime(2020);
    final last = booking ? first.add(const Duration(days: 7)) : DateTime(2040);
    var initial = DateTime.tryParse(c.text.replaceAll('/', '-')) ?? now;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (!mounted || date == null) return;
    DateTime value = date;
    if (field.editor == 'datetimepicker') {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initial),
      );
      if (!mounted || time == null) return;
      value = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    }
    setState(() {
      c.text = field.editor == 'datetimepicker'
          ? LeaveApplication.formatTime(value)
          : LeaveApplication.formatTime(value).split(' ').first;
      if (field.name == 'yyrq') {
        _choices.remove('yywxsj');
        _controllers['yywxsj']?.clear();
      }
    });
  }

  Future<void> _upload(RepairField field) async {
    if (_activeField != null) return;
    setState(() => _activeField = field.name);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (!mounted || image == null) return;
      final file = await widget.service.uploadAttachment(
        _session!,
        field,
        File(image.path),
      );
      if (mounted) {
        setState(
          () => _attachments.putIfAbsent(field.name, () => []).add(file),
        );
      }
    } catch (e) {
      if (mounted) _message('附件上传失败：$e');
    } finally {
      if (mounted) setState(() => _activeField = null);
    }
  }

  Future<void> _remove(RepairField field, RepairAttachment file) async {
    setState(() => _activeField = field.name);
    try {
      await widget.service.deleteAttachment(file.id);
      if (mounted) setState(() => _attachments[field.name]?.remove(file));
    } catch (e) {
      if (mounted) _message('$e');
    } finally {
      if (mounted) setState(() => _activeField = null);
    }
  }

  Future<void> _submit() async {
    if (_busy || _activeField != null || !_form.currentState!.validate()) {
      return;
    }
    final values = <String, dynamic>{};
    for (final field in _session!.fields) {
      if (field.hidden || field.readonly) continue;
      if (field.isUpload) {
        final files = _attachments[field.name] ?? [];
        if (field.required && files.isEmpty) {
          _message('请上传${field.label}');
          return;
        }
        values[field.name] = files.length;
      } else {
        values[field.name] =
            _choices[field.name]?.id ?? _controllers[field.name]!.text.trim();
      }
    }
    setState(() => _busy = true);
    try {
      await widget.service.submitForm(_session!, values);
      if (mounted) {
        _message('报修已提交');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) _message('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(RepairField field) {
    if (field.isUpload) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${field.label}${field.required ? ' *' : '（选填）'}'),
            for (final file in _attachments[field.name] ?? <RepairAttachment>[])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  file.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: '移除附件',
                  onPressed: _activeField != null || field.readonly
                      ? null
                      : () => _remove(field, file),
                  icon: const Icon(Icons.close),
                ),
              ),
            OutlinedButton.icon(
              onPressed: _activeField != null || field.readonly
                  ? null
                  : () => _upload(field),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(_activeField == field.name ? '正在处理…' : '上传图片'),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: _controllers[field.name],
        readOnly: field.readonly || field.isDate || field.isChoice,
        onTap: field.readonly || _activeField != null
            ? null
            : field.isDate
            ? () => _pickDate(field)
            : field.isChoice
            ? () => _choose(field)
            : null,
        minLines: field.isMultiline ? 3 : 1,
        maxLines: field.isMultiline ? 6 : 1,
        keyboardType: field.name == 'lxfs'
            ? TextInputType.phone
            : field.isMultiline
            ? TextInputType.multiline
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: '${field.label}${field.required ? ' *' : ''}',
          suffixIcon: _activeField == field.name
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : field.isChoice
              ? const Icon(Icons.expand_more)
              : field.isDate
              ? const Icon(Icons.calendar_month_outlined)
              : null,
        ),
        validator: (v) {
          if (field.required && (v ?? '').trim().isEmpty) {
            return '请填写${field.label}';
          }
          if (field.name == 'lxfs' &&
              (v ?? '').isNotEmpty &&
              !RegExp(r'^1\d{10}$').hasMatch(v!.trim())) {
            return '请输入11位手机号';
          }
          return null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.catalog.title)),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(onPressed: _load, child: const Text('重新加载')),
                ],
              ),
            ),
          )
        : Form(
            key: _form,
            child: AbsorbPointer(
              absorbing: _busy,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    widget.catalog.subtitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 20),
                  for (final field in _session!.fields)
                    if (!field.hidden) _field(field),
                  FilledButton.icon(
                    onPressed: _busy || _activeField != null ? null : _submit,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: Text(_busy ? '正在提交…' : '提交报修'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
  );
}
