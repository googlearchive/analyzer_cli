// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library analyzer_cli.src.bootloader;

import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/plugin/options.dart';
import 'package:analyzer/source/analysis_options_provider.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/plugin/plugin_configuration.dart';
import 'package:analyzer_cli/src/driver.dart';
import 'package:analyzer_cli/src/options.dart';
import 'package:analyzer_cli/src/plugin/plugin_config_processor_plugin.dart';
import 'package:plugin/manager.dart';
import 'package:plugin/plugin.dart';
import 'package:source_span/source_span.dart';
import 'package:yaml/src/yaml_node.dart';

const _analyzerPackageName = 'analyzer';

/// Source code assembler.
class Assembler {
  /// Plugin configuration info.
  final PluginConfig _config;

  /// Create an assembler for the given plugin [config].
  Assembler(this._config);

  /// A string enumerating required package `import`s.
  String get enumerateImports =>
      plugins.map((PluginInfo p) => "import '${p.libraryUri}';").join('\n');

  /// A string listing initialized plugin instances.
  String get pluginList =>
      plugins.map((PluginInfo p) => 'new ${p.className}()').join(', ');

  /// Plugins to configure.
  List<PluginInfo> get plugins => _config.plugins;

  /// Create a file containing a `main()` suitable for loading in spawned
  /// isolate.
  String createMain() => _generateMain();

  String _generateMain() => """
// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// This code was auto-generated, is not intended to be edited, and is subject to
// significant change. Please see the README file for more information.

import 'package:analyzer_cli/src/driver.dart';

$enumerateImports

void main(List<String> args) {
  var starter = new Driver();
  starter.userDefinedPlugins = [$pluginList];
  starter.start(args);
}
""";
}

/// Given environment information extracted from command-line `args`, creates a
/// a loadable analyzer "image".
class BootLoader {
  /// Emits an error message to [errorSink] if plugin config can't be read.
  static final ErrorHandler _pluginConfigErrorHandler = (Exception e) {
    String details;
    if (e is PluginConfigFormatException) {
      details = e.message;
      var node = e.yamlNode;
      if (node is YamlNode) {
        SourceLocation location = node.span.start;
        details += ' (line ${location.line}, column ${location.column})';
      }
    } else {
      details = e.toString();
    }

    errorSink.writeln('Plugin configuration skipped: $details');
  };

  /// Reads plugin config info from `.analysis_options`.
  PluginConfigProcessorPlugin _pluginConfigProcessorPlugin =
      new PluginConfigProcessorPlugin(_pluginConfigErrorHandler);

  /// Create a loadable analyzer image configured with plugins derived from
  /// the given analyzer command-line `args`.
  Image createImage(List<String> args) {
    _processPlugins();

    // Parse commandline options.
    CommandLineOptions options = CommandLineOptions.parse(args);

    // Process analysis options file (and notify all interested parties).
    _processAnalysisOptions(options);

    // TODO(pquitslund): Pass in .packages info
    return new Image(_pluginConfigProcessorPlugin.pluginConfig,
        args: args, packageRootPath: options.packageRootPath);
  }

  void _processAnalysisOptions(CommandLineOptions options) {
    // Determine options file path.
    var filePath = options.analysisOptionsFile != null
        ? options.analysisOptionsFile
        : AnalysisOptionsProvider.ANALYSIS_OPTIONS_NAME;
    List<OptionsProcessor> optionsProcessors =
        AnalysisEngine.instance.optionsPlugin.optionsProcessors;
    try {
      var file = PhysicalResourceProvider.INSTANCE.getFile(filePath);
      AnalysisOptionsProvider analysisOptionsProvider =
          new AnalysisOptionsProvider();
      Map<String, YamlNode> options =
          analysisOptionsProvider.getOptionsFromFile(file);
      optionsProcessors
          .forEach((OptionsProcessor p) => p.optionsProcessed(options));
    } on Exception catch (e) {
      optionsProcessors.forEach((OptionsProcessor p) => p.onError(e));
    }
  }

  void _processPlugins() {
    List<Plugin> plugins = <Plugin>[];
    plugins.add(_pluginConfigProcessorPlugin);
    plugins.addAll(AnalysisEngine.instance.supportedPlugins);
    ExtensionManager manager = new ExtensionManager();
    manager.processPlugins(plugins);
  }
}

/// A loadable "image" of a a configured analyzer instance.
class Image {
  /// (Optional) package root path.
  final String packageRootPath;

  /// (Optional) package map.
  final Map<String, Uri> packages;

  /// Args to be passed on to the loaded main.
  final List<String> args;

  /// Plugin configuration.
  final PluginConfig config;

  /// Create an image with the given [config] and optionally [packages],
  /// [packageRootPath], and command line [args].
  Image(this.config, {this.packages, this.packageRootPath, this.args});

  /// Load this image.
  ///
  /// Loading an image consists in assembling an analyzer `main()`, configured
  /// to include the appropriate analyzer plugins as specified in
  /// `.analyzer_options` which is then run in a spawned isolate.
  void load() {
    String mainSource = new Assembler(config).createMain();

    Uri uri =
        Uri.parse('data:application/dart;charset=utf-8,${Uri.encodeComponent(
            mainSource)}');

    ReceivePort errorListener = new ReceivePort();
    errorListener.listen((data) {
      //TODO(pquitslund): handle errors.
      print('>>> ERROR: $data');
    });

    ReceivePort exitListener = new ReceivePort();
    exitListener.listen((data) {
      // Propagate exit code.
      exit(exitCode);
    });

    // TODO(pquitslund): update once .packages are supported.
    String packageRoot =
        packageRootPath != null ? packageRootPath : './packages';
    Uri packageUri = new Uri.file(packageRoot);

    // TODO(pquitslund): add .packages support once the VM implements it.
    Isolate.spawnUri(uri, args, null /* msg */,
        packageRoot: packageUri,
        onError: errorListener.sendPort,
        onExit: exitListener.sendPort);

    // TODO(pquitslund): consider starting paused
    // http://stackoverflow.com/questions/29247374/what-is-the-best-way-to-track-the-state-of-an-isolate-in-dart
  }
}
