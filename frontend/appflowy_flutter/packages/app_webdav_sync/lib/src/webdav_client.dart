import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// 远端条目（PROPFIND 结果）。
class WebDavEntry {
  const WebDavEntry({
    required this.path,
    required this.isDirectory,
    required this.sizeInBytes,
    this.lastModified,
  });

  final String path;
  final bool isDirectory;
  final int sizeInBytes;
  final DateTime? lastModified;
}

/// 极简 WebDAV 客户端：只用标准方法（MKCOL / PUT / GET / HEAD / PROPFIND / DELETE）。
///
/// 之所以自己写而不是引第三方包：需求只有"放快照、取快照、列目录"，
/// 用标准 HTTP 方法即可，避免再引一个同步库（也便于后面替换成任意兼容 WebDAV 的网盘）。
class WebDavClient {
  WebDavClient({
    required String baseUrl,
    required String username,
    required String password,
    http.Client? client,
  })  : _baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
        _username = username,
        _password = password,
        _client = client ?? http.Client();

  final String _baseUrl;
  final String _username;
  final String _password;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 30);

  Uri uriOf(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$normalized');
  }

  Map<String, String> get _headers => {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$_username:$_password'))}',
      };

  /// 连接自检：对根目录做一次 PROPFIND，能拿到 207/200 就算通。
  Future<void> testConnection() async {
    final response = await _propfind('/');
    if (response.statusCode >= 400) {
      throw Exception('连接失败：HTTP ${response.statusCode}');
    }
  }

  /// 确保目录存在（逐级 MKCOL，已存在时服务端一般返回 405，视为成功）。
  Future<void> ensureDirectory(String path) async {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    var current = '';
    for (final segment in segments) {
      current = '$current/$segment';
      final response = await _client
          .send(
            http.Request('MKCOL', uriOf(current))
              ..headers.addAll(_headers),
          )
          .then(http.Response.fromStream)
          .timeout(_timeout);
      // 201 创建成功 / 405 已存在 / 301·302 已存在（部分网盘如此返回）
      if (response.statusCode >= 400 &&
          response.statusCode != 405 &&
          response.statusCode != 301 &&
          response.statusCode != 302) {
        throw Exception('创建目录失败 $current：HTTP ${response.statusCode}');
      }
    }
  }

  Future<void> putBytes(String path, List<int> bytes) async {
    final response = await _client
        .put(uriOf(path), headers: _headers, body: bytes)
        .timeout(_timeout);
    if (response.statusCode >= 400) {
      throw Exception('上传失败 $path：HTTP ${response.statusCode}');
    }
  }

  Future<void> putText(String path, String text) =>
      putBytes(path, utf8.encode(text));

  /// 下载（返回原始字节）。404 时抛 [RemoteFileNotFound]。
  Future<List<int>> getBytes(String path) async {
    final response =
        await _client.get(uriOf(path), headers: _headers).timeout(_timeout);
    if (response.statusCode == 404) {
      throw const RemoteFileNotFound();
    }
    if (response.statusCode >= 400) {
      throw Exception('下载失败 $path：HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  /// 读取文本（不存在时返回 null）。
  Future<String?> getTextOrNull(String path) async {
    try {
      final bytes = await getBytes(path);
      return utf8.decode(bytes);
    } on RemoteFileNotFound {
      return null;
    }
  }

  Future<bool> exists(String path) async {
    final response = await _client
        .head(uriOf(path), headers: _headers)
        .timeout(_timeout);
    return response.statusCode < 400;
  }

  Future<void> delete(String path) async {
    await _client
        .delete(uriOf(path), headers: _headers)
        .timeout(_timeout);
  }

  /// 列目录（Depth: 1）。
  Future<List<WebDavEntry>> list(String path) async {
    final response = await _propfind(path, depth: '1');
    if (response.statusCode >= 400) {
      throw Exception('列目录失败 $path：HTTP ${response.statusCode}');
    }
    return _parsePropfind(response.body);
  }

  Future<http.Response> _propfind(String path, {String depth = '0'}) {
    return _client
        .send(
          http.Request('PROPFIND', uriOf(path))
            ..headers.addAll({
              ..._headers,
              'Depth': depth,
              'Content-Type': 'application/xml',
            })
            ..body = '<?xml version="1.0" encoding="utf-8" ?>'
                '<d:propfind xmlns:d="DAV:"><d:prop>'
                '<d:resourcetype/><d:getcontentlength/><d:getlastmodified/>'
                '</d:prop></d:propfind>',
        )
        .then(http.Response.fromStream)
        .timeout(_timeout);
  }

  List<WebDavEntry> _parsePropfind(String xmlBody) {
    final document = XmlDocument.parse(xmlBody);
    final entries = <WebDavEntry>[];
    for (final response in document.findAllElements('response', namespace: '*')) {
      final href = response
          .findAllElements('href', namespace: '*')
          .firstOrNull
          ?.innerText
          .trim();
      if (href == null || href.isEmpty) {
        continue;
      }
      final resourceType = response.findAllElements('resourcetype', namespace: '*');
      final isDirectory = resourceType.any(
        (element) => element.findElements('collection', namespace: '*').isNotEmpty,
      );
      final size = int.tryParse(
            response
                    .findAllElements('getcontentlength', namespace: '*')
                    .firstOrNull
                    ?.innerText ??
                '',
          ) ??
          0;
      final modified = DateTime.tryParse(
        response
                .findAllElements('getlastmodified', namespace: '*')
                .firstOrNull
                ?.innerText ??
            '',
      );
      entries.add(
        WebDavEntry(
          path: Uri.decodeFull(href),
          isDirectory: isDirectory,
          sizeInBytes: size,
          lastModified: modified,
        ),
      );
    }
    return entries;
  }

  void close() => _client.close();
}

/// 远端文件不存在。
class RemoteFileNotFound implements Exception {
  const RemoteFileNotFound();

  @override
  String toString() => '远端文件不存在';
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
