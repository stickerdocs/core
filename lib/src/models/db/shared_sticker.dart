import 'package:stickerdocs_core/src/models/db/db_model.dart';

class SharedSticker extends DBModel {
  static const String tableName = 'shared_sticker';
  static const String stickerIdKey = 'sticker_id';
  static const String trustedUserIdKey = 'trusted_user_id';
  static const String sharedByMeKey = 'shared_by_me';
  static const String ignoreExternalEventsKey = 'ignore_external_events';

  String stickerId;
  String trustedUserId;
  bool sharedByMe;
  bool ignoreExternalEvents;

  // Shadow fields
  String? _stickerId;
  String? _trustedUserId;
  bool? _sharedByMe;
  bool? _ignoreExternalEvents;

  SharedSticker({
    required this.stickerId,
    required this.trustedUserId,
    required this.sharedByMe,
    required this.ignoreExternalEvents,
  }) {
    table = tableName;
    commit(isNew: true);
  }

  @override
  Map<String, dynamic> changeset() {
    var changes = <String, dynamic>{};

    if (isNew || stickerId != _stickerId) {
      changes[stickerIdKey] = stickerId;
    }

    if (isNew || trustedUserId != _trustedUserId) {
      changes[trustedUserIdKey] = trustedUserId;
    }

    if (isNew || sharedByMe != _sharedByMe) {
      changes[sharedByMeKey] = sharedByMe;
    }

    if (isNew || ignoreExternalEvents != _ignoreExternalEvents) {
      changes[ignoreExternalEventsKey] = ignoreExternalEvents;
    }

    populateCreatedAndUpdatedChanges(changes, updatable: false);
    return changes;
  }

  @override
  void commit({required bool isNew}) {
    _stickerId = stickerId;
    _trustedUserId = trustedUserId;
    _sharedByMe = sharedByMe;
    _ignoreExternalEvents = ignoreExternalEvents;
    baseCommit(isNew: isNew);
  }

  static SharedSticker fromMap(Map<String, dynamic> map) {
    final document = SharedSticker(
      stickerId: map[stickerIdKey],
      trustedUserId: map[trustedUserIdKey],
      sharedByMe: (map[sharedByMeKey] ?? 0) == 1,
      ignoreExternalEvents: (map[ignoreExternalEventsKey] ?? 0) == 1,
    );

    DBModel.mapBase(document, map);
    return document;
  }

  static List<SharedSticker> fromMaps(List<Map<String, dynamic>> maps) {
    return List.generate(maps.length, (i) {
      return SharedSticker.fromMap(maps[i]);
    });
  }
}
