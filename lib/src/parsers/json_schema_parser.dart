import 'dart:convert';

import '../models/schema_model.dart';
import 'package:recase/recase.dart';

/// Parser to convert JSON Schema into internal models
class JsonSchemaParser {
  Future<Schema> parse(dynamic jsonData) async {
    final models = <Model>[];

    // Verificar se estamos lidando com um objeto raiz que contém vários modelos
    if (jsonData is Map<String, dynamic>) {
      // Verify if the JSON contains conditional schemas
      if (jsonData.containsKey('if') &&
          jsonData.containsKey('then') &&
          jsonData.containsKey('else')) {
        final thenPrefixRaw = jsonData['if']['properties'].keys.first;
        final thenPrefix =
            ReCase(
              thenPrefixRaw.substring(2, thenPrefixRaw.length),
            ).pascalCase; // trim the prefix to remove "is" and convert to PascalCase for multi-word names
        final elsePrefix = 'Default';

        // Extract the base class name and names for 'then' and 'else' cases
        final baseClassName = jsonData['title'] ?? 'BaseClass';
        final thenClassName = thenPrefix + baseClassName;
        final elseClassName = elsePrefix + baseClassName;

        final String switchKey = jsonData['if']['properties'].keys.first;
        final bool switchKeyValueForThen =
            jsonData['if']['properties'][switchKey]['const'] as bool;

        final Map<String, String> switchCases = {
          switchKeyValueForThen.toString(): thenClassName,
          (!switchKeyValueForThen).toString(): elseClassName,
        };

        // Need to handle the case where the JSON is a conditional schema
        // Base class
        // TODO: Need to handle removing the properties from the base class for the 'then' and 'else' cases
        // This is determined by the first "required" array in the schema
        // 'then' and 'else' then define additional "required" arrays, which need to be added to those child classes
        if (jsonData.containsKey('properties') &&
            jsonData.containsKey('title')) {
          if (jsonData.containsKey('required')) {
            // TODO: Handle required properties and removing 'then' and 'else' properties
            // copy the jsonData to a new variable to avoid modifying the original
            Map<String, dynamic> baseClassJsonData = Map<String, dynamic>.from(
              jsonData,
            );
            Map<String, dynamic> thenClassJsonData = {};
            thenClassJsonData['properties'] = <String, dynamic>{};
            thenClassJsonData['required'] = <String>[];

            Map<String, dynamic> elseClassJsonData = {};
            elseClassJsonData['properties'] = <String, dynamic>{};
            elseClassJsonData['required'] = <String>[];

            // Remove 'then' and 'else' properties from the base class
            // Look at the "then" and "else" properties to determine which properties to remove

            if (jsonData.containsKey('then')) {
              // Get the required properties from the 'then' case
              final thenRequired =
                  (jsonData['then']['required'] as List?) ?? [];
              // Remove the properties that are required in the 'then' case
              if (thenRequired is List<String>) {
                for (final prop in baseClassJsonData['properties'].keys) {
                  if (thenRequired.contains(prop)) {
                    // Move the property to the 'then' class
                    thenClassJsonData['properties'][prop] =
                        baseClassJsonData['properties'][prop];
                    // Add the property to the 'then' class required list
                    // thenClassJsonData['required'] ??= [];
                    thenClassJsonData['required'].add(prop);
                    // Remove the property from the base class
                    baseClassJsonData['properties'].remove(prop);
                  }
                }
              }
            }

            if (jsonData.containsKey('else')) {
              // Get the required properties from the 'else' case
              final elseRequired =
                  (jsonData['else']['required'] as List?) ?? [];
              // Remove the properties that are required in the 'else' case
              if (elseRequired is List<String>) {
                for (final prop in baseClassJsonData['properties'].keys) {
                  if (elseRequired.contains(prop)) {
                    // Move the property to the 'else' class
                    elseClassJsonData['properties'][prop] =
                        baseClassJsonData['properties'][prop];
                    // Add the property to the 'else' class required list
                    // elseClassJsonData['required'] ??= [];
                    elseClassJsonData['required'].add(prop);
                    // Remove the property from the base class
                    baseClassJsonData['properties'].remove(prop);
                  }
                }
              }
            }

            // need a new helper function to parse the model as an abstract class with polymorphic children
            // TODO: Create a new method to handle polymorphic models
            // Base class
            Model baseModel = _parseModel(baseClassName, baseClassJsonData);
            // baseModel.isAbstract = true; // Mark the base class as abstract
            baseModel.switchKey = switchKey;
            baseModel.switchCases = switchCases;
            models.add(baseModel);

            // Then class
            Model thenModel = _parseModel(thenClassName, thenClassJsonData);
            thenModel.parentClass = jsonData['title'];
            thenModel.isAbstract = false; // Mark the 'then' class as concrete
            models.add(thenModel);

            // Else class
            Model elseModel = _parseModel(elseClassName, elseClassJsonData);
            elseModel.parentClass = jsonData['title'];
            elseModel.isAbstract = false; // Mark the 'else' class as concrete
            models.add(elseModel);
          }

          // Then class
          // Want to create a 'base' class and then 2 child classes for 'then' and 'else'
          // The base class will have all the common properties in "properties"
          // The 'then' and 'else' classes will have the specific properties for each case

          // return Schema(models: models);
          return Schema(
            models: models,
            version: jsonData['\$schema'] as String?,
          );
          // return Schema(models: models, version: jsonData['\$schema'] as String?);
        }
      }

      // Iterar por cada entrada no objeto principal
      jsonData.forEach((modelName, modelData) {
        // Verificar se o modelo tem o formato esperado (com 'schema' e 'description')
        if (modelData is Map<String, dynamic> &&
            modelData.containsKey('schema')) {
          final schema = modelData['schema'] as Map<String, dynamic>;
          final description = modelData['description'] as String?;

          // Extrair propriedades do schema
          if (schema.containsKey('properties')) {
            final model = _parseModel(modelName, schema, description);
            models.add(model);
          }
        } else if (modelData is Map<String, dynamic> &&
            modelData.containsKey('properties')) {
          // Formato alternativo onde o schema está diretamente no objeto
          final model = _parseModel(modelName, modelData);
          models.add(model);
        } else if (modelData is Map<String, dynamic> &&
            modelData.containsKey('definitions')) {
          // Formato com 'definitions'
          final definitions = modelData['definitions'] as Map<String, dynamic>;
          definitions.forEach((defName, defValue) {
            models.add(_parseModel('${modelName}_$defName', defValue));
          });
        }
      });
    }

    // Se não encontrou modelos, tente como um único schema
    if (models.isEmpty &&
        jsonData is Map<String, dynamic> &&
        jsonData.containsKey('properties')) {
      if (jsonData.containsKey('title')) {
        models.add(_parseModel(jsonData['title'], jsonData));
      } else {
        models.add(_parseModel('Root', jsonData));
      }
    }

    return Schema(models: models, version: jsonData['\$schema'] as String?);
  }

