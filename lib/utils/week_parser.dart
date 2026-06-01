class WeekParser {
  static List<int> parseWeeks(String weekString) {
    if (weekString.isEmpty) return [];

    String cleaned = weekString.replaceAll('(周)', '').replaceAll(' ', '').trim();
    if (cleaned.isEmpty) return [];

    List<int> weeks = [];
    final parts = cleaned.split(',');

    for (String part in parts) {
      part = part.trim();
      if (part.isEmpty) continue;

      if (part.contains('-')) {
        final range = part.split('-');
        if (range.length == 2) {
          try {
            int start = int.parse(range[0]);
            int end = int.parse(range[1]);

            if (start > end) {
              final temp = start;
              start = end;
              end = temp;
            }

            for (int i = start; i <= end; i++) {
              weeks.add(i);
            }
          } catch (e) {
            continue;
          }
        }
      } else {
        try {
          weeks.add(int.parse(part));
        } catch (e) {
          continue;
        }
      }
    }

    weeks = weeks.toSet().toList()..sort();
    return weeks;
  }

  static String formatWeeks(List<int> weeks) {
    if (weeks.isEmpty) return '';

    if (weeks.length == 1) {
      return '第${weeks[0]}周';
    }

    List<String> parts = [];
    int i = 0;

    while (i < weeks.length) {
      int start = weeks[i];
      int end = start;

      while (i + 1 < weeks.length && weeks[i + 1] == end + 1) {
        i++;
        end = weeks[i];
      }

      if (start == end) {
        parts.add('$start');
      } else {
        parts.add('$start-$end');
      }

      i++;
    }

    return '第${parts.join(',')}周';
  }
}
