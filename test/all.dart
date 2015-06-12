// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:unittest/unittest.dart';

import 'driver_test.dart' as driver;
import 'error_test.dart' as error;
import 'options_test.dart' as options;
import 'reporter_test.dart' as reporter;

main() {
  // Tidy up output.
  filterStacks = true;
  formatStacks = true;

  driver.main();
  error.main();
  options.main();
  reporter.main();
}
