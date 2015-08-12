#!/bin/bash

# Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

# Fast fail the script on failures.
set -e

# Verify that the libraries are error free.
dartanalyzer --fatal-warnings \
  bin/analyzer.dart \
  lib/src/analyzer_impl.dart \
  test/all.dart

# Run the tests.
# Note: the "-j1" is necessary because some tests temporarily change the
# working directory, and the working directory state is shared across isolates.
pub run test -j1

# Install dart_coveralls; gather and send coverage data.
if [ "$COVERALLS_TOKEN" ]; then
  pub global activate dart_coveralls
  pub global run dart_coveralls report \
    --exclude-test-files \
    --log-level warning \
    test/all.dart
fi
