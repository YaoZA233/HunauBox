import 'package:flutter/material.dart';

import '../models/classroom_model.dart';
import '../services/classroom_service.dart';
import '../widgets/campus_loading_mark.dart';

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
  bool _hasSearched = false;
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
        _selectedBuilding = options.buildings.isNotEmpty
            ? options.buildings.first
            : null;
        _selectedWeek = options.weeks.isNotEmpty ? options.weeks.first : null;
        _selectedSection = options.sections.isNotEmpty
            ? options.sections.first
            : null;
        _selectedDay = options.days.isNotEmpty
            ? options.days.first['value']
            : null;
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
    if (_selectedBuilding == null ||
        _selectedWeek == null ||
        _selectedSection == null ||
        _selectedDay == null) {
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
        _hasSearched = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _errorMessage = '查询失败，请检查登录状态后重试';
      });
    }
  }

  void _updateSelection(VoidCallback update) {
    setState(() {
      update();
      _classrooms = [];
      _hasSearched = false;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('空教室查询'),
        actions: [
          IconButton(
            onPressed: _loadingOptions ? null : _loadOptions,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '重新加载',
          ),
        ],
      ),
      body: _loadingOptions
          ? const Center(child: CampusLoadingMark(size: 38))
          : RefreshIndicator(
              onRefresh: _loadOptions,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                children: [
                  _buildIntroCard(),
                  const SizedBox(height: 18),
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
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.meeting_room_outlined, color: colors.primary, size: 22),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            '按教学时段查找可用教室',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchPanel() {
    final options = _options;
    if (options == null) {
      return const SizedBox.shrink();
    }

    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '查询条件',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildDropdownField(
                  label: '教学楼',
                  items: options.buildings,
                  value: _selectedBuilding,
                  onChanged: _searching
                      ? null
                      : (value) =>
                            _updateSelection(() => _selectedBuilding = value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdownField(
                  label: '周次',
                  items: options.weeks,
                  value: _selectedWeek,
                  onChanged: _searching
                      ? null
                      : (value) =>
                            _updateSelection(() => _selectedWeek = value),
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
                  onChanged: _searching
                      ? null
                      : (value) =>
                            _updateSelection(() => _selectedSection = value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdownField(
                  label: '星期',
                  items: options.days
                      .map((e) => e['label'] ?? '')
                      .where((value) => value.isNotEmpty)
                      .toList(),
                  value: _selectedDay == null
                      ? null
                      : options.days.firstWhere(
                          (item) => item['value'] == _selectedDay,
                          orElse: () => options.days.first,
                        )['label'],
                  onChanged: _searching
                      ? null
                      : (label) {
                          final matched = options.days
                              .cast<Map<String, String>>()
                              .firstWhere(
                                (item) => item['label'] == label,
                                orElse: () => options.days.first,
                              );
                          _updateSelection(
                            () => _selectedDay = matched['value'],
                          );
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _searching ? null : _search,
              icon: _searching
                  ? const CampusLoadingMark(size: 20, color: Colors.white)
                  : const Icon(Icons.search_rounded, size: 20),
              label: Text(
                _searching ? '查询中' : '查询空教室',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
    required ValueChanged<String?>? onChanged,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          icon: Icon(
            Icons.expand_more_rounded,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(
              0.3,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
                width: 1.4,
              ),
            ),
          ),
          dropdownColor: theme.colorScheme.surface,
          items: items
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(
                    item,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildErrorBanner(String message) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: colors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultSection() {
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: CampusLoadingMark(size: 34)),
      );
    }

    if (_classrooms.isEmpty) {
      final colors = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 38),
        child: Column(
          children: [
            Icon(
              _hasSearched ? Icons.search_off : Icons.tune,
              size: 30,
              color: colors.outline,
            ),
            const SizedBox(height: 10),
            Text(
              _hasSearched ? '这个时段没有空教室' : '选择条件后开始查询',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
            ),
            if (_hasSearched) ...[
              const SizedBox(height: 5),
              Text(
                '试试更换教学楼或时段',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
          ],
        ),
      );
    }

    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 2),
          child: Row(
            children: [
              Text(
                '可用教室',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${_classrooms.length} 间',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        for (var i = 0; i < _classrooms.length; i++) ...[
          _ClassroomRow(room: _classrooms[i]),
          if (i < _classrooms.length - 1)
            Divider(height: 1, color: colors.outlineVariant),
        ],
      ],
    );
  }
}

class _ClassroomRow extends StatelessWidget {
  const _ClassroomRow({required this.room});

  final ClassroomModel room;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(Icons.meeting_room_outlined, size: 20, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              room.jsmc,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${room.zws} 座',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
