// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library analyzer_cli.src.utils;

import 'dart:io';

/// Parses a package map cfg file into a String map.
Map<String, String> readPackageMap(File file) {
  var map = <String, String>{};
  file.readAsLinesSync().forEach((String line) {
    if (!line.startsWith('#')) {
      var entry = line.split('=');
      map[entry[0]] = entry[1];
    }
  });
  return map;
}
