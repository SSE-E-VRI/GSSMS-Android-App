import 'package:dio/dio.dart';

/// Everything a bounded list fetch returns: the rows, plus whether the fetch
/// stopped early because it hit [fetchAllPages]'s page cap.
class PagedFetchResult {
  const PagedFetchResult({required this.items, required this.truncated});

  final List<dynamic> items;

  /// True when the server still had pages left at the cap. A caller that shows
  /// these rows to a user must say so — silently presenting a partial register
  /// as the whole one is worse than being slow.
  final bool truncated;
}

/// Default page cap. Only `AssetViewSet` paginates today
/// (StandardResultsSetPagination, `page_size` up to 100), so at
/// [preferredPageSize] this is 2,000 rows before truncation — comfortably past
/// any one depot's register, while still bounding a global-scoped fetch that
/// would otherwise walk the entire railway into a phone's memory.
const int defaultMaxPages = 20;

/// Page size to request. DRF ignores it on unpaginated viewsets, and
/// `StandardResultsSetPagination.max_page_size` caps it at 100 — asking for it
/// cuts a full-register walk from ~5 requests per 100 rows to one.
const int preferredPageSize = 100;

/// Walks a DRF list endpoint's `next` links and returns the accumulated rows.
///
/// Handles both shapes the backend serves: a paginated
/// `{count, next, results}` envelope and a bare list from a viewset with
/// `pagination_class = None`.
///
/// The walk is bounded three ways, because an unbounded one on a mobile client
/// is a hang or an OOM rather than a slow screen: [maxPages] caps the number of
/// requests, and a `next` link that repeats or fails to advance terminates the
/// loop instead of spinning on it.
Future<PagedFetchResult> fetchAllPages(
  Dio dio,
  String path, {
  Map<String, dynamic>? queryParameters,
  int maxPages = defaultMaxPages,
}) async {
  final items = <dynamic>[];
  final seenPaths = <String>{};

  String? currentPath = path;
  Map<String, dynamic>? currentQuery = {
    ...?queryParameters,
    'page_size': preferredPageSize,
  };

  var pages = 0;
  while (currentPath != null) {
    if (pages >= maxPages) {
      return PagedFetchResult(items: items, truncated: true);
    }
    pages++;

    final response = await dio.get<dynamic>(currentPath, queryParameters: currentQuery);
    currentQuery = null;

    final data = response.data;
    if (data is Map<String, dynamic>) {
      if (data['results'] is List) {
        items.addAll(data['results'] as List<dynamic>);
      }
      final nextUrl = data['next'] as String?;
      if (nextUrl == null || nextUrl.isEmpty) break;

      final uri = Uri.parse(nextUrl);
      final nextPath = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
      // A `next` that points back at a page already fetched would loop
      // forever. Treat it as the end of the list, not as more data.
      if (!seenPaths.add(nextPath)) break;
      currentPath = nextPath;
    } else if (data is List<dynamic>) {
      items.addAll(data);
      break;
    } else {
      break;
    }
  }

  return PagedFetchResult(items: items, truncated: false);
}
