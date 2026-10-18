import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/leave_application.dart';
import '../models/leave_models.dart';
import '../services/leave_service.dart';

class LeaveApplyPage extends StatefulWidget {
  final LeaveService service;
  const LeaveApplyPage({super.key, required this.service});
  @override
  State<LeaveApplyPage> createState() => _LeaveApplyPageState();
}

class _LeaveApplyPageState extends State<LeaveApplyPage> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController(),
      _contact = TextEditingController(),
      _phone = TextEditingController(),
      _companions = TextEditingController(),
      _address = TextEditingController(),
      _remark = TextEditingController();
  List<LeaveDictItem> _types = [];
  List<RegionNode> _regions = [];
  LeaveDictItem? _type;
  RegionNode? _province, _city, _county;
  DateTime? _start, _end;
  LeaveDuration? _duration;
  XFile? _attachment;
  bool _loading = true,
      _busy = false,
      _calculating = false,
      _pickingImage = false;
  bool _leaveSchool = false,
      _backDorm = false,
      _outCity = false,
      _outProvince = false;
  String? _loadError, _durationError;
  int _calculationVersion = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _reason,
      _contact,
      _phone,
      _companions,
      _address,
      _remark,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait<Object>([
        widget.service.fetchTypes(),
        widget.service.fetchRegions(),
      ]);
      if (!mounted) return;
      final types = results[0] as List<LeaveDictItem>;
      if (types.isEmpty) throw const LeaveException('学校未返回请假类型，请重试');
      setState(() {
        _types = types;
        _regions = results[1] as List<RegionNode>;
        _type = types.first;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick(bool isStart) async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    var initial =
        (isStart ? _start : _end) ?? (!isStart ? _start : null) ?? now;
    if (initial.isBefore(first)) initial = first;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: first.add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    final value = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!isStart && _start != null && !value.isAfter(_start!)) {
      _message('结束时间必须晚于开始时间');
      return;
    }
    setState(() {
      if (isStart) {
        _start = value;
        if (_end != null && !_end!.isAfter(value)) _end = null;
      } else {
        _end = value;
      }
      _duration = null;
      _durationError = null;
    });
    await _calculate();
  }

  Future<void> _calculate() async {
    final version = ++_calculationVersion;
    final start = _start, end = _end;
    setState(() {
      _duration = null;
      _durationError = null;
      _calculating = start != null && end != null;
    });
    if (start == null || end == null) return;
    try {
      final result = await widget.service.calculate(
        LeaveApplication.formatTime(start),
        LeaveApplication.formatTime(end),
      );
      if (!mounted || version != _calculationVersion) return;
      if (result.days < 0 || result.hours < 0 || result.hours > 23) {
        throw const LeaveException('学校返回的请假时长异常');
      }
      setState(() => _duration = result);
    } catch (e) {
      if (mounted && version == _calculationVersion) {
        setState(() => _durationError = '$e');
      }
    } finally {
      if (mounted && version == _calculationVersion) {
        setState(() => _calculating = false);
      }
    }
  }

  Future<void> _pickAttachment() async {
    setState(() => _pickingImage = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (mounted && image != null) setState(() => _attachment = image);
    } catch (_) {
      if (mounted) _message('无法读取照片，请检查相册权限后重试');
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  LeaveApplication get _application => LeaveApplication(
    type: _type,
    start: _start,
    end: _end,
    duration: _duration,
    reason: _reason.text,
    contact: _contact.text,
    phone: _phone.text,
    companions: _companions.text,
    address: _address.text,
    remark: _remark.text,
    leaveSchool: _leaveSchool,
    backDorm: _backDorm,
    outCity: _outCity,
    outProvince: _outProvince,
    destination: _county ?? _city ?? _province,
  );

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _submit() async {
    if (_busy || _calculating || _pickingImage) return;
    final valid = _form.currentState!.validate();
    final application = _application;
    if (!valid || application.validationError != null) {
      _message(application.validationError ?? '请检查必填信息');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.service.submit(
        fields: application.toFields(),
        attachmentPath: _attachment?.path,
      );
      if (!mounted) return;
      _message('请假申请已提交');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _message('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _text(
    String label,
    TextEditingController controller, {
    bool required = false,
    bool phone = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      keyboardType: phone
          ? TextInputType.phone
          : lines > 1
          ? TextInputType.multiline
          : TextInputType.text,
      minLines: lines,
      maxLines: lines > 1 ? lines + 3 : 1,
      decoration: InputDecoration(
        labelText: '$label${required ? ' *' : '（选填）'}',
        alignLabelWithHint: lines > 1,
      ),
      validator: (value) {
        if (required && (value ?? '').trim().isEmpty) return '请填写$label';
        if (phone && !RegExp(r'^1\d{10}$').hasMatch((value ?? '').trim())) {
          return '请输入11位手机号';
        }
        return null;
      },
    ),
  );
  Widget _region(
    String label,
    List<RegionNode> nodes,
    RegionNode? selected,
    ValueChanged<RegionNode?> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<RegionNode>(
      key: ValueKey(
        '$label-${selected?.id}-${nodes.map((n) => n.id).join(',')}',
      ),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(labelText: '$label *'),
      items: nodes
          .map(
            (n) => DropdownMenuItem(
              value: n,
              child: Text(n.name, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: onChanged,
      validator: (v) => v == null ? '请选择$label' : null,
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('申请请假')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _loadError != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_loadError!),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _load, child: const Text('重新加载')),
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
                  Text('请假信息', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<LeaveDictItem>(
                    key: ValueKey(_type?.id),
                    initialValue: _type,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '请假类型 *'),
                    items: _types
                        .map(
                          (t) =>
                              DropdownMenuItem(value: t, child: Text(t.name)),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _type = v),
                  ),
                  const SizedBox(height: 16),
                  for (final isStart in [true, false])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: TextFormField(
                        key: ValueKey(
                          '${isStart ? 'start' : 'end'}-${isStart ? _start : _end}',
                        ),
                        readOnly: true,
                        initialValue: (isStart ? _start : _end) == null
                            ? ''
                            : LeaveApplication.formatTime(
                                (isStart ? _start : _end)!,
                              ),
                        decoration: InputDecoration(
                          labelText: '${isStart ? '开始' : '结束'}时间 *',
                          suffixIcon: const Icon(Icons.calendar_month_outlined),
                        ),
                        onTap: () => _pick(isStart),
                        validator: (v) => (v ?? '').isEmpty ? '请选择时间' : null,
                      ),
                    ),
                  if (_calculating) const LinearProgressIndicator(),
                  if (_duration != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        '请假时长：${_duration!.label.isEmpty ? '不足1小时' : _duration!.label}',
                      ),
                    ),
                  if (_durationError != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_durationError!),
                      trailing: TextButton(
                        onPressed: _calculate,
                        child: const Text('重新计算'),
                      ),
                    ),
                  _text('请假事由', _reason, required: true, lines: 3),
                  _text('紧急联系人', _contact, required: true),
                  _text('紧急联系人电话', _phone, required: true, phone: true),
                  _text('同行人员', _companions),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('是否离校'),
                    value: _leaveSchool,
                    onChanged: (v) => setState(() => _leaveSchool = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('是否返宿'),
                    value: _backDorm,
                    onChanged: (v) => setState(() => _backDorm = v),
                  ),
                  if (_leaveSchool) ...[
                    const SizedBox(height: 16),
                    _region(
                      '省份',
                      _regions,
                      _province,
                      (v) => setState(() {
                        _province = v;
                        _city = null;
                        _county = null;
                      }),
                    ),
                    if (_province != null && _province!.children.isNotEmpty)
                      _region(
                        '城市',
                        _province!.children,
                        _city,
                        (v) => setState(() {
                          _city = v;
                          _county = null;
                        }),
                      ),
                    if (_city != null && _city!.children.isNotEmpty)
                      _region(
                        '区县',
                        _city!.children,
                        _county,
                        (v) => setState(() => _county = v),
                      ),
                    _text('离校详细地址', _address, required: true),
                    _text('离校备注', _remark, required: true, lines: 2),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('是否出市'),
                      value: _outCity,
                      onChanged: _outProvince
                          ? null
                          : (v) => setState(() => _outCity = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('是否出省'),
                      value: _outProvince,
                      onChanged: (v) => setState(() {
                        _outProvince = v;
                        if (v) _outCity = true;
                      }),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    '证明附件（选填）',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_attachment != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(_attachment!.path),
                        height: 160,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Text('图片无法预览，可移除后重新选择'),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _attachment!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: '移除附件',
                        onPressed: () => setState(() => _attachment = null),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ],
                  OutlinedButton.icon(
                    onPressed: _pickingImage ? null : _pickAttachment,
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      _pickingImage
                          ? '正在读取…'
                          : _attachment == null
                          ? '选择图片'
                          : '更换图片',
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _busy || _calculating || _pickingImage
                        ? null
                        : _submit,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_busy ? '正在提交…' : '提交申请'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
  );
}
