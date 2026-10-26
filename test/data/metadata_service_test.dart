import 'dart:convert';

import 'package:bookcatalog/data/models/book.dart';
import 'package:bookcatalog/data/services/metadata_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const isbn = '9780306406157';

final openLibraryFull = {
  'ISBN:$isbn': {
    'title': 'Test Driven Development',
    'subtitle': 'By Example',
    'authors': [
      {'name': 'Kent Beck', 'url': 'https://openlibrary.org/authors/x'},
    ],
    'publishers': [
      {'name': 'Addison-Wesley'},
    ],
    'publish_date': 'November 2002',
    'identifiers': {
      'isbn_10': ['0306406152'],
    },
    'cover': {
      'small': 'https://covers.openlibrary.org/b/id/1-S.jpg',
      'medium': 'https://covers.openlibrary.org/b/id/1-M.jpg',
    },
  },
};

final openLibraryPartial = {
  'ISBN:$isbn': {
    'title': 'Test Driven Development',
    'authors': [
      {'name': 'Kent Beck'},
    ],
  },
};

final googleBooks = {
  'totalItems': 1,
  'items': [
    {
      'volumeInfo': {
        'title': 'Test-Driven Development',
        'authors': ['Kent Beck'],
        'publisher': 'Addison-Wesley Professional',
        'publishedDate': '2003-01-01',
        'industryIdentifiers': [
          {'type': 'ISBN_13', 'identifier': isbn},
          {'type': 'ISBN_10', 'identifier': '0306406152'},
        ],
        'imageLinks': {'thumbnail': 'http://books.google.com/x.jpg'},
      },
    },
  ],
};

MetadataService serviceWith(
  Object? openLibrary,
  Object? google, {
  bool fail = false,
}) {
  final client = MockClient((request) async {
    if (fail) throw http.ClientException('offline');
    final body = request.url.host == 'openlibrary.org' ? openLibrary : google;
    return http.Response(jsonEncode(body ?? {}), 200);
  });
  return MetadataService(client: client, coverCheck: (_) async => true);
}

