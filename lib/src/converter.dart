import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:recase/recase.dart';

import 'models/schema_model.dart';
import 'parsers/json_schema_parser.dart';

/// Main class that manages the conversion of schemas to Dart/Freezed classes
class JsonSchemaToFreezed {
  final bool freezed;
  final bool jsonSerializable;
  final Map<String, String> headers;

  JsonSchemaToFreezed({
    this.freezed = true,
    this.jsonSerializable = true,
    this.headers = const {},
  });

  /// Converts schema from a URL to Dart/Freezed classes
  Future<bool> convertFromUrl(String url, String outputPath) async {
    try {
      final response = await http.get(Uri.parse(url), headers: headers);

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to retrieve schema. Status: ${response.statusCode}',
        );
      }

      final jsonData = json.decode(response.body);
      return _processSchemaData(jsonData, outputPath);
    } catch (e) {
      print('Error converting from URL: $e');
      return false;
    }
  }

  /// Converts schema from a local file to Dart/Freezed classes
  Future<bool> convertFromFile(String filePath, String outputPath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File not found: $filePath');
      }

      final content = await file.readAsString();
      final extension = path.extension(filePath).toLowerCase();

      if (extension == '.json') {
        final jsonData = json.decode(content);
        return _processSchemaData(jsonData, outputPath);
      } else {
        throw Exception('Unsupported file format: $extension. Use .json');
      }
    } catch (e) {
      print('Error converting from file: $e');
      return false;
    }
  }

  Future<bool> _processSchemaData(dynamic jsonData, String outputPath) async {
    final parser = JsonSchemaParser();
    final schema = await parser.parse(jsonData);

    // Transform model names to use AdapterParams instead of Params
    for (var model in schema.models) {
      if (model.name.endsWith('Params')) {
        model.name =
            '${model.name.substring(0, model.name.length - 'Params'.length)}AdapterParams';
      }
    }

    // Check if user requested separate files
    final generateSeparateFiles = outputPath.contains("*");

    if (generateSeparateFiles) {
      return _generateSeparateFiles(schema, outputPath);
    } else {
      return _generateDartClasses(schema, outputPath);
    }
  }

  Future<bool> _generateSeparateFiles(
    Schema schema,
    String outputPathTemplate,
  ) async {
    try {
      bool allSuccess = true;
      final directory = Directory(
        path.dirname(outputPathTemplate.replaceAll("*", "")),
      );
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      for (final model in schema.models) {
        final fileName = _getFileName(model.name);

        final outputPath = outputPathTemplate.replaceAll("*", fileName);

        final output = File(outputPath);
        final buffer = StringBuffer();

        // Add necessary imports
        if (freezed) {
          buffer.writeln("// GENERATED CODE - DO NOT MODIFY MANUALLY");
          buffer.writeln(
            "// Generated on: ${DateTime.now().toIso8601String()}",
          );
          buffer.writeln();
          buffer.writeln(
            "import 'package:freezed_annotation/freezed_annotation.dart';",
          );

          if (jsonSerializable) {
            buffer.writeln(
              "import 'package:json_annotation/json_annotation.dart';",
            );
          }

          buffer.writeln("import 'dart:convert';");

          final referenceFields = model.fields.where(
            (f) => f.type.kind == TypeKind.reference,
          );
          if (referenceFields.isNotEmpty) {
            buffer.writeln();
            for (final field in referenceFields) {
              final referenceFileName = _getFileName(field.type.reference!);
              buffer.writeln(
                "import '../$referenceFileName/$referenceFileName.dart';",
              );
            }
          }

          buffer.writeln();

          final fileNameBase = path.basenameWithoutExtension(outputPath);
          buffer.writeln("part '$fileNameBase.freezed.dart';");

          if (jsonSerializable) {
            buffer.writeln("part '$fileNameBase.g.dart';");
          }

          buffer.writeln();
        }

        // Generate class for this model
        _generateModelClass(buffer, model);

        await output.writeAsString(buffer.toString());
        print('✅ Class generated: ${model.name} -> $outputPath');
      }

      return allSuccess;
    } catch (e) {
      print('Error generating Dart classes: $e');
      return false;
    }
  }

  String _getFileName(String modelName) {
    String fileName = ReCase(modelName).snakeCase;

    if (fileName.endsWith('_adapter_params')) {
      fileName =
          '${fileName.substring(0, fileName.length - '_adapter_params'.length)}_adapter';
    } else if (fileName.endsWith('_params')) {
      fileName =
          '${fileName.substring(0, fileName.length - '_params'.length)}_adapter';
    }

    return fileName;
  }

  Future<bool> _generateDartClasses(Schema schema, String outputPath) async {
    try {
      final directory = Directory(path.dirname(outputPath));
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final output = File(outputPath);
      final buffer = StringBuffer();

      // Add necessary imports
      if (freezed) {
        buffer.writeln("// GENERATED CODE - DO NOT MODIFY MANUALLY");
        buffer.writeln();
        buffer.writeln(
          "import 'package:freezed_annotation/freezed_annotation.dart';",
        );

        if (jsonSerializable) {
          buffer.writeln(
            "import 'package:json_annotation/json_annotation.dart';",
          );
        }

        buffer.writeln("import 'dart:convert';");

        for (final model in schema.models) {
          // Add imports for reference fields
          final Set<String> referenceFields = {};

          for (final field in model.fields) {
            if (field.type.kind == TypeKind.reference) {
              referenceFields.add(field.type.reference!);
            } else if (field.type.kind == TypeKind.array &&
                field.type.itemType?.kind == TypeKind.reference) {
              referenceFields.add(field.type.itemType!.reference!);
            }
          }

          if (model.unionVariants != null) {
            for (final variant in model.unionVariants!) {
              for (final field in variant.fields) {
                if (field.type.kind == TypeKind.reference) {
                  referenceFields.add(field.type.reference!);
                } else if (field.type.kind == TypeKind.array &&
                    field.type.itemType?.kind == TypeKind.reference) {
                  referenceFields.add(field.type.itemType!.reference!);
                }
              }
            }
          }

          if (referenceFields.isNotEmpty) {
            buffer.writeln();
            for (final fieldString in referenceFields) {
              final referenceFileName = _getFileName(fieldString);
              buffer.writeln(
                "import '../$referenceFileName/$referenceFileName.dart';",
              );
            }
          }
        }

        buffer.writeln();

        final fileName = path.basenameWithoutExtension(outputPath);
        buffer.writeln("part '$fileName.freezed.dart';");

        if (jsonSerializable) {
          buffer.writeln("part '$fileName.g.dart';");
        }

        buffer.writeln();
      }

      // Generate classes for each model in the schema
      for (final model in schema.models) {
        _generateModelClass(buffer, model);
      }

      await output.writeAsString(buffer.toString());
      return true;
    } catch (e) {
      print('Error generating Dart classes: $e');
      return false;
    }
  }

  void _generateModelClass(StringBuffer buffer, Model model) {
    if (freezed) {
      if (model.unionKey != null) {
        buffer.writeln("@Freezed(unionKey: '${model.unionKey}')");
      } else {
        buffer.writeln("@freezed");
      }
      // Check if the model is a child of another class
      final abstractClass = model.isAbstract ? "abstract " : "";

      // final parentClass =
      // model.parentClass != null ? "extends ${model.parentClass} " : "";
      buffer.writeln(
        "${abstractClass}class ${model.name} with _\$${model.name} {",
      );

      // Internal variables to hold parentClass and isAbstract for later use to allow removal
      // final bool hasParentClass = model.parentClass != null;
      // final bool isAbstract = model.isAbstract;

      // Private Constructor
      if (model.unionKey != null) {
        buffer.writeln("  const ${model.name}._();");
        buffer.writeln();

        // Implement the factory constructors for the union variants
        if (model.unionVariants != null && model.unionVariants!.isNotEmpty) {
          for (final variant in model.unionVariants!) {
            final variantName = variant.variantName;
            final variantFields = variant.fields;

            if (variant.isDefaultVariant) {
              buffer.writeln('  @FreezedUnionValue(\'${variant.unionValue}\')');
            }

            buffer.writeln(
              "  const factory ${model.name}${variantName != null ? '.${ReCase(variantName).camelCase}' : ''}({",
            );
            for (final field in variantFields) {
              //   final dartType = _mapTypeToDart(field.type);
              //   buffer.writeln("    $dartType ${field.name},");
              // }
              final dartType = _mapTypeToDart(field.type);
              final nullableMark = field.isNullable ? '?' : '';
              final defaultUnionValue = variant.unionValue ? true : false;
              final defaultMark =
                  field.name == model.unionKey
                      ? "@Default($defaultUnionValue) "
                      : '';
              final requiredMark =
                  field.isNullable && defaultMark != '' ? '' : 'required ';

              if (field.description != null && field.description!.isNotEmpty) {
                buffer.writeln("    /// ${field.description}");
              }

              buffer.writeln(
                "    $defaultMark$requiredMark$dartType$nullableMark ${field.name},",
              );
            }
            buffer.writeln("  }) = _$variantName;");
            buffer.writeln();
          }
        }
      } else {
        // Factory Constructor
        buffer.writeln("  const factory ${model.name}({");

        // If the model has a parent class, remove the parentClass field from fields to avoid adding to the generated class
        // if (model.parentClass != null) {
        //   model.fields.removeWhere((field) => field.name == 'parentClass');
        // }

        // Remove the isAbstract field
        // model.fields.removeWhere((field) => field.name == 'isAbstract');

        for (final field in model.fields) {
          final dartType = _mapTypeToDart(field.type);
          final nullableMark = field.isNullable ? '?' : '';
          final requiredMark = field.isNullable ? '' : 'required ';

          if (field.description != null && field.description!.isNotEmpty) {
            buffer.writeln("    /// ${field.description}");
          }

          buffer.writeln(
            "    $requiredMark$dartType$nullableMark ${field.name},",
          );
        }

        buffer.writeln("  }) = _${model.name};");
        // if (!isAbstract) {
        //   if (hasParentClass) {
        //     buffer.writeln();
        //     buffer.writeln("  const ${model.name}._() : super._();");
        //   } else {
        //     buffer.writeln("  const ${model.name}._();");
        //   }
        // }
        buffer.writeln();
      }

      if (jsonSerializable) {
        buffer.writeln(
          "  factory ${model.name}.fromJson(Map<String, dynamic> json) =>",
        );
        buffer.writeln("      _\$${model.name}FromJson(json);");
        // if (model.switchKey != null && model.switchCases != null) {
        //   final switchKey = model.switchKey!;
        //   final switchCases = model.switchCases!;

        //   // fromJson factory
        //   buffer.writeln(
        //     "  factory ${model.name}.fromJson(Map<String, dynamic> json) {",
        //   );
        //   buffer.writeln(
        //     "    final ${switchKey}Value = json['$switchKey'] as bool;",
        //   );
        //   buffer.writeln("      switch (${switchKey}Value) {");
        //   switchCases.forEach((switchCase, subClass) {
        //     String caseLiteral;
        //     if (switchCase == 'true' || switchCase == 'false') {
        //       caseLiteral = switchCase;
        //     } else {
        //       caseLiteral = "'$switchCase'";
        //     }

        //     buffer.writeln("        case $caseLiteral:");
        //     // Call the public constructor of the subclass
        //     buffer.writeln("          return ${subClass}.fromJson(json);");
        //   });

        //   // Default case for unknown switch keys (debugging purposes)
        //   buffer.writeln("        default:");
        //   buffer.writeln(
        //     "          throw Exception('Unknown switch case for \\'$switchKey\\': \$${switchKey}Value');",
        //   );
        //   buffer.writeln("      }");
        //   buffer.writeln("  }");
        // } else {
        //   buffer.writeln(
        //     "  factory ${model.name}.fromJson(Map<String, dynamic> json) =>",
        //   );
        //   buffer.writeln("      _\$${model.name}FromJson(json);");
        // }

        // // toJson method
        // buffer.writeln();
        // if (hasParentClass) {
        //   buffer.writeln("  @override");
        // }
        // buffer.writeln(
        //   "  Map<String, dynamic> toJson() => _\$${model.name}ToJson(this as _${model.name});",
        // );
      }

      buffer.writeln("}");
    } else {
      // Implementation for regular Dart classes (non-Freezed)
      buffer.writeln("class ${model.name} {");

      // Field declarations
      for (final field in model.fields) {
        final dartType = _mapTypeToDart(field.type);
        final nullableMark = field.isNullable ? '?' : '';

        if (field.description != null && field.description!.isNotEmpty) {
          buffer.writeln("  /// ${field.description}");
        }

        buffer.writeln("  final $dartType$nullableMark ${field.name};");
      }

      buffer.writeln();

      // Constructor
      buffer.writeln("  ${model.name}({");
      for (final field in model.fields) {
        final requiredMark = field.isNullable ? '' : 'required ';
        buffer.writeln("    ${requiredMark}this.${field.name},");
      }
      buffer.writeln("  });");

      // fromJson
      if (jsonSerializable) {
        buffer.writeln();
        buffer.writeln(
          "  factory ${model.name}.fromJson(Map<String, dynamic> json) {",
        );
        buffer.writeln("    return ${model.name}(");
        for (final field in model.fields) {
          final castOp = _getCastOperation(field.type, field.isNullable);
          buffer.writeln(
            "      ${field.name}: ${castOp("json['${field.name}']")},",
          );
        }
        buffer.writeln("    );");
        buffer.writeln("  }");

        // toJson
        buffer.writeln();
        buffer.writeln("  Map<String, dynamic> toJson() {");
        buffer.writeln("    return {");
        for (final field in model.fields) {
          buffer.writeln("      '${field.name}': ${field.name},");
        }
        buffer.writeln("    };");
        buffer.writeln("  }");
      }

      buffer.writeln("}");
    }

    buffer.writeln();
  }

  String _mapTypeToDart(FieldType type) {
    switch (type.kind) {
      case TypeKind.string:
        return 'String';
      case TypeKind.integer:
        return 'int';
      case TypeKind.float:
        return 'double';
      case TypeKind.boolean:
        return 'bool';
      case TypeKind.dateTime:
        return 'DateTime';
      case TypeKind.array:
        final itemType = _mapTypeToDart(type.itemType!);
        return 'List<$itemType>';
      case TypeKind.map:
        return 'Map<String, dynamic>';
      case TypeKind.reference:
        return type.reference!;
      default:
        return 'dynamic';
    }
  }

  String Function(String) _getCastOperation(FieldType type, bool isNullable) {
    switch (type.kind) {
      case TypeKind.string:
        return (source) =>
            isNullable ? "$source as String?" : "$source as String";
      case TypeKind.integer:
        return (source) => isNullable ? "$source as int?" : "$source as int";
      case TypeKind.float:
        return (source) =>
            isNullable ? "$source as double?" : "$source as double";
      case TypeKind.boolean:
        return (source) => isNullable ? "$source as bool?" : "$source as bool";
      case TypeKind.dateTime:
        return (source) =>
            isNullable
                ? "$source != null ? DateTime.parse($source as String) : null"
                : "DateTime.parse($source as String)";
      case TypeKind.array:
        final itemCast = _getCastOperation(type.itemType!, false);
        return (source) =>
            isNullable
                ? "$source != null ? ($source as List).map((e) => ${itemCast('e')}).toList() : null"
                : "($source as List).map((e) => ${itemCast('e')}).toList()";
      case TypeKind.reference:
        final ref = type.reference!;
        return (source) =>
            isNullable
                ? "$source != null ? $ref.fromJson($source as Map<String, dynamic>) : null"
                : "$ref.fromJson($source as Map<String, dynamic>)";
      default:
        return (source) => source;
    }
  }
}
