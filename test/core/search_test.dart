import 'package:bookcatalog/core/search.dart';
import 'package:bookcatalog/data/models/book.dart';
import 'package:flutter_test/flutter_test.dart';

final book = Book(
  id: '1',
  title: "L'Étranger",
  authors: const ['Albert Camus'],
  isbn13: '9780306406157',
  isbn10: '0306406152',
  notes: 'Signed copy from Paris',
  addedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  test('accent- and case-insensitive title/author search', () {
    expect(bookMatches(book, 'etranger'), isTrue);
    expect(bookMatches(book, 'CAMUS'), isTrue);
    expect(bookMatches(book, 'camus etranger'), isTrue);
    expect(bookMatches(book, 'sartre'), isFalse);
  });

  test('searches notes', () {
    expect(bookMatches(book, 'signed'), isTrue);
  });

  test('ISBN search in either form, with hyphens', () {
    expect(bookMatches(book, '978-0-306-40615-7'), isTrue);
    expect(bookMatches(book, '0306406152'), isTrue);
    expect(bookMatches(book, '9780804429573'), isFalse);
    expect(bookMatches(book, '40615'), isTrue);
  });

  test('empty query matches everything', () {
    expect(bookMatches(book, '  '), isTrue);
  });
}