  Model _parseModel(String name, dynamic modelData, [String? description]) {
    final fields = <Field>[];

    if (modelData.containsKey('properties')) {
      final properties = modelData['properties'] as Map<String, dynamic>;
      final required =
          modelData['required'] is List
              ? (modelData['required'] as List).cast<String>()
              : <String>[];

      // Verificar se existe uma ordenação de propriedades
      List<String>? propertyOrder;
      if (modelData.containsKey('propertyOrder') &&
          modelData['propertyOrder'] is List) {
        propertyOrder = (modelData['propertyOrder'] as List).cast<String>();
      }

      // Lista de propriedades ordenadas, se possível
      final orderedProps =
          propertyOrder != null ? [...propertyOrder] : properties.keys.toList();

      // Adicionar propriedades que não estão na ordem, mas existem
      for (final key in properties.keys) {
        if (!orderedProps.contains(key)) {
          orderedProps.add(key);
        }
      }

      // Processar as propriedades na ordem correta
      for (final propName in orderedProps) {
        if (properties.containsKey(propName)) {
          fields.add(
            _parseField(
              propName,
              properties[propName],
              isNullable: !required.contains(propName),
            ),
          );
        }
      }
    }

    return Model(
      name: _formatClassName(name),
      fields: fields,
      description: description ?? modelData['description'] as String?,
    );
  }

  Field _parseField(String name, dynamic fieldData, {bool isNullable = false}) {
    return Field(
      name: name,
      type: _parseFieldType(fieldData),
      isNullable: isNullable,
      description: fieldData['description'] as String?,
    );
  }

  FieldType _parseFieldType(dynamic typeData) {
    if (typeData.containsKey('\$ref')) {
      final ref = typeData['\$ref'] as String;
      final refName = ref.split('/').last;
      return FieldType(
        kind: TypeKind.reference,
        reference: _formatClassName(refName),
      );
    }

    final type = typeData['type'];

    switch (type) {
      case 'string':
        if (typeData['format'] == 'date-time') {
          return FieldType(kind: TypeKind.dateTime);
        }
        return FieldType(kind: TypeKind.string);
      case 'integer':
        return FieldType(kind: TypeKind.integer);
      case 'number':
        return FieldType(kind: TypeKind.float);
      case 'boolean':
        return FieldType(kind: TypeKind.boolean);
      case 'array':
        return FieldType(
          kind: TypeKind.array,
          itemType: _parseFieldType(typeData['items']),
        );
      case 'object':
        return FieldType(kind: TypeKind.map);
      default:
        return FieldType(kind: TypeKind.unknown);
    }
  }

  String _formatClassName(String name) {
    // Usar recase para formatação consistente
    ReCase rc = ReCase(name);
    String className = rc.pascalCase;

    // Substituir Params por AdapterParams
    if (className.endsWith('Params')) {
      className =
          '${className.substring(0, className.length - 'Params'.length)}AdapterParams';
    }

    return className;
  }
}
