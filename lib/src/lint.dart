// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Support for linting.
/// NOTE: that this library implementation is CERTAIN to change.
library analyzer_cli.src.lint;

import 'package:analyzer/src/services/lint.dart';
import 'package:linter/src/linter.dart';
import 'package:linter/src/rules/camel_case_types.dart';
import 'package:linter/src/rules/constant_identifier_names.dart';
import 'package:linter/src/rules/empty_constructor_bodies.dart';
import 'package:linter/src/rules/library_names.dart';
import 'package:linter/src/rules/library_prefixes.dart';
import 'package:linter/src/rules/non_constant_identifier_names.dart';
import 'package:linter/src/rules/one_member_abstracts.dart';
import 'package:linter/src/rules/slash_for_doc_comments.dart';
import 'package:linter/src/rules/super_goes_last.dart';
import 'package:linter/src/rules/type_init_formals.dart';
import 'package:linter/src/rules/unnecessary_brace_in_string_interp.dart';

/// Default lint rules. (To be replaced with a plugin contribution.)
final List<LintRule> _rules = [
  new CamelCaseTypes(),
  new ConstantIdentifierNames(),
  new EmptyConstructorBodies(),
  new LibraryNames(),
  new LibraryPrefixes(),
  new NonConstantIdentifierNames(),
  new OneMemberAbstracts(),
  new SlashForDocComments(),
  new SuperGoesLast(),
  new TypeInitFormals(),
  new UnnecessaryBraceInStringInterp()
];

/// Register default lint rules.
void registerLints() {
  LintGenerator.LINTERS.clear();
  LintGenerator.LINTERS.addAll(_rules);
}
