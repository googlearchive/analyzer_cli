// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library analyzer_cli.test.driver;

import 'dart:io';

import 'package:analyzer/plugin/options.dart';
import 'package:analyzer_cli/src/driver.dart';
import 'package:path/path.dart' as path;
import 'package:plugin/plugin.dart';
import 'package:test/test.dart';
import 'package:yaml/src/yaml_node.dart';

main() {
  group('Driver', () {
    group('options', () {
      test('processing', () {
        Driver driver = new Driver();
        TestProcessor processor = new TestProcessor();
        driver.userDefinedPlugins = [new TestPlugin(processor)];
        driver.start([
          '--options',
          'test/data/test_options.yaml',
          'test/data/test_file.dart'
        ]);
        expect(processor.options['test_plugin'], isNotNull);
        expect(processor.exception, isNull);
      });
    });

    group('in temp directory', () {
      StringSink savedOutSink, savedErrorSink;
      int savedExitCode;
      Directory savedCurrentDirectory;
      Directory tempDir;
      setUp(() {
        savedOutSink = outSink;
        savedErrorSink = errorSink;
        savedExitCode = exitCode;
        outSink = new StringBuffer();
        errorSink = new StringBuffer();
        savedCurrentDirectory = Directory.current;
        tempDir = Directory.systemTemp.createTempSync('analyzer_');
      });
      tearDown(() {
        outSink = savedOutSink;
        errorSink = savedErrorSink;
        exitCode = savedExitCode;
        Directory.current = savedCurrentDirectory;
        tempDir.deleteSync(recursive: true);
      });

      test('packages folder', () {
        Directory.current = tempDir;
        new File(path.join(tempDir.path, 'test.dart')).writeAsStringSync('''
import 'package:foo/bar.dart';
main() {
  baz();
}
        ''');
        Directory packagesDir =
            new Directory(path.join(tempDir.path, 'packages'));
        packagesDir.createSync();
        Directory fooDir = new Directory(path.join(packagesDir.path, 'foo'));
        fooDir.createSync();
        new File(path.join(fooDir.path, 'bar.dart')).writeAsStringSync('''
void baz() {}
        ''');
        new Driver().start(['test.dart']);
        expect(exitCode, 0);
      });

      test('no package resolution', () {
        Directory.current = tempDir;
        new File(path.join(tempDir.path, 'test.dart')).writeAsStringSync('''
import 'package:path/path.dart';
main() {}
        ''');
        new Driver().start(['test.dart']);
        expect(exitCode, 3);
        String stdout = outSink.toString();
        expect(stdout, contains('[error] Target of URI does not exist'));
        expect(stdout, contains('1 error found.'));
        expect(errorSink.toString(), '');
      });
    });
  });
}

class TestPlugin extends Plugin {
  TestProcessor processor;
  TestPlugin(this.processor);

  @override
  String get uniqueIdentifier => 'test_plugin.core';

  @override
  void registerExtensionPoints(RegisterExtensionPoint register) {
    // None
  }

  @override
  void registerExtensions(RegisterExtension register) {
    register(OPTIONS_PROCESSOR_EXTENSION_POINT_ID, processor);
  }
}

class TestProcessor extends OptionsProcessor {
  Map<String, YamlNode> options;
  Exception exception;

  @override
  void onError(Exception exception) {
    this.exception = exception;
  }

  @override
  void optionsProcessed(Map<String, YamlNode> options) {
    this.options = options;
  }
}
