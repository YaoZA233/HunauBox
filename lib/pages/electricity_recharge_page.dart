import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/electricity_model.dart';
import '../services/app_logger.dart';
import '../services/campus_card_service.dart';
import '../services/electricity_service.dart';
import '../widgets/payment_result_sheet.dart';

class ElectricityRechargePage extends StatefulWidget {
  const ElectricityRechargePage({super.key});

  @override
  State<ElectricityRechargePage> createState() =>
      _ElectricityRechargePageState();
}

class _ElectricityRechargePageState extends State<ElectricityRechargePage> {
  final _logger = AppLogger.instance;
  final TextEditingController _amountController = TextEditingController();

  bool _isLoading = true;
  String? _error;

  List<ElectricityArea> _areas = [];
  List<ElectricityBuilding> _buildings = [];
  List<ElectricityRoom> _rooms = [];

  ElectricityArea? _selectedArea;
  ElectricityBuilding? _selectedBuilding;
  ElectricityRoom? _selectedRoom;
  ElectricityBalanceInfo? _balance;
  bool _isBalanceLoading = false;
  int _balanceRequestId = 0;

  double? _selectedAmount;
  final List<double> _presetAmounts = [10, 20, 50, 100];
  bool _isPaying = false;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final service = ElectricityService.instance;
      final savedRoom = await service.getSavedRoom();
      _areas = await service.getAreas();

