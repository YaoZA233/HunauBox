import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/electricity_model.dart';
import '../services/app_logger.dart';
import '../services/campus_card_service.dart';
import '../services/electricity_service.dart';
import '../services/finance_cache_store.dart';
import '../widgets/campus_card_payment_sheet.dart';
import '../widgets/payment_result_sheet.dart';
import '../widgets/campus_loading_mark.dart';

enum _ElectricityPaymentMethod { campusCard, wechat, alipay }

class ElectricityRechargePage extends StatefulWidget {
  const ElectricityRechargePage({super.key, this.roomSlot = 0, this.service})
    : assert(roomSlot >= 0 && roomSlot <= 1);

  final int roomSlot;
  final ElectricityService? service;

  @override
  State<ElectricityRechargePage> createState() =>
      _ElectricityRechargePageState();
}

class _ElectricityRechargePageState extends State<ElectricityRechargePage> {
  final _logger = AppLogger.instance;
  final TextEditingController _amountController = TextEditingController();

  bool _isLoading = true;
  String? _error;
  bool _editingRoom = false;
  String? _balanceError;
  DateTime? _balanceUpdatedAt;

  List<ElectricityArea> _areas = [];
  List<ElectricityBuilding> _buildings = [];
  List<ElectricityRoom> _rooms = [];

  ElectricityArea? _selectedArea;
  ElectricityBuilding? _selectedBuilding;
  ElectricityRoom? _selectedRoom;
  ElectricityBalanceInfo? _balance;
  bool _isBalanceLoading = false;
  int _balanceRequestId = 0;
  Future<void> _selectionSave = Future<void>.value();
  bool _isSavingSelection = false;
  bool _isReturning = false;

  double? _selectedAmount;
  final List<double> _presetAmounts = [10, 20, 50, 100];
  bool _isPaying = false;
  _ElectricityPaymentMethod _paymentMethod =
      _ElectricityPaymentMethod.campusCard;

  ElectricityService get _service =>
      widget.service ?? ElectricityService.instance;

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

  Future<void> _initData({bool editRoom = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final service = _service;
      final savedRoom = await service.getSavedRoom(slot: widget.roomSlot);
      if (!mounted || _isReturning) return;
      if (savedRoom != null && !editRoom) {
        final snapshot = await FinanceCacheStore.read(
          ElectricityService.balanceCacheKey(savedRoom),
        );
        if (!mounted || _isReturning) return;
        setState(() {
          _selectedArea = ElectricityArea(
            id: savedRoom.areaName,
            name: savedRoom.areaName,
          );
          _selectedBuilding = ElectricityBuilding(
            id: savedRoom.buildingName,
            name: savedRoom.buildingName,
          );
          _selectedRoom = ElectricityRoom(
            id: savedRoom.roomId,
            name: savedRoom.roomName,
            mertype: savedRoom.mertype,
          );
          _balance = snapshot == null
              ? null
              : ElectricityBalanceInfo.fromJson(snapshot.data);
          _balanceUpdatedAt = snapshot?.updatedAt;
          _isLoading = false;
          _editingRoom = false;
        });
        await _loadBalance();
        return;
      }
      _editingRoom = true;
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

        await _saveCurrentSelection();
        if (mounted && !_isReturning) _loadBalance();
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
      final service = _service;
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
      final service = _service;
      final rooms = await service.getRooms(areaName, buildingName);
      if (mounted) {
        setState(() {
          _rooms = rooms;
          _selectedRoom = rooms.isNotEmpty ? rooms.first : null;
          _balance = null;
          _balanceRequestId++;
        });
        await _saveCurrentSelection();
        await _loadBalance();
      }
    } catch (e) {
      _logger.w('Failed to load rooms: $e');
    }
  }

  Future<void> _saveCurrentSelection() async {
    if (!mounted ||
        _isReturning ||
        _selectedArea == null ||
        _selectedBuilding == null ||
        _selectedRoom == null) {
      return;
    }
    final room = SavedElectricityRoom(
      areaName: _selectedArea!.name,
      buildingName: _selectedBuilding!.name,
      roomId: _selectedRoom!.id,
      roomName: _selectedRoom!.name,
      mertype: _selectedRoom!.mertype,
    );
    // Serialize writes so a slower earlier selection cannot replace a newer one.
    final save = _selectionSave.then(
      (_) => _service.saveSavedRoom(room, slot: widget.roomSlot),
    );
    _selectionSave = save;
    if (mounted) setState(() => _isSavingSelection = true);
    await save;
    if (mounted && identical(_selectionSave, save)) {
      setState(() => _isSavingSelection = false);
    }
  }

