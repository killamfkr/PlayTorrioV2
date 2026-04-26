class IptvCategory {
  final String categoryId;
  final String categoryName;
  final int? parentId;

  const IptvCategory({
    required this.categoryId,
    required this.categoryName,
    this.parentId,
  });

  factory IptvCategory.fromJson(Map<String, dynamic> json) {
    return IptvCategory(
      categoryId: json['category_id']?.toString() ?? '0',
      categoryName: json['category_name']?.toString() ?? 'Unknown',
      parentId: int.tryParse(json['parent_id']?.toString() ?? ''),
    );
  }
}
