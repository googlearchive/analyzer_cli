// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library analyzer_cli.src.driver;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/file_system/file_system.dart' as fileSystem;
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/source/package_map_provider.dart';
import 'package:analyzer/source/package_map_resolver.dart';
import 'package:analyzer/source/pub_package_map_provider.dart';
import 'package:analyzer/src/generated/constant.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/error.dart';
import 'package:analyzer/src/generated/interner.dart';
import 'package:analyzer/src/generated/java_engine.dart';
import 'package:analyzer/src/generated/java_io.dart';
import 'package:analyzer/src/generated/sdk_io.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/src/generated/source_io.dart';
import 'package:analyzer_cli/src/analyzer_impl.dart';
import 'package:analyzer_cli/src/options.dart';
import 'package:linter/src/plugin/linter_plugin.dart';
import 'package:package_config/packages_file.dart' as pkgfile show parse;
import 'package:path/path.dart' as path;
import 'package:plugin/manager.dart';
import 'package:plugin/plugin.dart';

/// The maximum number of sources for which AST structures should be kept in the cache.
const int _maxCacheSize = 512;

typedef ErrorSeverity _BatchRunnerHandler(List<String> args);

class Driver {

  /// The plugins that are defined outside the `analyzer_cli` package.
  List<Plugin> _userDefinedPlugins = <Plugin>[];

  /// Indicates whether the analyzer is running in batch mode.
  bool _isBatch;

  /// The context that was most recently created by a call to [_analyzeAll], or
  /// `null` if [_analyzeAll] hasn't been called yet.
  AnalysisContext _context;

  /// If [_context] is not `null`, the [CommandLineOptions] that guided its
  /// creation.
  CommandLineOptions _previousOptions;

  /// Set the [plugins] that are defined outside the `analyzer_cli` package.
  void set userDefinedPlugins(List<Plugin> plugins) {
    _userDefinedPlugins = plugins == null ? <Plugin>[] : plugins;
  }

  /// Use the given command-line [args] to start this analysis driver.
  void start(List<String> args) {
    StringUtilities.INTERNER = new MappedInterner();
    _processPlugins();
    CommandLineOptions options = CommandLineOptions.parse(args);
    // In batch mode, SDK is specified on the main command line rather than in
    // the command lines sent to stdin.  So process it before deciding whether
    // to activate batch mode.
    if (sdk == null) {
      sdk = new DirectoryBasedDartSdk(new JavaFile(options.dartSdkPath));
    }
    _isBatch = options.shouldBatch;
    if (_isBatch) {
      _BatchRunner.runAsBatch(args, (List<String> args) {
        CommandLineOptions options = CommandLineOptions.parse(args);
        return _analyzeAll(options);
      });
    } else {
      _analyzeAll(options);
    }
  }

  /// Perform analysis according to the given [options].
  ErrorSeverity _analyzeAll(CommandLineOptions options) {
    if (!options.machineFormat) {
      stdout.writeln("Analyzing ${options.sourceFiles}...");
    }

    // Create a context, or re-use the previous one.
    _createAnalysisContext(options);

    // Add all the files to be analyzed en masse to the context.  Skip any
    // files that were added earlier (whether explicitly or implicitly) to
    // avoid causing those files to be unnecessarily re-read.
    Set<Source> knownSources = _context.sources.toSet();
    List<Source> sourcesToAnalyze = <Source>[];
    ChangeSet changeSet = new ChangeSet();
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
      Source source = _computeLibrarySource(sourcePath);
      if (!knownSources.contains(source)) {
        changeSet.addedSource(source);
      }
      sourcesToAnalyze.add(source);
    }
    _context.applyChanges(changeSet);

