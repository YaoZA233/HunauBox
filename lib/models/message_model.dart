/// 通知消息数据模型
class MessageModel {
  final String idCode;
  final String title;
  final String content;
  final String createrName;
  final String sendTime;
  final bool isRead;
  final bool hasRedDot;
  final int countAll;
  final int countRead;
  final String uuid;
  
  const MessageModel({
    required this.idCode,
    required this.title,
    required this.content,
    required this.createrName,
    required this.sendTime,
    required this.isRead,
    required this.hasRedDot,
    required this.countAll,
    required this.countRead,
    this.uuid = '',
  });
  
  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      idCode: json['idCode'] as String? ?? '',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      createrName: json['createrName'] as String? ?? '',
      sendTime: json['sendTime'] as String? ?? '',
      isRead: json['isRead'] == '1',
      hasRedDot: json['redDot'] == '0',
      countAll: json['countAll'] as int? ?? 0,
      countRead: json['countRead'] as int? ?? 0,
    );
  }
  
  factory MessageModel.fromChaoxingJson(Map<String, dynamic> json) {
    final insertTime = json['insertTime'] as int? ?? 0;
    final dateTime = insertTime > 0 
        ? DateTime.fromMillisecondsSinceEpoch(insertTime)
        : DateTime.now();
    final sendTimeStr = '${dateTime.year}-${_twoDigits(dateTime.month)}-${_twoDigits(dateTime.day)} ${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}';
    
    final isReadValue = json['isread'] as int? ?? 0;
    final countAll = _parseInt(json['count_all']);
    final countRead = _parseInt(json['count_read']);
    
    return MessageModel(
      idCode: json['idCode'] as String? ?? '',
      title: _extractTitle(json),
      content: json['content'] as String? ?? '',
      createrName: json['createrName'] as String? ?? '',
      sendTime: sendTimeStr,
      isRead: isReadValue == 1,
      hasRedDot: isReadValue == 0,
      countAll: countAll,
      countRead: countRead,
      uuid: json['uuid'] as String? ?? '',
    );
  }
  
  static String _extractTitle(Map<String, dynamic> json) {
    final attachment = json['attachment'] as String?;
    if (attachment != null && attachment.isNotEmpty) {
      try {
        final titleRegex = RegExp(r'"title"\s*:\s*"([^"]+)"');
        final match = titleRegex.firstMatch(attachment);
        if (match != null && match.group(1) != null) {
          return match.group(1)!;
        }
      } catch (e) {}
    }
    
    final content = json['content'] as String? ?? '';
    if (content.isNotEmpty) {
      final lines = content.split('\r\n');
      if (lines.isNotEmpty && lines[0].isNotEmpty) {
        final firstLine = lines[0];
        return firstLine.length > 50 ? '${firstLine.substring(0, 50)}...' : firstLine;
      }
    }
    
    return '无标题';
  }
  
  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
  
  static String _twoDigits(int n) => n.toString().padLeft(2, '0');
  
  Map<String, dynamic> toJson() => {
    'idCode': idCode,
    'title': title,
    'content': content,
    'createrName': createrName,
    'sendTime': sendTime,
    'isRead': isRead ? '1' : '0',
    'redDot': hasRedDot ? '0' : '1',
    'countAll': countAll,
    'countRead': countRead,
  };
}

class NoticeResult {
  final List<MessageModel> messages;
  final String? nextLastValue;
  final bool hasMore;

  NoticeResult({
    required this.messages,
    this.nextLastValue,
    this.hasMore = true,
  });
}