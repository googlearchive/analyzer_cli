// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library analyzer_cli.test.utils;

import 'dart:io';

import 'package:analyzer_cli/src/utils.dart';
import 'package:unittest/unittest.dart';

main() {
  groupSep = ' | ';

  defineTests();
}

defineTests() {
  group('utils', () {
    group('packagemap.cfg', () {
      test('parsing', () {
        var map = readPackageMap(new File('test/data/test.cfg'));
        expect(map, containsPair(
            'unittest', '/home/somebody/.pub/cache/unittest-0.9.9/lib/'));
        expect(map, containsPair(
            'async', '/home/somebody/.pub/cache/async-1.1.0/lib/'));
        expect(map, containsPair(
            'quiver', '/home/somebody/.pub/cache/quiver-1.2.1/lib/'));
      });
    });
  });
}