void main() {
  test('uses Open Library when it has complete data', () async {
    final result = await serviceWith(openLibraryFull, googleBooks).lookup(isbn);
    expect(result, isNotNull);
    expect(result!.title, 'Test Driven Development');
    expect(result.subtitle, 'By Example');
    expect(result.authors, ['Kent Beck']);
    expect(result.publisher, 'Addison-Wesley');
    expect(result.publishedYear, 2002);
    expect(result.isbn10, '0306406152');
    expect(result.coverUrl, 'https://covers.openlibrary.org/b/id/1-M.jpg');
    expect(result.source, MetadataSource.openlibrary);
  });

  test('fills gaps from Google Books', () async {
    final result = await serviceWith(
      openLibraryPartial,
      googleBooks,
    ).lookup(isbn);
    expect(result!.title, 'Test Driven Development');
    expect(result.publisher, 'Addison-Wesley Professional');
    expect(result.publishedYear, 2003);
    expect(result.coverUrl, 'https://books.google.com/x.jpg');
    expect(result.source, MetadataSource.openlibrary);
  });

  test('falls back to Google Books when Open Library has nothing', () async {
    final result = await serviceWith({}, googleBooks).lookup(isbn);
    expect(result!.title, 'Test-Driven Development');
    expect(result.source, MetadataSource.google);
  });

  test('returns null when nobody knows the book', () async {
    expect(await serviceWith({}, {'totalItems': 0}).lookup(isbn), isNull);
  });

  group('backup sources', () {
    /// Routes requests by host/path to canned JSON; records what was asked.
    MetadataService routed(
      Map<String, Object> Function(Uri) respond,
      List<Uri> calls,
    ) {
      final client = MockClient((request) async {
        calls.add(request.url);
        return http.Response(jsonEncode(respond(request.url)), 200);
      });
      return MetadataService(client: client, coverCheck: (_) async => true);
    }

    test('Google Books is retried with the ISBN-10', () async {
      final calls = <Uri>[];
      final result = await routed((u) {
        if (u.host == 'www.googleapis.com' &&
            u.queryParameters['q'] == 'isbn:0306406152') {
          return googleBooks;
        }
        return {};
      }, calls).lookup(isbn);
      expect(result!.title, 'Test-Driven Development');
      expect(calls.where((u) => u.host == 'www.googleapis.com').length, 2);
    });

    test('Open Library search index is used next', () async {
      final result = await routed((u) {
        if (u.path == '/search.json') {
          return {
            'numFound': 1,
            'docs': [
              {
                'title': 'Old Book',
                'author_name': ['A. Writer'],
                'publisher': ['Small Press'],
                'first_publish_year': 1971,
                'cover_i': 42,
              },
            ],
          };
        }
        return {};
      }, []).lookup(isbn);
      expect(result!.title, 'Old Book');
      expect(result.authors, ['A. Writer']);
      expect(result.publishedYear, 1971);
      expect(result.coverUrl, 'https://covers.openlibrary.org/b/id/42-M.jpg');
    });

    test('Crossref is the last resort', () async {
      final result = await routed((u) {
        if (u.host == 'api.crossref.org') {
          return {
            'message': {
              'items': [
                {
                  'title': ['Handbook of Things'],
                  'author': [
                    {'given': 'Ada', 'family': 'Lovelace'},
                  ],
                  'publisher': 'Springer',
                  'published-print': {
                    'date-parts': [
                      [2015, 3],
                    ],
                  },
                },
              ],
            },
          };
        }
        return {};
      }, []).lookup(isbn);
      expect(result!.title, 'Handbook of Things');
      expect(result.authors, ['Ada Lovelace']);
      expect(result.publishedYear, 2015);
      expect(result.source, MetadataSource.crossref);
      // No cover from Crossref: falls back to Open Library's cover-by-ISBN.
      expect(result.coverUrl, contains('/b/isbn/$isbn-M.jpg'));
    });

    test('stops once details are complete', () async {
      final calls = <Uri>[];
      await routed(
        (u) => u.host == 'openlibrary.org' && u.path == '/api/books'
            ? openLibraryFull
            : {},
        calls,
      ).lookup(isbn);
      expect(calls.length, 1);
    });
  });

  group('covers are chosen separately from details', () {
    MetadataService withCovers(Set<String> working) {
      final client = MockClient((request) async {
        final body = request.url.host == 'openlibrary.org'
            ? (request.url.path == '/api/books' ? openLibraryFull : {})
            : googleBooks;
        return http.Response(jsonEncode(body), 200);
      });
      return MetadataService(
        client: client,
        coverCheck: (url) async => working.contains(url),
      );
    }

    test('details from Open Library, cover from Google Books', () async {
      // Open Library's cover link is broken; Google's works.
      final result = await withCovers({'https://books.google.com/x.jpg'})
          .lookup(isbn);
      expect(result!.title, 'Test Driven Development');
      expect(result.publisher, 'Addison-Wesley');
      expect(result.source, MetadataSource.openlibrary);
      expect(result.coverUrl, 'https://books.google.com/x.jpg');
    });

    test('falls back to Open Library cover-by-ISBN', () async {
      final byIsbn =
          'https://covers.openlibrary.org/b/isbn/$isbn-M.jpg?default=false';
      final result = await withCovers({byIsbn}).lookup(isbn);
      expect(result!.coverUrl, byIsbn);
    });

    test('no working cover anywhere gives no cover', () async {
      final result = await withCovers({}).lookup(isbn);
      expect(result!.title, 'Test Driven Development');
      expect(result.coverUrl, isNull);
    });
  });

  test('throws LookupUnavailableException when offline', () async {
    expect(
      serviceWith(null, null, fail: true).lookup(isbn),
      throwsA(isA<LookupUnavailableException>()),
    );
  });
}
