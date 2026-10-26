import 'package:bookcatalog/core/isbn.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeIsbn', () {
    test('strips separators and upper-cases X', () {
      expect(normalizeIsbn('0-8044-2957-x'), '080442957X');
      expect(normalizeIsbn(' 978 0 306 40615 7 '), '9780306406157');
    });
  });

  group('ISBN-10', () {
    test('valid', () {
      expect(isValidIsbn10('0-306-40615-2'), isTrue);
      expect(isValidIsbn10('080442957X'), isTrue);
      expect(isValidIsbn10('0-8044-2957-x'), isTrue);
    });
    test('invalid', () {
      expect(isValidIsbn10('0-306-40615-3'), isFalse);
      expect(isValidIsbn10('X306406152'), isFalse);
      expect(isValidIsbn10('030640615'), isFalse);
      expect(isValidIsbn10(''), isFalse);
    });
  });

  group('ISBN-13', () {
    test('valid', () {
      expect(isValidIsbn13('978-0-306-40615-7'), isTrue);
      expect(isValidIsbn13('9791090636071'), isTrue);
    });
    test('invalid checksum or prefix', () {
      expect(isValidIsbn13('9780306406158'), isFalse);
      // Valid EAN-13 but not a book (no 978/979 prefix).
      expect(isValidIsbn13('4006381333931'), isFalse);
      expect(isValidIsbn13('978030640615'), isFalse);
    });
  });

  group('conversion', () {
    test('10 -> 13', () {
      expect(toIsbn13('0-306-40615-2'), '9780306406157');
      expect(toIsbn13('080442957X'), '9780804429573');
    });
    test('13 stays 13', () {
      expect(toIsbn13('978-0-306-40615-7'), '9780306406157');
    });
    test('13 -> 10', () {
      expect(toIsbn10('9780306406157'), '0306406152');
      expect(toIsbn10('9780804429573'), '080442957X');
    });
    test('979 has no ISBN-10', () {
      expect(toIsbn10('9791090636071'), isNull);
    });
    test('invalid returns null', () {
      expect(toIsbn13('1234567890'), isNull);
      expect(toIsbn10('nonsense'), isNull);
    });
    test('round trip', () {
      for (final isbn10 in ['0306406152', '080442957X', '0140449132']) {
        expect(toIsbn10(toIsbn13(isbn10)!), isbn10);
      }
    });
  });

  group('extractIsbns', () {
    test('labelled ISBN-13 with hyphens', () {
      expect(extractIsbns('Printed in USA\nISBN 978-0-306-40615-7\n10 9 8 7'), [
        '9780306406157',
      ]);
    });
    test('ISBN-10 is converted to 13', () {
      expect(extractIsbns('ISBN: 0-306-40615-2'), ['9780306406157']);
    });
    test('ISBN-13: label with spaces', () {
      expect(extractIsbns('ISBN-13: 978 0 306 40615 7'), ['9780306406157']);
    });
    test('both forms on one page give one result', () {
      expect(extractIsbns('ISBN-10: 0306406152\nISBN-13: 9780306406157'), [
        '9780306406157',
      ]);
    });
    test('OCR confusions are corrected', () {
      expect(extractIsbns('ISBN 978-O-3O6-4O6l5-7'), ['9780306406157']);
    });
    test('trailing X', () {
      expect(extractIsbns('ISBN 0-8044-2957-X'), ['9780804429573']);
    });
    test('ignores numbers with bad checksums', () {
      expect(extractIsbns('Tel 555-123-4567, order 9780306406158'), isEmpty);
    });
    test('ignores ordinary words', () {
      expect(extractIsbns('ISBN Booklist Sales Solid Oil'), isEmpty);
    });
    test('ISBN next to price in one run', () {
      expect(extractIsbns('9780306406157 52499'), ['9780306406157']);
    });
  });

  test('displayIsbn', () {
    expect(displayIsbn('9780306406157'), '978-030640615-7');
  });
}
