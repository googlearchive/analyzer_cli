// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library analyzer_cli.src.driver;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/error.dart';
import 'package:analyzer/src/generated/interner.dart';
import 'package:analyzer/src/generated/java_engine.dart';
import 'package:analyzer/src/generated/utilities_general.dart';
import 'package:analyzer_cli/src/analyzer_impl.dart';
import 'package:analyzer_cli/src/options.dart';
import 'package:linter/src/plugin/linter_plugin.dart';
import 'package:plugin/manager.dart';
import 'package:plugin/plugin.dart';

ErrorSeverity _analyzeAll(CommandLineOptions options, bool isBatch) {
  if (!options.machineFormat) {
    stdout.writeln("Analyzing ${options.sourceFiles}...");
  }
  ErrorSeverity allResult = ErrorSeverity.NONE;
  for (String sourcePath in options.sourceFiles) {
    sourcePath = sourcePath.trim();
    // check that file exists
    if (!new File(sourcePath).existsSync()) {
      print('File not found: $sourcePath');
      exitCode = ErrorSeverity.ERROR.ordinal;
      // fail fast; don't analyze more files
      return ErrorSeverity.ERROR;
    }
    // check that file is Dart file
    if (!AnalysisEngine.isDartFileName(sourcePath)) {
      print('$sourcePath is not a Dart file');
      exitCode = ErrorSeverity.ERROR.ordinal;
      // fail fast; don't analyze more files
      return ErrorSeverity.ERROR;
    }
    ErrorSeverity status = _runAnalyzer(options, sourcePath, isBatch);
    allResult = allResult.max(status);
  }
  return allResult;
}

ErrorSeverity _runAnalyzer(
    CommandLineOptions options, String sourcePath, bool isBatch) {
  if (options.warmPerf) {
    int startTime = currentTimeMillis();
    AnalyzerImpl analyzer =
        new AnalyzerImpl(sourcePath, options, startTime, isBatch);
    analyzer.analyzeSync(printMode: 2);

    for (int i = 0; i < 8; i++) {
      startTime = currentTimeMillis();
      analyzer = new AnalyzerImpl(sourcePath, options, startTime, isBatch);
      analyzer.analyzeSync(printMode: 0);
    }

    PerformanceTag.reset();
    startTime = currentTimeMillis();
    analyzer = new AnalyzerImpl(sourcePath, options, startTime, isBatch);
    return analyzer.analyzeSync();
  }
  int startTime = currentTimeMillis();
  AnalyzerImpl analyzer =
      new AnalyzerImpl(sourcePath, options, startTime, isBatch);
  var errorSeverity = analyzer.analyzeSync();
  if (errorSeverity == ErrorSeverity.ERROR) {
    exitCode = errorSeverity.ordinal;
  }
  if (options.warningsAreFatal && errorSeverity == ErrorSeverity.WARNING) {
    exitCode = errorSeverity.ordinal;
  }
  return errorSeverity;
}

typedef ErrorSeverity _BatchRunnerHandler(List<String> args);

class Driver {

  /// The plugins that are defined outside the `analyzer_cli` package.
  List<Plugin> _userDefinedPlugins = <Plugin>[];

  /// Set the [plugins] that are defined outside the `analyzer_cli` package.
  void set userDefinedPlugins(List<Plugin> plugins) {
    _userDefinedPlugins = plugins == null ? <Plugin>[] : plugins;
  }

  /// Use the given command-line [args] to start this analysis driver.
  void start(List<String> args) {
    StringUtilities.INTERNER = new MappedInterner();
    _processPlugins();
    CommandLineOptions options = CommandLineOptions.parse(args);
    if (options.shouldBatch) {
      _BatchRunner.runAsBatch(args, (List<String> args) {
        CommandLineOptions options = CommandLineOptions.parse(args);
        return _analyzeAll(options, true);
      });
    } else {
      _analyzeAll(options, false);
    }
  }

  void _processPlugins() {
    List<Plugin> plugins = <Plugin>[];
    // TODO(pquitslund): add once engine plugin imports are fixed
    //plugins.add(AnalysisEngine.instance.enginePlugin);
    plugins.add(linterPlugin);
    plugins.addAll(_userDefinedPlugins);
    ExtensionManager manager = new ExtensionManager();
    manager.processPlugins(plugins);
  }
}

/// Provides a framework to read command line options from stdin and feed them
/// to a callback.
class _BatchRunner {
  /// Run the tool in 'batch' mode, receiving command lines through stdin and
  /// returning pass/fail status through stdout. This feature is intended for
  /// use in unit testing.
  static void runAsBatch(List<String> sharedArgs, _BatchRunnerHandler handler) {
    stdout.writeln('>>> BATCH START');
    Stopwatch stopwatch = new Stopwatch();
    stopwatch.start();
    int testsFailed = 0;
    int totalTests = 0;
    ErrorSeverity batchResult = ErrorSeverity.NONE;
    // read line from stdin
    Stream cmdLine =
        stdin.transform(UTF8.decoder).transform(new LineSplitter());
    cmdLine.listen((String line) {
      // may be finish
      if (line.isEmpty) {
        var time = stopwatch.elapsedMilliseconds;
        stdout.writeln(
            '>>> BATCH END (${totalTests - testsFailed}/$totalTests) ${time}ms');
        exitCode = batchResult.ordinal;
      }
      // prepare aruments
      var args;
      {
        var lineArgs = line.split(new RegExp('\\s+'));
        args = new List<String>();
        args.addAll(sharedArgs);
        args.addAll(lineArgs);
        args.remove('-b');
        args.remove('--batch');
      }
      // analyze single set of arguments
      try {
        totalTests++;
        ErrorSeverity result = handler(args);
        bool resultPass = result != ErrorSeverity.ERROR;
        if (!resultPass) {
          testsFailed++;
        }
        batchResult = batchResult.max(result);
        // Write stderr end token and flush.
        stderr.writeln('>>> EOF STDERR');
        String resultPassString = resultPass ? 'PASS' : 'FAIL';
        stdout.writeln(
            '>>> TEST $resultPassString ${stopwatch.elapsedMilliseconds}ms');
      } catch (e, stackTrace) {
        stderr.writeln(e);
        stderr.writeln(stackTrace);
        stderr.writeln('>>> EOF STDERR');
        stdout.writeln('>>> TEST CRASH');
      }
    });
  }
}
