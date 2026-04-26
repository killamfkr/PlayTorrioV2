class IptvChannel {
  final int num;
  final String name;
  final String streamType;
  final int streamId;
  final String? streamIcon;
  final String? epgChannelId;
  final String? added;
  final String categoryId;
  final String? categoryName; // Used for M3U parsed channels
  final String? customSid;
  final int tvArchive;
  final String? directSource;
  final int tvArchiveDuration;

  /// For M3U-parsed channels, we store the direct stream URL
  final String? streamUrl;

  const IptvChannel({
    this.num = 0,
    required this.name,
    this.streamType = 'live',
    this.streamId = 0,
    this.streamIcon,
    this.epgChannelId,
    this.added,
    this.categoryId = '0',
    this.categoryName,
    this.customSid,
    this.tvArchive = 0,
    this.directSource,
    this.tvArchiveDuration = 0,
    this.streamUrl,
  });

  /// Alias for stream icon
  String? get logoUrl => streamIcon;

  factory IptvChannel.fromJson(Map<String, dynamic> json) {
    return IptvChannel(
      num: int.tryParse(json['num']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? 'Unknown Channel',
      streamType: json['stream_type']?.toString() ?? 'live',
      streamId: int.tryParse(json['stream_id']?.toString() ?? '') ?? 0,
      streamIcon: json['stream_icon']?.toString(),
      epgChannelId: json['epg_channel_id']?.toString(),
      added: json['added']?.toString(),
      categoryId: json['category_id']?.toString() ?? '0',
      customSid: json['custom_sid']?.toString(),
      tvArchive: int.tryParse(json['tv_archive']?.toString() ?? '') ?? 0,
      directSource: json['direct_source']?.toString(),
      tvArchiveDuration: int.tryParse(json['tv_archive_duration']?.toString() ?? '') ?? 0,
    );
  }
}
