import 'dart:convert';

class Event {
  String timestamp;
  int dbVersion;
  String type;
  String id;
  String key;
  String? value;

  Event(
    this.timestamp,
    this.dbVersion,
    this.type,
    this.id,
    this.key,
    this.value,
  );

  Event.fromMap(Map<String, dynamic> map)
      : timestamp = map['timestamp'],
        dbVersion = map['db_version'],
        type = map['type'],
        id = map['id'],
        key = map['key'],
        value = map['value'];

  Map toJson() => {
        'timestamp': timestamp,
        'db_version': dbVersion,
        'type': type,
        'id': id,
        'key': key,
        'value': value,
      };

  static List<Event> fromMaps(List<Map<String, dynamic>> maps) {
    return List.generate(maps.length, (item) {
      return Event.fromMap(maps[item]);
    });
  }

  static List<Event> deserialize(String data) {
    List<Event> events = [];

    for (final item in jsonDecode(data)) {
      events.add(Event.fromMap(item));
    }

    return events;
  }
}
