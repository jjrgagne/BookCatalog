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
  return MetadataService(client: client);
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

  test('throws LookupUnavailableException when offline', () async {
    expect(
      serviceWith(null, null, fail: true).lookup(isbn),
      throwsA(isA<LookupUnavailableException>()),
    );
  });
}