    // Analyze the files.
    ErrorSeverity allResult = ErrorSeverity.NONE;
    for (Source source in sourcesToAnalyze) {
      ErrorSeverity status = _runAnalyzer(source, options);
      allResult = allResult.max(status);
    }
    return allResult;
  }

  /// Determine whether the context created during a previous call to
  /// [_analyzeAll] can be re-used in order to analyze using [options].
  bool _canContextBeReused(CommandLineOptions options) {
    // TODO(paulberry): add a command-line option that disables context re-use.
    if (_context == null) {
      return false;
    }
    if (options.packageRootPath != _previousOptions.packageRootPath) {
      return false;
    }
    if (options.packageConfigPath != _previousOptions.packageConfigPath) {
      return false;
    }
    if (!_equalMaps(
        options.customUrlMappings, _previousOptions.customUrlMappings)) {
      return false;
    }
    if (!_equalMaps(
        options.definedVariables, _previousOptions.definedVariables)) {
      return false;
    }
    if (options.log != _previousOptions.log) {
      return false;
    }
    if (options.disableHints != _previousOptions.disableHints) {
      return false;
    }
    if (options.enableNullAwareOperators !=
        _previousOptions.enableNullAwareOperators) {
      return false;
    }
    if (options.enableStrictCallChecks !=
        _previousOptions.enableStrictCallChecks) {
      return false;
    }
    if (options.showPackageWarnings != _previousOptions.showPackageWarnings) {
      return false;
    }
    if (options.showSdkWarnings != _previousOptions.showSdkWarnings) {
      return false;
    }
    if (options.lints != _previousOptions.lints) {
      return false;
    }
    return true;
  }

  /// Decide on the appropriate policy for which files need to be fully parsed
  /// and which files need to be diet parsed, based on [options], and return an
  /// [AnalyzeFunctionBodiesPredicate] that implements this policy.
  AnalyzeFunctionBodiesPredicate _chooseDietParsingPolicy(
      CommandLineOptions options) {
    if (_isBatch) {
      // As analyzer is currently implemented, once a file has been diet
      // parsed, it can't easily be un-diet parsed without creating a brand new
      // context and losing caching.  In batch mode, we can't predict which
      // files we'll need to generate errors and warnings for in the future, so
      // we can't safely diet parse anything.
      return (Source source) => true;
    }

    // Determine the set of packages requiring a full parse.  Use null to
    // represent the case where all packages require a full parse.
    Set<String> packagesRequiringFullParse;
    if (options.showPackageWarnings) {
      // We are showing warnings from all packages so all packages require a
      // full parse.
      packagesRequiringFullParse = null;
    } else {
      // We aren't showing warnings for dependent packages, but we may still
      // need to show warnings for "self" packages, so we need to do a full
      // parse in any package containing files mentioned on the command line.
      // TODO(paulberry): implement this.  As a temporary workaround, we're
      // fully parsing all packages.
      packagesRequiringFullParse = null;
    }
    return (Source source) {
      if (source.uri.scheme == 'dart') {
        return options.showSdkWarnings;
      } else if (source.uri.scheme == 'package') {
        if (packagesRequiringFullParse == null) {
          return true;
        } else if (source.uri.pathSegments.length == 0) {
          // We should never see a URI like this, but fully parse it to be
          // safe.
          return true;
        } else {
          return packagesRequiringFullParse
              .contains(source.uri.pathSegments[0]);
        }
      } else {
        return true;
      }
    };
  }

  /// Decide on the appropriate method for resolving URIs based on the given
  /// [options] and [customUrlMappings] settings, and return a
  /// [SourceFactory] that has been configured accordingly.
  SourceFactory _chooseUriResolutionPolicy(
      CommandLineOptions options, Map<String, String> customUrlMappings) {
    List<UriResolver> resolvers = [
      new CustomUriResolver(customUrlMappings),
      new DartUriResolver(sdk)
    ];

    if (options.packageConfigPath != null) {
      String packageConfigPath = options.packageConfigPath;
      Uri fileUri = new Uri.file(packageConfigPath);
      try {
        File configFile = new File.fromUri(fileUri);
        List<int> bytes = configFile.readAsBytesSync();
        Map<String, Uri> map = pkgfile.parse(bytes, fileUri);
        // TODO(pquitslund): plug into new resolver once implemented
        // https://github.com/dart-lang/sdk/issues/23615
      } catch (e) {
        printAndFail(
            'Unable to read package config data from $packageConfigPath: $e');
      }
      printAndFail(
          'Package config files are not supported yet. For status see: https://github.com/dart-lang/sdk/issues/23373');
    } else if (options.packageRootPath != null) {
      JavaFile packageDirectory = new JavaFile(options.packageRootPath);
      resolvers.add(new PackageUriResolver([packageDirectory]));
    } else {
      PubPackageMapProvider pubPackageMapProvider =
          new PubPackageMapProvider(PhysicalResourceProvider.INSTANCE, sdk);
      PackageMapInfo packageMapInfo = pubPackageMapProvider.computePackageMap(
          PhysicalResourceProvider.INSTANCE.getResource('.'));
      Map<String, List<fileSystem.Folder>> packageMap =
          packageMapInfo.packageMap;
      if (packageMap != null) {
        resolvers.add(new PackageMapUriResolver(
            PhysicalResourceProvider.INSTANCE, packageMap));
      }
    }
    resolvers.add(new FileUriResolver());
    return new SourceFactory(resolvers);
  }

  /// Convert the given [sourcePath] (which may be relative to the current
  /// working directory) to a [Source] object that can be fed to the analysis
  /// context.
  Source _computeLibrarySource(String sourcePath) {
    sourcePath = _normalizeSourcePath(sourcePath);
    JavaFile sourceFile = new JavaFile(sourcePath);
    Source source = sdk.fromFileUri(sourceFile.toURI());
    if (source != null) {
      return source;
    }
    source = new FileBasedSource.con2(sourceFile.toURI(), sourceFile);
    Uri uri = _context.sourceFactory.restoreUri(source);
    if (uri == null) {
      return source;
    }
    return new FileBasedSource.con2(uri, sourceFile);
  }

  /// Create an analysis context that is prepared to analyze sources according
  /// to the given [options], and store it in [_context].
  void _createAnalysisContext(CommandLineOptions options) {
    if (_canContextBeReused(options)) {
      return;
    }
    _previousOptions = options;
    // Choose a package resolution policy and a diet parsing policy based on
    // the command-line options.
    SourceFactory sourceFactory =
        _chooseUriResolutionPolicy(options, options.customUrlMappings);
    AnalyzeFunctionBodiesPredicate dietParsingPolicy =
        _chooseDietParsingPolicy(options);
    // Create a context using these policies.
    AnalysisContext context = AnalysisEngine.instance.createAnalysisContext();
    context.sourceFactory = sourceFactory;
    Map<String, String> definedVariables = options.definedVariables;
    if (!definedVariables.isEmpty) {
      DeclaredVariables declaredVariables = context.declaredVariables;
      definedVariables.forEach((String variableName, String value) {
        declaredVariables.define(variableName, value);
      });
    }
    // Uncomment the following to have errors reported on stdout and stderr
    AnalysisEngine.instance.logger = new StdLogger(options.log);

    // set options for context
    AnalysisOptionsImpl contextOptions = new AnalysisOptionsImpl();
    contextOptions.cacheSize = _maxCacheSize;
    contextOptions.hint = !options.disableHints;
    contextOptions.enableNullAwareOperators = options.enableNullAwareOperators;
    contextOptions.enableStrictCallChecks = options.enableStrictCallChecks;
    contextOptions.analyzeFunctionBodiesPredicate = dietParsingPolicy;
    contextOptions.generateImplicitErrors = options.showPackageWarnings;
    contextOptions.generateSdkErrors = options.showSdkWarnings;
    contextOptions.lint = options.lints;
    context.analysisOptions = contextOptions;
    _context = context;
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

  /// Analyze a single source.
  ErrorSeverity _runAnalyzer(Source source, CommandLineOptions options) {
    int startTime = currentTimeMillis();
    AnalyzerImpl analyzer =
        new AnalyzerImpl(_context, source, options, startTime);
    var errorSeverity = analyzer.analyzeSync();
    if (errorSeverity == ErrorSeverity.ERROR) {
      exitCode = errorSeverity.ordinal;
    }
    if (options.warningsAreFatal && errorSeverity == ErrorSeverity.WARNING) {
      exitCode = errorSeverity.ordinal;
    }
    return errorSeverity;
  }

  /// Perform a deep comparison of two string maps.
  static bool _equalMaps(Map<String, String> m1, Map<String, String> m2) {
    if (m1.length != m2.length) {
      return false;
    }
    for (String key in m1.keys) {
      if (!m2.containsKey(key) || m1[key] != m2[key]) {
        return false;
      }
    }
    return true;
  }

  /// Convert [sourcePath] into an absolute path.
  static String _normalizeSourcePath(String sourcePath) {
    return path.normalize(new File(sourcePath).absolute.path);
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
