import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

class NetworkSpeedTestPage extends StatefulWidget {
  const NetworkSpeedTestPage({super.key});

  @override
  State<NetworkSpeedTestPage> createState() => _NetworkSpeedTestPageState();
}

class _NetworkSpeedTestPageState extends State<NetworkSpeedTestPage>
    with SingleTickerProviderStateMixin {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  CancelToken? _cancelToken;

  bool _isTesting = false;
  double _currentSpeedMbps = 0.0;
  double _avgSpeedMbps = 0.0;
  double _progress = 0.0;
  String _networkQuality = '--';
  IconData _qualityIcon = Icons.wifi_find;
  Color _qualityColor = Colors.grey;

  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _dio.close();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _startTest() async {
    final colors = Theme.of(context).colorScheme;
    if (_isTesting) {
      _cancelToken?.cancel("用户取消测速");
      setState(() {
        _isTesting = false;
        _progress = 0;
        _currentSpeedMbps = 0;
        _networkQuality = '已取消';
        _qualityColor = colors.tertiary;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _currentSpeedMbps = 0.0;
      _avgSpeedMbps = 0.0;
      _progress = 0.0;
      _networkQuality = '测速中...';
      _qualityIcon = Icons.sensors;
      _qualityColor = colors.primary;
    });

    _cancelToken = CancelToken();

    // 多个测速地址，优先使用国内 CDN
    const List<String> testUrls = [
      'https://speed.cloudflare.com/__down?bytes=10485760',
      'https://dldir1.qq.com/qqfile/qq/PCQQ9.7.17/QQ9.7.17.29225.exe',
    ];

    int startTime = DateTime.now().millisecondsSinceEpoch;
    int lastCalcTime = startTime;
    int lastReceivedBytes = 0;

    final List<double> speedSamples = [];
    bool testCompleted = false;

    for (final testUrl in testUrls) {
      if (testCompleted) break;

      try {
        await _dio.get(
          testUrl,
          cancelToken: _cancelToken,
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 30),
          ),
          onReceiveProgress: (received, total) {
            final int now = DateTime.now().millisecondsSinceEpoch;
            final int timePassed = now - lastCalcTime;

            // 每 200 毫秒刷新一次 UI 和瞬时速度
            if (timePassed >= 200 || (total > 0 && received == total)) {
              final int bytesPassed = received - lastReceivedBytes;
              if (bytesPassed > 0 && timePassed > 0) {
                final double speedBytesPerSec =
                    bytesPassed / (timePassed / 1000.0);
                final double speedMbps = (speedBytesPerSec * 8) / (1024 * 1024);

                if (speedMbps > 0) {
                  speedSamples.add(speedMbps);
                }

                if (mounted) {
                  setState(() {
                    _currentSpeedMbps = speedMbps;
                    if (total > 0) {
                      _progress = received / total;
                    } else {
                      _progress = (received / (10 * 1024 * 1024)).clamp(
                        0.0,
                        0.99,
                      );
                    }
                  });
                }
              }

              lastCalcTime = now;
              lastReceivedBytes = received;
            }
          },
        );

        testCompleted = true;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
          debugPrint('测速已取消');
          testCompleted = true;
        } else {
          debugPrint('测速地址 $testUrl 失败: ${e.message}，尝试下一个...');
        }
      }
    }

    if (testCompleted && speedSamples.isNotEmpty) {
      _calculateFinalResult(speedSamples);
    } else if (!testCompleted) {
      if (mounted) {
        setState(() {
          _isTesting = false;
          _networkQuality = '测速失败';
          _qualityIcon = Icons.error_outline;
          _qualityColor = colors.error;
        });
      }
    }
  }

  void _calculateFinalResult(List<double> samples) {
    if (!mounted) return;
    final colors = Theme.of(context).colorScheme;

    double avg = 0;
    if (samples.isNotEmpty) {
      // 排除极端抖动的数据（去掉最高和最低的一部分，取稳定的平均值）
      samples.sort();
      int dropCount = (samples.length * 0.1).floor(); // 丢弃前后 10%
      final validSamples = samples.sublist(
        dropCount,
        samples.length - dropCount,
      );
      if (validSamples.isNotEmpty) {
        avg = validSamples.reduce((a, b) => a + b) / validSamples.length;
      } else {
        avg = samples.reduce((a, b) => a + b) / samples.length;
      }
    }

    String desc = '--';
    Color color = colors.outline;
    IconData icon = Icons.wifi;

    if (avg >= 50) {
      desc = '极佳';
      color = colors.primary;
      icon = Icons.network_wifi_3_bar;
    } else if (avg >= 20) {
      desc = '流畅';
      color = colors.secondary;
      icon = Icons.network_wifi_2_bar;
    } else if (avg >= 5) {
      desc = '一般';
      color = colors.tertiary;
      icon = Icons.network_wifi_1_bar;
    } else {
      desc = '较差';
      color = colors.error;
      icon = Icons.network_wifi_1_bar;
    }

    setState(() {
      _isTesting = false;
      _avgSpeedMbps = avg;
      _currentSpeedMbps = avg; // 展示最终平均值
      _networkQuality = desc;
      _qualityColor = color;
      _qualityIcon = icon;
      _progress = 1.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: Text(
          '测速工具',
          style: TextStyle(
            color: colors.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.onSurface),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),

              // 测速仪表盘 UI
              Center(
                child: SizedBox(
                  width: 260,
                  height: 260,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 外圈光晕动画
                      if (_isTesting)
                        ScaleTransition(
                          scale: _scaleAnimation,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colors.primary.withValues(alpha: 0.15),
                            ),
                          ),
                        ),

                      // 进度环
                      SizedBox(
                        width: 240,
                        height: 240,
                        child: CircularProgressIndicator(
                          value: _isTesting ? _progress : 1.0,
                          strokeWidth: 8,
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _isTesting ? colors.primary : _qualityColor,
                          ),
                        ),
                      ),

                      // 内部数值展示
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _qualityIcon,
                            size: 36,
                            color: _isTesting ? colors.primary : _qualityColor,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _currentSpeedMbps.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              color: _isTesting
                                  ? colors.onSurface
                                  : _qualityColor,
                            ),
                          ),
                          const Text(
                            'Mbps',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // 测速信息卡片
              Container(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildInfoColumn('网络质量', _networkQuality, _qualityColor),
                    Container(
                      height: 40,
                      width: 1,
                      color: Colors.grey.withValues(alpha: 0.2),
                    ),
                    _buildInfoColumn(
                      '平均网速',
                      '${_avgSpeedMbps.toStringAsFixed(1)} M',
                      colors.onSurface,
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // 操作按钮
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _startTest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isTesting ? colors.error : colors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _isTesting ? '停止测速' : '开始测速',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoColumn(String title, String value, Color valueColor) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
