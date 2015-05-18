// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Support for linting.
/// NOTE: that this library implementation is CERTAIN to change.
library analyzer_cli.src.lint;

import 'package:analyzer/src/services/lint.dart';
import 'package:linter/src/plugin/linter_plugin.dart';

/// Register default lint rules.
void registerLints() {
  LintGenerator.LINTERS.clear();
  LintGenerator.LINTERS.addAll(linterPlugin.lintRules);
}
