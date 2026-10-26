import '../data/models/book.dart';
import 'isbn.dart';

const _diacritics = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'æ': 'ae',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ß': 'ss',
  'œ': 'oe',
};

/// Lower-cases and strips accents so "Émile" matches "emile".
String foldForSearch(String s) {
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final c = String.fromCharCode(rune);
    out.write(_diacritics[c] ?? c);
  }
  return out.toString();
}

/// Whether [book] matches a free-text [query] on title, subtitle, authors,
/// publisher, notes or ISBN (ISBN-10 or -13, with or without hyphens).
bool bookMatches(Book book, String query) {
  final q = query.trim();
  if (q.isEmpty) return true;

  final digits = normalizeIsbn(q);
  if (digits.length >= 4 &&
      digits.length == q.replaceAll(RegExp(r'[\s-]'), '').length) {
    final asIsbn13 = toIsbn13(digits);
    if (asIsbn13 != null) return book.isbn13 == asIsbn13;
    if ((book.isbn13?.contains(digits) ?? false) ||
        (book.isbn10?.contains(digits) ?? false)) {
      return true;
    }
  }

  final haystack = foldForSearch(
    [
      book.title,
      book.subtitle ?? '',
      ...book.authors,
      book.publisher ?? '',
      book.notes,
    ].join(' '),
  );
  return foldForSearch(q).split(RegExp(r'\s+')).every(haystack.contains);
}
