import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../models/chaoxing_course.dart';

class ChaoxingCourseException implements Exception {
  const ChaoxingCourseException(this.message, {this.needsLogin = false});
  final String message;
  final bool needsLogin;
  @override
  String toString() => message;
}

/// The personal-space URL is a shell. Its course iframe loads HTML through
/// courselistdata; folders use the same endpoint with a courseFolderId.
class ChaoxingCourseService {
  ChaoxingCourseService(this.dio);
  final Dio dio;
  static const portalUrl = 'https://i.chaoxing.com/base';
  static const origin = 'https://mooc2-ans.chaoxing.com';
  static const interactionUrl = '$origin/mooc2-ans/visit/interaction';
  static const desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  Options get _options => Options(
    responseType: ResponseType.plain,
    headers: {'User-Agent': desktopUserAgent, 'Referer': interactionUrl},
    sendTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 25),
  );

  static bool isChaoxingUrl(Uri uri) =>
      uri.scheme == 'https' &&
      (uri.host == 'chaoxing.com' || uri.host.endsWith('.chaoxing.com'));

  Document _document(Response response) {
    final document = html.parse(response.data?.toString() ?? '');
    if (response.realUri.host.startsWith('passport') ||
        document.querySelector('input[type="password"]') != null ||
        document.querySelector('#phoneLogin, #loginForm') != null) {
      throw const ChaoxingCourseException('学习通登录已失效，请登录后重试', needsLogin: true);
    }
    return document;
  }

  Future<List<ChaoxingCourse>> fetchCourses() async {
    try {
      final interaction = _document(
        await dio.get(interactionUrl, options: _options),
      );
      if (interaction.querySelector('#courseType, #myLearn') == null) {
        throw const ChaoxingCourseException(
          '未能读取学习通课程页，请打开学习通确认登录状态',
          needsLogin: true,
        );
      }
      String value(String id) =>
          interaction.querySelector('#$id')?.attributes['value'] ?? '';
      final parameters = <String, dynamic>{
        'courseType': '1',
        'query': '',
        'pageHeader': value('stuPageHeader'),
        'single': value('single'),
        'superstarClass': value('superstarClass'),
        'isFirefly': value('isFirefly') == '1' ? '1' : '0',
        'courseLevelLabelId': '0',
        'fid': value('filterFid'),
        'from': value('from'),
      };
      final folders = <String, String>{'0': '', ...parseFolders(interaction)};
      final visited = <String>{};
      final courses = <String, ChaoxingCourse>{};
      while (folders.keys.any((id) => !visited.contains(id))) {
        if (visited.length >= 100) {
          throw const ChaoxingCourseException('课程文件夹过多，请在学习通网页查看完整列表');
        }
        final id = folders.keys.firstWhere((id) => !visited.contains(id));
        visited.add(id);
        final response = await dio.post(
          '$origin/mooc2-ans/visit/courselistdata',
          data: {...parameters, 'courseFolderId': id},
          options: _options.copyWith(
            contentType: Headers.formUrlEncodedContentType,
          ),
        );
        final document = _document(response);
        final parsed = parseCourses(document, folder: folders[id]!);
        if (parsed.isEmpty &&
            document.querySelector(
                  '#courseList, #stuNormalCourseListDiv, #stuTopCourseListDiv, .null-data',
                ) ==
                null) {
          throw const ChaoxingCourseException('学习通课程列表格式已变化，请在网页查看或稍后重试');
        }
        for (final course in parsed) {
          courses[course.id] = course;
        }
        folders.addAll(parseFolders(document));
      }
      final result = courses.values.toList();
      // Progress is supplementary: unavailable progress must not hide courses.
      for (var offset = 0; offset < result.length; offset += 20) {
        final batch = result
            .skip(offset)
            .take(20)
            .where((c) => c.personInfo.isNotEmpty)
            .toList();
        if (batch.isEmpty) continue;
        try {
          final response = await dio.get(
            '$origin/mooc2-ans/mycourse/stu-job-info',
            queryParameters: {
              'clazzPersonStr': batch.map((c) => c.personInfo).join(','),
            },
            options: _options,
          );
          final data = response.data is String
              ? jsonDecode(response.data)
              : response.data;
          if (data is! Map ||
              data['status'] != true ||
              data['jobArray'] is! List) {
            continue;
          }
          for (final job in data['jobArray'] as List) {
            if (job is! Map) continue;
            final finished = int.tryParse('${job['jobFinishCount']}');
            final total = int.tryParse('${job['jobCount']}');
            if (finished == null ||
                total == null ||
                finished < 0 ||
                total < 0) {
              continue;
            }
            for (var i = offset; i < result.length && i < offset + 20; i++) {
              if (Uri.parse(result[i].url).queryParameters['clazzid'] ==
                  '${job['clazzId']}') {
                result[i] = result[i].withJobs(finished, total);
              }
            }
          }
        } catch (_) {
          // Keep progress unknown rather than reporting zero completion.
        }
      }
      return result;
    } on DioException {
      throw const ChaoxingCourseException('暂时无法连接学习通，请检查网络后重试');
    }
  }

  static Map<String, String> parseFolders(Document document) => {
    for (final folder in document.querySelectorAll('#fileList li[fileid]'))
      if (RegExp(r'^\d+$').hasMatch(folder.attributes['fileid'] ?? ''))
        folder.attributes['fileid']!:
            folder.querySelector('.file-name')?.text.trim() ?? '文件夹',
  };

  static List<ChaoxingCourse> parseCourses(
    Document document, {
    String folder = '',
  }) {
    final result = <ChaoxingCourse>[];
    for (final card in document.querySelectorAll('.learnCourse')) {
      final link = card.querySelector('.course-info h3 a');
      final rawUrl = link?.attributes['href'] ?? '';
      if (rawUrl.isEmpty) continue;
      final uri = Uri.parse(interactionUrl).resolve(rawUrl);
      final nameNode = card.querySelector('.course-name');
      final name =
          (nameNode?.attributes['title'] ?? nameNode?.text ?? link?.text ?? '')
              .trim();
      final courseId = uri.queryParameters['courseid'];
      final classId = uri.queryParameters['clazzid'];
      if (!isChaoxingUrl(uri) ||
          name.isEmpty ||
          courseId == null ||
          classId == null) {
        continue;
      }
      final cover =
          card.querySelector('.course-cover img')?.attributes['src'] ?? '';
      final image = cover.isEmpty
          ? null
          : Uri.tryParse(interactionUrl)?.resolve(cover);
      final progress = RegExp(
        r'(\d+)\s*/\s*(\d+)',
      ).firstMatch(card.querySelector('.l-txt')?.text ?? '');
      result.add(
        ChaoxingCourse(
          id: '$courseId:$classId',
          name: name,
          url: uri.toString(),
          teacher:
              card.querySelector('.course-info p.color3')?.text.trim() ?? '',
          school:
              card.querySelector('.course-info p.color2')?.text.trim() ?? '',
          schedule: card
              .querySelectorAll('.course-info p')
              .map((p) => p.text.trim())
              .where((text) => text.startsWith('开课时间'))
              .join(' '),
          coverUrl:
              image != null &&
                  (image.scheme == 'https' || image.scheme == 'http')
              ? image.replace(scheme: 'https').toString()
              : '',
          folder: folder,
          personInfo: card.attributes['info'] ?? '',
          finishedJobs: progress == null
              ? null
              : int.tryParse(progress.group(1)!),
          totalJobs: progress == null ? null : int.tryParse(progress.group(2)!),
        ),
      );
    }
    return result;
  }
}
