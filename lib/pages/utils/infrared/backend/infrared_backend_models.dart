class CategoryManifest {
  CategoryManifest({required this.displayName, required this.singularDisplayName});
  final String displayName;
  final String singularDisplayName;

  factory CategoryManifest.fromJson(Map<String, dynamic> j) => CategoryManifest(
        displayName: '${j['display_name'] ?? ''}',
        singularDisplayName: '${j['singular_display_name'] ?? ''}',
      );
}

class CategoryMeta {
  CategoryMeta({
    required this.iconPngBase64,
    required this.iconSvgBase64,
    required this.manifest,
  });

  final String iconPngBase64;
  final String iconSvgBase64;
  final CategoryManifest manifest;

  factory CategoryMeta.fromJson(Map<String, dynamic> j) => CategoryMeta(
        iconPngBase64: '${j['icn_png_base64'] ?? ''}',
        iconSvgBase64: '${j['icn_svg_base64'] ?? ''}',
        manifest: CategoryManifest.fromJson(
          (j['manifest_content'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
      );
}

class DeviceCategory {
  DeviceCategory({required this.id, required this.meta, required this.folderName});
  final int id;
  final CategoryMeta meta;
  final String folderName;

  String get displayName => meta.manifest.displayName;

  factory DeviceCategory.fromJson(Map<String, dynamic> j) => DeviceCategory(
        id: (j['id'] as num?)?.toInt() ?? 0,
        meta: CategoryMeta.fromJson(
          (j['meta'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        folderName: '${j['folder_name'] ?? ''}',
      );
}

class BrandModel {
  BrandModel({required this.id, required this.name, required this.categoryId});
  final int id;
  final String name;
  final int categoryId;

  factory BrandModel.fromJson(Map<String, dynamic> j) => BrandModel(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: '${j['name'] ?? ''}',
        categoryId: (j['category_id'] as num?)?.toInt() ?? 0,
      );
}

class IfrFileModel {
  IfrFileModel({
    required this.id,
    required this.brandId,
    required this.fileName,
    required this.folderName,
  });
  final int id;
  final int brandId;
  final String fileName;
  final String folderName;

  factory IfrFileModel.fromJson(Map<String, dynamic> j) => IfrFileModel(
        id: (j['id'] as num?)?.toInt() ?? 0,
        brandId: (j['brand_id'] as num?)?.toInt() ?? 0,
        fileName: '${j['file_name'] ?? ''}',
        folderName: '${j['folder_name'] ?? ''}',
      );
}
