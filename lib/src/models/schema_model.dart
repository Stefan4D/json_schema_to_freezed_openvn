/// Represents a complete schema with multiple models
class Schema {
  final List<Model> models;
  final String? version;
  final Map<String, dynamic>? metadata;

  Schema({required this.models, this.version, this.metadata});
}

/// Represents a model or entity in the schema
class Model {
  String name; // Changed from final to allow modification
  final List<Field> fields;
  final String? description;
  final bool isEnum;
  // String? parentClass; // Optional parent class for inheritance
  bool isAbstract;
  String? unionKey; // Optional union key for polymorphic models
  List<UnionVariant>?
  unionVariants; // Optional union variants for polymorphic models
  // Map<String, String>?
  // switchCases; // Optional switch cases for polymorphic models
  // bool isParentClass; // Flag to indicate if this is a parent class

  Model({
    required this.name,
    required this.fields,
    this.description,
    this.isEnum = false,
    // this.parentClass,
    this.isAbstract = true,
    this.unionKey,
    // this.switchCases,
    // this.isParentClass = false,
  });
}

/// Represents a field in a model
class Field {
  final String name;
  final FieldType type;
  final bool isNullable;
  final String? description;
  final bool isId;
  final bool isUnique;
  final Map<String, dynamic>? attributes;

  Field({
    required this.name,
    required this.type,
    this.isNullable = false,
    this.description,
    this.isId = false,
    this.isUnique = false,
    this.attributes,
  });
}

/// Type of a field
class FieldType {
  final TypeKind kind;
  final FieldType? itemType; // For arrays
  final String? reference; // For references to other models

  FieldType({required this.kind, this.itemType, this.reference});
}

/// Enumeration of possible field types
enum TypeKind {
  string,
  integer,
  float,
  boolean,
  dateTime,
  array,
  map,
  reference,
  enum_,
  unknown,
}

class UnionVariant {
  final String? variantName;
  final bool unionValue;
  // List of fields for the variant include base class fields
  final List<Field> fields;
  final bool isDefaultVariant;

  UnionVariant({
    this.variantName,
    required this.unionValue,
    required this.fields,
    this.isDefaultVariant = false,
  });
}
