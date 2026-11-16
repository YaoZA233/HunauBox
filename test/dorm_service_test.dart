import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/services/dorm_service.dart';

void main() {
  group('DormService.parseDormInfo', () {
    test('ignores page status text and reads adjacent dorm values', () {
      const html = '''
        <html>
          <head><title>学生公寓服务平台</title></head>
          <body>
            <h1>学生公寓服务平台</h1>
            <p>床号获取到后将在下方显示</p>
            <div class="row"><span>宿舍楼</span><strong>丰泽四北</strong></div>
            <div class="row"><span>楼层</span><strong>4</strong></div>
            <div class="row"><span>房间</span><strong>401</strong></div>
            <div class="row"><span>床号</span><strong>2号床</strong></div>
          </body>
        </html>
      ''';

      final info = DormService().parseDormInfo(html);

      expect(info.dormBuilding, '丰泽四北');
      expect(info.floor, '4');
      expect(info.room, '401');
      expect(info.bed, '2');
    });

    test('does not accept page shell copy as dorm information', () {
      const html = '''
        <html><body>
          <h1>学生公寓服务平台</h1>
          <p>床号获取到后将在下方显示</p>
        </body></html>
      ''';

      final info = DormService().parseDormInfo(html);

      expect(info.hasAny, isFalse);
    });

    test('reads explicit label and value table rows', () {
      const html = '''
        <table>
          <tr><th>宿舍楼</th><th>楼层</th><th>房间</th><th>床号</th></tr>
          <tr><td>丰泽四北</td><td>4</td><td>401</td><td>2</td></tr>
        </table>
      ''';

      final info = DormService().parseDormInfo(html);

      expect(info.dormBuilding, '丰泽四北');
      expect(info.bed, '2');
    });

    test('reads fields from compact rendered text without separators', () {
      const html = '''
        <html><body>
          <div>学生公寓服务平台</div>
          <div>床号获取到后将在下方显示</div>
          <div>宿舍楼丰泽四北楼层4房间401床号2号床</div>
        </body></html>
      ''';

      final info = DormService().parseDormInfo(html);

      expect(info.dormBuilding, '丰泽四北');
      expect(info.floor, '4');
      expect(info.room, '401');
      expect(info.bed, '2');
    });

    test('reads and merges fields from an API JSON response', () {
      const payload = '''
        {
          "data": {
            "dormName": "丰泽四北",
            "floorName": "4层",
            "roomNo": "401",
            "bedNo": "2号床"
          }
        }
      ''';

      final info = DormService().parseDormPayload(payload);

      expect(info.dormBuilding, '丰泽四北');
      expect(info.floor, '4层');
      expect(info.room, '401');
      expect(info.bed, '2');
    });

    test('keeps legacy fields while skipping misleading platform copy', () {
      const html = '''
        <html><body>
          学生公寓 服务平台
          公寓 丰泽四北
          楼层 4
          房间 401
          床号 获取到 2号床
        </body></html>
      ''';

      final info = DormService().parseDormInfo(html);

      expect(info.dormBuilding, '丰泽四北');
      expect(info.floor, '4');
      expect(info.room, '401');
      expect(info.bed, '2');
    });

    test('reads the actual createRow structure used by the dorm page', () {
      const html = '''
        <html><body>
          <script>
            function loadData() {
              // view.createRow("ssl", "宿舍楼", "未安排床位");
              view.createRow("ssl", "宿舍楼", "丰泽4北");
              view.createRow("lc", "楼层", "4");
              view.createRow("fj", "寝室房间号", "401");
              view.createRow("cw", "床位", "2");
            }
          </script>
          <div>床号将在20秒内获取到</div>
        </body></html>
      ''';

      final info = DormService().parseDormInfo(html);

      expect(info.dormBuilding, '丰泽四北');
      expect(info.floor, '4');
      expect(info.room, '401');
      expect(info.bed, '2');
    });
  });
}