  Future<void> _handleBackNavigation(bool didPop, Object? result) async {
    if (didPop) {
      _isReturning = true;
      return;
    }
    if (_isReturning) return;
    _isReturning = true;
    // The overview must read the completed write when this route returns.
    while (mounted && _isSavingSelection) {
      await _selectionSave;
    }
    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> _loadBalance() async {
    final area = _selectedArea;
    final building = _selectedBuilding;
    final room = _selectedRoom;
    if (area == null || building == null || room == null) return;

    final requestId = ++_balanceRequestId;
    if (mounted) {
      setState(() {
        _isBalanceLoading = true;
        _balanceError = null;
      });
    }
    try {
      final balance = await _service.getBalance(
        areaName: area.name,
        buildingName: building.name,
        roomId: room.id,
        mertype: room.mertype,
      );
      if (mounted && requestId == _balanceRequestId) {
        setState(() {
          _balance = balance;
          _balanceUpdatedAt = DateTime.now();
        });
      }
    } catch (e) {
      _logger.w('Failed to load electricity balance: $e');
      if (mounted && requestId == _balanceRequestId) {
        setState(
          () => _balanceError = _balance == null ? '余额查询失败，请重试' : '更新失败，显示上次余额',
        );
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

    final amountText = _amountController.text.trim();
    final amount = int.tryParse(amountText);

    if (amount == null || amount < 1 || amount > 1000) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入 1–1000 元的整数金额')));
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
      final service = _service;
      final success = await service.recharge(
        areaName: _selectedArea!.name,
        buildingName: _selectedBuilding!.name,
        roomId: _selectedRoom!.id,
        roomName: _selectedRoom!.name,
        mertype: _selectedRoom!.mertype,
        amount: amount.toDouble(),
        roomSlot: widget.roomSlot,
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

  Future<void> _handleThirdPartyRecharge(PaymentMethod method) async {
    final area = _selectedArea;
    final building = _selectedBuilding;
    final room = _selectedRoom;
    if (area == null || building == null || room == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择完整的房间信息')));
      return;
    }

    final amountText = _amountController.text.trim();
    final amount = int.tryParse(amountText);
    if (amount == null || amount < 1 || amount > 1000) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入 1–1000 元的整数金额')));
      return;
    }

    late final CampusCardInfo cardInfo;
    setState(() => _isPaying = true);
    try {
      // 支付结果通过校园卡余额增长确认，因此必须以本次下单前的实时余额为基线。
      cardInfo = await CampusCardService.instance.fetchRechargeInfo();
    } catch (e) {
      _logger.e('Failed to fetch card info for electricity recharge: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('获取校园卡信息失败: $e')));
      }
      return;
    } finally {
      if (mounted) setState(() => _isPaying = false);
    }
    if (!mounted) return;

    final roomDescription = '${area.name} ${building.name} ${room.name}';
    await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => CampusCardPaymentSheet(
        amount: amountText,
        merchantName: '缴电费·$roomDescription',
        info: cardInfo,
        paymentMethod: method,
        successTitle: '电费充值成功',
        onCardRechargeSuccess: () async {
          final success = await _service.recharge(
            areaName: area.name,
            buildingName: building.name,
            roomId: room.id,
            roomName: room.name,
            mertype: room.mertype,
            amount: amount.toDouble(),
            roomSlot: widget.roomSlot,
          );
          if (!success) throw Exception('电费充值失败');
        },
      ),
    );

    if (!mounted) return;
    try {
      await CampusCardService.instance.fetchRechargeInfo();
    } catch (e) {
      _logger.w('Failed to refresh card info after payment: $e');
    }
    await _loadBalance();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_isSavingSelection,
      onPopInvokedWithResult: _handleBackNavigation,
      child: _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final amount = int.tryParse(_amountController.text.trim());
    final canRecharge = _selectedRoom != null &&
        amount != null &&
        amount >= 1 &&
        amount <= 1000 &&
        !_isPaying;
    return Scaffold(
      appBar: AppBar(
        title: const Text('电费充值'),
        actions: [
          IconButton(
            tooltip: '刷新电费余额',
            onPressed: _isBalanceLoading || _selectedRoom == null
                ? null
                : _loadBalance,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CampusLoadingMark(size: 36))
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
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        border: Border.all(color: colors.outlineVariant),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.bolt_rounded, color: colors.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '当前用电房间',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (!_editingRoom)
                                TextButton.icon(
                                  onPressed: () => _initData(editRoom: true),
                                  icon: const Icon(Icons.edit_outlined, size: 17),
                                  label: const Text('更换房间'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selectedRoom == null
                                ? '尚未选择房间'
                                : '${_selectedArea?.name} · ${_selectedBuilding?.name} · ${_selectedRoom?.name}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Divider(height: 1, color: colors.outlineVariant),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '电费余额',
                                      style: Theme.of(context).textTheme.bodySmall
                                          ?.copyWith(color: colors.onSurfaceVariant),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _balance == null
                                          ? (_isBalanceLoading ? '查询中' : '--')
                                          : '${_balance!.balance} 元',
                                      style: Theme.of(context).textTheme.headlineSmall
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ),
                              if (_isBalanceLoading)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 6),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CampusLoadingMark(size: 16),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _balanceError ??
                                (_balanceUpdatedAt == null
                                    ? '余额尚未更新'
                                    : '更新于 ${_balanceUpdatedAt!.month}/${_balanceUpdatedAt!.day} ${_balanceUpdatedAt!.hour.toString().padLeft(2, '0')}:${_balanceUpdatedAt!.minute.toString().padLeft(2, '0')}'),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _balanceError == null
                                  ? colors.onSurfaceVariant
                                  : colors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_editingRoom) ...[
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 10),
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
                      const SizedBox(height: 10),
                      _buildRoomSelectionBox(
                        '房间',
                        _rooms.map((e) => e.name).toList(),
                        _selectedRoom?.name,
                        (val) async {
                          final room = _rooms.firstWhere((e) => e.name == val);
                          setState(() {
                            _selectedRoom = room;
                            _balance = null;
                          });
                          await _saveCurrentSelection();
                          await _loadBalance();
                        },
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            '充值金额',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '1–1000 元',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 2.8,
                          ),
                      itemCount: _presetAmounts.length,
                      itemBuilder: (context, index) => _ElectricityAmountOption(
                        amount: _presetAmounts[index],
                        selected: _selectedAmount == _presetAmounts[index],
                        onTap: () =>
                            _handlePresetAmountSelect(_presetAmounts[index]),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: '其他金额',
                        prefixText: '¥ ',
                        suffixText: '元',
                        filled: true,
                        fillColor: colors.surfaceContainerLow,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: colors.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: colors.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: colors.primary, width: 1.5),
                        ),
                      ),
                      onChanged: (value) => setState(
                        () => _selectedAmount = double.tryParse(value),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '支付方式',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          avatar: const Icon(Icons.credit_card_outlined, size: 18),
                          label: const Text('校园卡'),
                          selected: _paymentMethod ==
                              _ElectricityPaymentMethod.campusCard,
                          onSelected: (_) => setState(() => _paymentMethod =
                              _ElectricityPaymentMethod.campusCard),
                        ),
                        ChoiceChip(
                          avatar: SvgPicture.string(kWechatSvg, width: 18, height: 18),
                          label: const Text('微信支付'),
                          selected: _paymentMethod ==
                              _ElectricityPaymentMethod.wechat,
                          onSelected: (_) => setState(() => _paymentMethod =
                              _ElectricityPaymentMethod.wechat),
                        ),
                        ChoiceChip(
                          avatar: SvgPicture.string(kAlipaySvg, width: 18, height: 18),
                          label: const Text('支付宝'),
                          selected: _paymentMethod ==
                              _ElectricityPaymentMethod.alipay,
                          onSelected: (_) => setState(() => _paymentMethod =
                              _ElectricityPaymentMethod.alipay),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _isLoading || _error != null
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(top: BorderSide(color: colors.outlineVariant)),
                ),
                child: SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: canRecharge
                        ? () {
                            switch (_paymentMethod) {
                              case _ElectricityPaymentMethod.campusCard:
                                _handleRecharge();
                                break;
                              case _ElectricityPaymentMethod.wechat:
                                _handleThirdPartyRecharge(PaymentMethod.wechat);
                                break;
                              case _ElectricityPaymentMethod.alipay:
                                _handleThirdPartyRecharge(PaymentMethod.alipay);
                                break;
                            }
                          }
                        : null,
                    child: _isPaying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CampusLoadingMark(size: 16, color: Colors.white),
                          )
                        : Text(
                            canRecharge
                                ? '确认充值  ¥${amount.toString()}'
                                : '选择充值金额',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
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
      key: ValueKey('$label:$current'),
      initialValue: items.contains(current) ? current : null,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 1.5,
          ),
        ),
      ),
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: onChanged,
    );
  }

}

class _ElectricityAmountOption extends StatelessWidget {
  const _ElectricityAmountOption({
    required this.amount,
    required this.selected,
    required this.onTap,
  });

  final double amount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.primaryContainer : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Text(
            '¥ ${amount.toStringAsFixed(0)}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: selected ? colors.onPrimaryContainer : colors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
