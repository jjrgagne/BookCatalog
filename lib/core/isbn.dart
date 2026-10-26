/// ISBN validation, conversion and extraction helpers.
///
/// Everything is normalised to ISBN-13 for storage and duplicate detection.
library;

/// Removes everything except digits and `X`, upper-casing `x`.
String normalizeIsbn(String input) =>
    input.toUpperCase().replaceAll(RegExp(r'[^0-9X]'), '');

/// Whether [input] (hyphens/spaces allowed) is a valid ISBN-10.
bool isValidIsbn10(String input) {
  final s = normalizeIsbn(input);
  if (!RegExp(r'^[0-9]{9}[0-9X]$').hasMatch(s)) return false;
  var sum = 0;
  for (var i = 0; i < 10; i++) {
    final c = s[i];
    final value = c == 'X' ? 10 : int.parse(c);
    sum += value * (10 - i);
  }
  return sum % 11 == 0;
}

/// Whether [input] (hyphens/spaces allowed) is a valid ISBN-13
/// (EAN-13 with the 978/979 "Bookland" prefix).
bool isValidIsbn13(String input) {
  final s = normalizeIsbn(input);
  if (!RegExp(r'^97[89][0-9]{10}$').hasMatch(s)) return false;
  return _ean13CheckDigit(s.substring(0, 12)) == int.parse(s[12]);
}

int _ean13CheckDigit(String first12) {
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(first12[i]) * (i.isEven ? 1 : 3);
  }
  return (10 - sum % 10) % 10;
}

/// Converts a valid ISBN-10 or ISBN-13 to ISBN-13. Returns null if invalid.
String? toIsbn13(String input) {
  final s = normalizeIsbn(input);
  if (isValidIsbn13(s)) return s;
  if (isValidIsbn10(s)) {
    final first12 = '978${s.substring(0, 9)}';
    return '$first12${_ean13CheckDigit(first12)}';
  }
  return null;
}

/// Converts a valid 978-prefixed ISBN-13 (or an ISBN-10) to ISBN-10.
/// Returns null for 979 ISBNs, which have no ISBN-10 equivalent.
String? toIsbn10(String input) {
  final s = normalizeIsbn(input);
  if (isValidIsbn10(s)) return s;
  if (!isValidIsbn13(s) || !s.startsWith('978')) return null;
  final first9 = s.substring(3, 12);
  var sum = 0;
  for (var i = 0; i < 9; i++) {
    sum += int.parse(first9[i]) * (10 - i);
  }
  final check = (11 - sum % 11) % 11;
  return '$first9${check == 10 ? 'X' : check}';
}

/// Parses user or scanner input into a normalised ISBN-13, or null.
String? parseIsbn(String input) => toIsbn13(input);

const _confusables = {
  'O': '0',
  'o': '0',
  'D': '0',
  'Q': '0',
  'I': '1',
  'l': '1',
  '|': '1',
  'S': '5',
  's': '5',
  'B': '8',
  'Z': '2',
};

/// Finds checksum-valid ISBNs in free text such as OCR output and returns
/// them as unique ISBN-13s in order of appearance.
///
/// Handles hyphens, spaces and common OCR letter/digit confusions
/// (O→0, I/l→1, S→5, B→8, Z→2).
List<String> extractIsbns(String text) {
  final found = <String>[];
  void add(String? isbn) {
    if (isbn != null && !found.contains(isbn)) found.add(isbn);
  }

  // Drop "ISBN"/"ISBN-13:" labels so their letters can't be misread as digits.
  final cleaned = text.replaceAll(
    RegExp(r'ISBN(?:[-\s]?1[03])?\s*:?', caseSensitive: false),
    ' ',
  );

  // Per line, find runs of digit-like groups separated by a single
  // hyphen or space, e.g. "978-0-306-40615-7" or "9780306406157 52499".
  final group = RegExp(r'[0-9OoDQIl|SsBZXx]+');
  final separator = RegExp(r'^[ \t\-‐‑‒–]$');
  for (final line in cleaned.split(RegExp(r'[\r\n]+'))) {
    final groups = group.allMatches(line).toList();
    var start = 0;
    while (start < groups.length) {
      // Extend the run while groups are separated by exactly one separator.
      var end = start;
      while (end + 1 < groups.length &&
          separator.hasMatch(
            line.substring(groups[end].end, groups[end + 1].start),
          )) {
        end++;
      }
      final run = [for (var i = start; i <= end; i++) groups[i].group(0)!];
      // Candidates are contiguous groups, so an ISBN printed next to other
      // numbers is found without inventing digit boundaries.
      for (var i = 0; i < run.length; i++) {
        var raw = '';
        for (var j = i; j < run.length; j++) {
          raw += run[j];
          if (raw.length > 13) break;
          if (raw.length == 10 || raw.length == 13) add(_candidate(raw));
        }
      }
      // A single unseparated block longer than 13 (e.g. ISBN + price).
      for (final block in run.where((g) => g.length > 13)) {
        add(_candidate(block.substring(0, 13)));
        add(_candidate(block.substring(0, 10)));
      }
      start = end + 1;
    }
  }
  return found;
}

/// Maps OCR confusions to digits and validates; null if not an ISBN.
String? _candidate(String raw) {
  // Mostly real digits, so ordinary words are never mistaken for ISBNs.
  final realDigits = RegExp(r'[0-9]').allMatches(raw).length;
  if (realDigits < raw.length * 0.6) return null;
  final digits = raw
      .split('')
      .map((c) => _confusables[c] ?? c)
      .join()
      .toUpperCase();
  if (digits.contains(RegExp(r'X.'))) return null;
  return toIsbn13(digits);
}

/// Whether a scanned EAN-13 barcode value is a book ISBN.
bool isBooklandEan(String value) => isValidIsbn13(value);

/// Formats an ISBN-13 for display as `978-0-306-40615-7`-style groups.
///
/// Exact hyphenation depends on registration-group tables; this uses a
/// simple readable split (prefix-rest-check) instead.
String displayIsbn(String isbn13) {
  if (isbn13.length != 13) return isbn13;
  return '${isbn13.substring(0, 3)}-${isbn13.substring(3, 12)}-${isbn13[12]}';
}
