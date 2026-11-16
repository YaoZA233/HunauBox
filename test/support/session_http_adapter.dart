import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class SessionHttpAdapter implements HttpClientAdapter {
  SessionHttpAdapter(this.handle);
  final FutureOr<ResponseBody> Function(RequestOptions) handle;
  final requests = <RequestOptions>[];
  final bodies = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final part in requestStream) {
        bytes.addAll(part);
      }
    }
    bodies.add(utf8.decode(bytes, allowMalformed: true));
    return handle(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody sessionResponse(
  String body, {
  int status = 200,
  String? location,
  List<String>? cookies,
}) => ResponseBody.fromString(
  body,
  status,
  headers: {
    if (location != null) 'location': [location],
    'set-cookie': ?cookies,
  },
);
