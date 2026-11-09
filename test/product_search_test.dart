import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_manager/utils/product_search.dart';

typedef P = (String name, String size);

List<String> search(List<P> items, String query) => [
      for (final p in rankBySearch<P>(items, query,
          name: (p) => p.$1, size: (p) => p.$2))
        '${p.$1} | ${p.$2}',
    ];

void main() {
  const caps = <P>[
    ('ppr end cap', '3/4 Inch'),
    ('END CAP', '4 Inch'),
    ('End Cap', '1/4 Inch'),
    ('End Cap', '40 MM'),
    ('End Cap', '4"'),
    ('Reducer Socket', '4 × 3 Inch'),
    ('Reducer Socket', '3 × 2.5 Inch'),
    ('GI Nipple Desi 4"', 'NA'),
    ('End Cap', '1.5 Inch'),
  ];

  test('a size number matches whole sizes only, not 3/4 or 40', () {
    expect(search(caps, 'end cap 4'), ['END CAP | 4 Inch', 'End Cap | 4"']);
  });

  test('fractions are typed exactly', () {
    expect(search(caps, 'end cap 3/4'), ['ppr end cap | 3/4 Inch']);
  });

  test('decimal, mixed and hyphenated sizes are the same value', () {
    for (final q in ['cap 1.5', 'cap 1 1/2', 'cap 1-1/2', 'cap 3/2']) {
      expect(search(caps, q), ['End Cap | 1.5 Inch'], reason: q);
    }
  });

  test('units are read loosely and never rule a product out', () {
    expect(search(caps, 'cap 4"'), ['END CAP | 4 Inch', 'End Cap | 4"']);
    expect(search(caps, 'cap 4 inch'), ['END CAP | 4 Inch', 'End Cap | 4"']);
    expect(search(caps, 'cap 40mm'), ['End Cap | 40 MM']);
  });

  test('exact reducer size ranks before one that only shares a number', () {
    expect(search(caps, 'reducer 4 3'), ['Reducer Socket | 4 × 3 Inch']);
    expect(search(caps, 'reducer 3'),
        ['Reducer Socket | 3 × 2.5 Inch', 'Reducer Socket | 4 × 3 Inch']);
  });

  test('numbers in the name count when the size is blank', () {
    expect(search(caps, 'nipple 4'), ['GI Nipple Desi 4" | NA']);
  });

  test('words match part-typed, joined up, or with a typo', () {
    const items = <P>[
      ('Finolex Cpvc Reducer Elbow', '1 × 3/4 Inch'),
      ('Wall Mixer', 'NA'),
      ('Endcap Plug', '2 Inch'),
    ];
    expect(search(items, 'fin elb'), ['Finolex Cpvc Reducer Elbow | 1 × 3/4 Inch']);
    expect(search(items, 'reduser'), ['Finolex Cpvc Reducer Elbow | 1 × 3/4 Inch']);
    expect(search(items, 'end cap'), ['Endcap Plug | 2 Inch']);
    expect(search(items, 'mixr'), ['Wall Mixer | NA']);
  });

  test('codes with letters then digits stay whole', () {
    const items = <P>[('Suraksha Plus Base SL1', 'NA'), ('Suraksha Plus Base SL2', 'NA')];
    expect(search(items, 'sl1'), ['Suraksha Plus Base SL1 | NA']);
  });

  test('empty query keeps everything in order', () {
    expect(search(caps, '  ').length, caps.length);
  });

  test('a reducer typed "1 3/4" finds size 1 × 3/4', () {
    const items = <P>[
      ('Reducer Elbow', '1 × 3/4 Inch'),
      ('Reducer Elbow', '1 × 1/2 Inch'),
      ('Bend', '1 3/4 Inch'),
    ];
    expect(search(items, 'reducer 1 3/4'), ['Reducer Elbow | 1 × 3/4 Inch']);
    expect(search(items, 'bend 1 3/4'), ['Bend | 1 3/4 Inch']);
  });

  test('short words only match the start of a word', () {
    const items = <P>[('Unik Tee', '1/2 Inch'), ('Gate Ball Steel', '1/2')];
    expect(search(items, 'tee 1/2'), ['Unik Tee | 1/2 Inch']);
  });
}
