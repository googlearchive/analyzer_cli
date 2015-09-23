// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library analyzer_cli.src.plugin.plugin_config_processor;

import 'package:analyzer/plugin/options.dart';
import 'package:analyzer/src/plugin/plugin_configuration.dart';
import 'package:plugin/plugin.dart';

/// A plugin that registers an extension to process plugin configurations
/// as defined in .`analysis options`.
class PluginConfigProcessorPlugin implements Plugin {
  /// The unique identifier of this plugin.
  static const String UNIQUE_IDENTIFIER = 'plugin_config_processor.core';

  final PluginConfigOptionsProcessor _optionProcessor;

  PluginConfigProcessorPlugin([ErrorHandler handler])
      : _optionProcessor = new PluginConfigOptionsProcessor(handler);

  PluginConfig get pluginConfig => _optionProcessor.config;

  @override
  String get uniqueIdentifier => UNIQUE_IDENTIFIER;

  @override
  void registerExtensionPoints(RegisterExtensionPoint registerExtensionPoint) {
    // There are no extension points.
  }

  @override
  void registerExtensions(RegisterExtension registerExtension) {
    registerExtension(OPTIONS_PROCESSOR_EXTENSION_POINT_ID, _optionProcessor);
  }
}
