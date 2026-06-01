import 'package:flutter/material.dart';

import '../models/classroom_model.dart';
import '../services/classroom_service.dart';

class EmptyClassroomPage extends StatefulWidget {
  const EmptyClassroomPage({super.key});

  @override
  State<EmptyClassroomPage> createState() => _EmptyClassroomPageState();
}

class _EmptyClassroomPageState extends State<EmptyClassroomPage> {
  final _service = ClassroomService.instance;

  ClassroomInquiryOptions? _options;
  bool _loadingOptions = true;
  bool _searching = false;
  String? _errorMessage;
  List<ClassroomModel> _classrooms = [];

  String? _selectedBuilding;
  String? _selectedWeek;
  String? _selectedSection;
  String? _selectedDay;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loadingOptions = true;
      _errorMessage = null;
    });

    try {
      final options = await _service.fetchOptions();
      if (!mounted) return;

      setState(() {
        _options = options;
        _loadingOptions = false;
        _selectedBuilding = options.buildings.isNotEmpty ? options.buildings.first : null;
        _selectedWeek = options.weeks.isNotEmpty ? options.weeks.first : null;
        _selectedSection = options.sections.isNotEmpty ? options.sections.first : null;
        _selectedDay = options.days.isNotEmpty ? options.days.first['value'] : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingOptions = false;
        _errorMessage = '加载查询条件失败，请稍后重试';
      });
    }
  }

  Future<void> _search() async {
    if (_selectedBuilding == null || _selectedWeek == null || _selectedSection == null || _selectedDay == null) {
      return;
    }

    setState(() {
      _searching = true;
      _errorMessage = null;
    });

    try {
      final results = await _service.queryClassrooms(
        building: _selectedBuilding!,
        week: _selectedWeek!,
        jc: _selectedSection!,
        day: _selectedDay!,
      );

      if (!mounted) return;
      setState(() {
        _classrooms = results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _errorMessage = '查询失败，请检查登录状态后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('空教室查询'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _loadingOptions ? null : _loadOptions,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '重新加载',
          ),
        ],
      ),
      body: _loadingOptions
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadOptions,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  _buildIntroCard(),
                  const SizedBox(height: 24),
                  _buildSearchPanel(),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    _buildErrorBanner(_errorMessage!),
                  ],
                  const SizedBox(height: 16),
                  _buildResultSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildIntroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.tertiaryContainer.withOpacity(0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.meeting_room_rounded, color: Theme.of(context).colorScheme.tertiary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '空教室查询',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
                ),
                const SizedBox(height: 6),
                Text(
                  '选择教学楼、周次、节次和星期后即可查询可用教室。',
                  style: TextStyle(fontSize: 13, height: 1.4, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchPanel() {
    final options = _options;
    if (options == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildDropdownField(
                  label: '教学楼',
                  items: options.buildings,
                  value: _selectedBuilding,
                  onChanged: (value) => setState(() => _selectedBuilding = value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdownField(
                  label: '周次',
                  items: options.weeks,
                  value: _selectedWeek,
                  onChanged: (value) => setState(() => _selectedWeek = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDropdownField(
                  label: '节次',
                  items: options.sections,
                  value: _selectedSection,
                  onChanged: (value) => setState(() => _selectedSection = value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdownField(
                  label: '星期',
                  items: options.days.map((e) => e['label'] ?? '').where((value) => value.isNotEmpty).toList(),
                  value: _selectedDay == null
                      ? null
                      : options.days.firstWhere(
                          (item) => item['value'] == _selectedDay,
                          orElse: () => options.days.first,
                        )['label'],
                  onChanged: (label) {
                    final matched = options.days.cast<Map<String, String>>().firstWhere(
                          (item) => item['label'] == label,
                          orElse: () => options.days.first,
                        );
                    setState(() => _selectedDay = matched['value']);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _searching ? null : _search,
              icon: _searching
                  ? Container(
                      width: 16,
                      height: 16,
                      margin: const EdgeInsets.only(right: 8),
                      child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary),
                    )
                  : const Icon(Icons.search_rounded, size: 20),
              label: Text(_searching ? '查询中' : '查询', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required List<String> items,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          icon: Icon(Icons.expand_more_rounded, size: 20, color: theme.colorScheme.onSurfaceVariant),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
            ),
          ),
          dropdownColor: theme.colorScheme.surface,
          items: items
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(item, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.error.withOpacity(0.2)),
      ),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
      ),
    );
  }

  Widget _buildResultSection() {
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.only(top: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_classrooms.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 56),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(Icons.hourglass_empty_rounded, size: 42, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              '暂无查询结果',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              '调整条件后再试一次',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7), fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '查询结果（${_classrooms.length}）',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
          ),
        ),
        ..._classrooms.map((room) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.meeting_room_rounded, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.jsmc,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '可容纳人数：${room.zws}',
                        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}