      if (_areas.isNotEmpty) {
        final savedArea = savedRoom == null
            ? null
            : _areas
                  .where((area) => area.name == savedRoom.areaName)
                  .firstOrNull;
        _selectedArea = savedArea ?? _areas.first;

        _buildings = await service.getBuildings(_selectedArea!.name);
        final savedBuilding = savedRoom != null && savedArea != null
            ? _buildings
                  .where((building) => building.name == savedRoom.buildingName)
                  .firstOrNull
            : null;
        _selectedBuilding =
            savedBuilding ?? (_buildings.isNotEmpty ? _buildings.first : null);

        if (_selectedBuilding != null) {
          _rooms = await service.getRooms(
            _selectedArea!.name,
            _selectedBuilding!.name,
          );
          final savedRoomMatch = savedRoom != null && savedBuilding != null
              ? _rooms
                    .where(
                      (room) =>
                          room.id == savedRoom.roomId ||
                          room.name == savedRoom.roomName,
                    )
                    .firstOrNull
              : null;
          _selectedRoom =
              savedRoomMatch ?? (_rooms.isNotEmpty ? _rooms.first : null);
        }

        _saveCurrentSelection();
        await _loadBalance();
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      _logger.e('Failed to init electricity data: $e');
      if (mounted) {
        setState(() {
          _error = '加载列表失败，请重试';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadBuildings(String areaName) async {
    try {
      final service = ElectricityService.instance;
      final buildings = await service.getBuildings(areaName);
      if (mounted) {
        setState(() {
          _buildings = buildings;
          _selectedBuilding = buildings.isNotEmpty ? buildings.first : null;
          _rooms = [];
          _selectedRoom = null;
          _balance = null;
          _balanceRequestId++;
        });
        if (_selectedBuilding != null) {
          await _loadRooms(areaName, _selectedBuilding!.name);
        }
      }
    } catch (e) {
      _logger.w('Failed to load buildings: $e');
    }
  }

  Future<void> _loadRooms(String areaName, String buildingName) async {
    try {
      final service = ElectricityService.instance;
      final rooms = await service.getRooms(areaName, buildingName);
      if (mounted) {
        setState(() {
          _rooms = rooms;
          _selectedRoom = rooms.isNotEmpty ? rooms.first : null;
          _balance = null;
          _balanceRequestId++;
        });
        _saveCurrentSelection();
        await _loadBalance();
      }
    } catch (e) {
      _logger.w('Failed to load rooms: $e');
    }
  }

  void _saveCurrentSelection() {
    if (_selectedArea == null ||
        _selectedBuilding == null ||
        _selectedRoom == null) {
      return;
    }
    ElectricityService.instance.saveSavedRoom(
      SavedElectricityRoom(
        areaName: _selectedArea!.name,
        buildingName: _selectedBuilding!.name,
        roomId: _selectedRoom!.id,
        roomName: _selectedRoom!.name,
        mertype: _selectedRoom!.mertype,
      ),
    );
  }

  Future<void> _loadBalance() async {
    final area = _selectedArea;
    final building = _selectedBuilding;
    final room = _selectedRoom;
    if (area == null || building == null || room == null) return;

    final requestId = ++_balanceRequestId;
    if (mounted) setState(() => _isBalanceLoading = true);
    try {
      final balance = await ElectricityService.instance.getBalance(
        areaName: area.name,
        buildingName: building.name,
        roomId: room.id,
        mertype: room.mertype,
      );
      if (mounted && requestId == _balanceRequestId) {
        setState(() => _balance = balance);
      }
    } catch (e) {
      _logger.w('Failed to load electricity balance: $e');
      if (mounted && requestId == _balanceRequestId) {
        setState(() => _balance = null);
      }
    } finally {
      if (mounted && requestId == _balanceRequestId) {
        setState(() => _isBalanceLoading = false);
      }
    }
  }

  void _handlePresetAmountSelect(double amount) {
    setState(() {
      _selectedAmount = amount;
      _amountController.text = amount.toStringAsFixed(0);
    });
  }

  Future<void> _handleRecharge() async {
    if (_selectedArea == null ||
        _selectedBuilding == null ||
        _selectedRoom == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择完整的房间信息')));
      return;
    }

    final amountText = _amountController.text;
    final amount = double.tryParse(amountText);

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效的充值金额')));
      return;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => PaymentResultSheet(
        type: PaymentResultType.confirm,
        merchantName: '缴电费 (校园卡支付)',
        amount: amountText,
        onConfirm: () => Navigator.pop(context, true),
      ),
    );

    if (confirmed != true) return;

    setState(() => _isPaying = true);

    try {
      final service = ElectricityService.instance;
      final success = await service.recharge(
        areaName: _selectedArea!.name,
        buildingName: _selectedBuilding!.name,
        roomId: _selectedRoom!.id,
        mertype: _selectedRoom!.mertype,
        amount: amount,
      );

      if (mounted) {
        setState(() => _isPaying = false);
        if (success) {
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            builder: (context) => PaymentResultSheet(
              type: PaymentResultType.success,
              merchantName: '缴电费',
              amount: amountText,
            ),
          );
          CampusCardService.instance.fetchRechargeInfo();
          _loadBalance();
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('充值失败，请重试')));
        }
      }
    } catch (e) {
      _logger.e('Recharge failed: $e');
      if (mounted) {
        setState(() => _isPaying = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('充值失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('电费充值'), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _initData,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.secondaryContainer.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.bolt_rounded,
                              size: 20,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '当前充值房间',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.secondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _selectedRoom != null
                              ? '${_selectedArea?.name} - ${_selectedBuilding?.name} - ${_selectedRoom?.name}'
                              : '尚未选择房间',
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 18,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '当前电费余额',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.secondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: '刷新余额',
                              visualDensity: VisualDensity.compact,
                              onPressed: _isBalanceLoading
                                  ? null
                                  : _loadBalance,
                              icon: const Icon(Icons.refresh_rounded, size: 19),
                            ),
                          ],
                        ),
                        Text(
                          _isBalanceLoading
                              ? '查询中...'
                              : _balance == null
                              ? '暂时无法获取'
                              : '${_balance!.balance} 元',
                          style: TextStyle(
                            fontSize: 24,
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildRoomSelectionBox(
                    '校区',
                    _areas.map((e) => e.name).toList(),
                    _selectedArea?.name,
                    (val) {
                      final area = _areas.firstWhere((e) => e.name == val);
                      setState(() => _selectedArea = area);
                      _loadBuildings(area.name);
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildRoomSelectionBox(
                    '楼栋',
                    _buildings.map((e) => e.name).toList(),
                    _selectedBuilding?.name,
                    (val) {
                      final building = _buildings.firstWhere(
                        (e) => e.name == val,
                      );
                      setState(() => _selectedBuilding = building);
                      _loadRooms(_selectedArea!.name, building.name);
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildRoomSelectionBox(
                    '房间',
                    _rooms.map((e) => e.name).toList(),
                    _selectedRoom?.name,
                    (val) {
                      final room = _rooms.firstWhere((e) => e.name == val);
                      setState(() {
                        _selectedRoom = room;
                        _balance = null;
                      });
                      _saveCurrentSelection();
                      _loadBalance();
                    },
                  ),
                  const SizedBox(height: 32),
                  Text(
                    '选择充值金额',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 2.8,
                        ),
                    itemCount: _presetAmounts.length,
                    itemBuilder: (context, index) {
                      final amount = _presetAmounts[index];
                      final isSelected = _selectedAmount == amount;
                      return InkWell(
                        onTap: () => _handlePresetAmountSelect(amount),
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outlineVariant
                                        .withOpacity(0.5),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${amount.toStringAsFixed(0)}元',
                            style: TextStyle(
                              color: isSelected
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer
                                  : Theme.of(context).colorScheme.onSurface,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    decoration: InputDecoration(
                      labelText: '其他金额',
                      prefixText: '¥ ',
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        ),
                      ),
                    ),
                    onChanged: (value) => setState(
                      () => _selectedAmount = double.tryParse(value),
                    ),
                  ),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: _isPaying ? null : _handleRecharge,
                      icon: _isPaying
                          ? Container(
                              width: 20,
                              height: 20,
                              margin: const EdgeInsets.only(right: 8),
                              child: CircularProgressIndicator(
                                color: Theme.of(context).colorScheme.onPrimary,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.bolt_rounded, size: 20),
                      label: const Text(
                        '立即充值',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildRoomSelectionBox(
    String label,
    List<String> items,
    String? current,
    Function(String?) onChanged,
  ) {
    return DropdownButtonFormField<String>(
      value: items.contains(current) ? current : null,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
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
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 2,
          ),
        ),
      ),
      items: items
          .map(
            (e) => DropdownMenuItem(
              value: e,
              child: Text(
                e,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
      icon: Icon(
        Icons.expand_more_rounded,
        size: 24,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
