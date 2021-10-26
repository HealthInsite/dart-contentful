import 'package:dartz/dartz.dart';
import 'package:contentful/lib/conversion.dart' as convert;
import 'package:contentful/lib/entry.dart' as entry_utils;

bool _isListOfLinks(dynamic list) {
  if (list is! List) {
    return false;
  } else if (list.isEmpty) {
    return false;
  }

  if (!(list.first is Map)) {
    return false;
  }

  return entry_utils.isLink(list.first);
}

class Includes {
  static Includes fromJson(Map<String, dynamic> json) =>
      Includes._(_IncludesMap.fromJson(json));

  Includes._(this.map);
  final _IncludesMap map;

  /// Keep track of processed entry id to prevent infinite recursive loop.
  Map<String, int> _processedIds = {};
  int _maxDiscoveredCount = 1;

  List<Map<String, dynamic>> resolveLinks(
    List<dynamic> items, {
    bool initial = false,
  }) {
    if (initial) {
      _maxDiscoveredCount = items.length;
    }
    return items.map(convert.map).map(_walkMap).toList();
  }

  /// Walk the branch and look at each fields if there is
  /// a field that contains a link to other entry
  /// then continue on that branch of entry.
  Map<String, dynamic> _walkMap(Map<String, dynamic> entry) {
    final id = entry_utils.id(entry).fold(() => '', (id) => id);
    // print('WalkMap: $id');
    return entry_utils.isLink(entry)
        ? map.resolveLink(entry).fold(() => entry, _walkMap)
        : entry_utils.fields(entry).fold(
              () => entry,
              (fields) => {
                ...entry,
                'fields': fields.map(
                  (String key, dynamic object) =>
                      _resolveEntryField(key, object, id),
                ),
              },
            );
  }

  /// Look through each field in `fields`.
  ///
  /// `key` is `ContentType` of the entry.
  MapEntry<String, dynamic> _resolveEntryField(
    String key,
    dynamic object,
    String entryId,
  ) {
    // print(' Resolve: $entryId: $key');

    /// max discoveredTime allowed = items.length
    final discoveredTimes = _processedIds[entryId] ?? 0;
    if (_isListOfLinks(object) && discoveredTimes < _maxDiscoveredCount) {
      _processedIds.update(entryId, (value) => value + 1, ifAbsent: () => 1);
      // print('_processedIds: ${_processedIds.length}');
      // 1. links to entries
      return MapEntry(key, resolveLinks(object));
    } else if (object is! Map) {
      // 2. value
      return MapEntry(key, object);
    }

    // 3. map of values or a link
    final fieldMap = some(convert.map(object));
    final resolveLink = () =>
        fieldMap.filter(entry_utils.isLink).bind(map.resolveLink).map(_walkMap);
    final resolveRichText =
        () => fieldMap.filter(entry_utils.isRichText).map(_walkRichText);

    return resolveLink().orElse(resolveRichText).fold(
          () => MapEntry(key, object),
          (field) => MapEntry(key, field),
        );
  }

  Map<String, dynamic> _walkRichText(Map<String, dynamic> doc) {
    final root = {
      ...doc,
      'data': entry_utils.dataTarget(doc).bind(map.resolveLink).fold(
            () => doc['data'],
            (entry) => {
              ...doc['data'],
              'target': entry,
            },
          ),
    };

    return entry_utils
        .contentList(doc)
        .map((nodes) => nodes.map(_walkRichText))
        .fold(
          () => root,
          (nodes) => {
            ...root,
            'content': nodes.toList(),
          },
        );
  }
}

Map<String, Map<String, dynamic>> _addEntriesToMap(
        Map<String, Map<String, dynamic>> map,
        List<Map<String, dynamic>> entries) =>
    entries.fold(
      map,
      (map, entry) => entry_utils.id(entry).fold(
        () => map,
        (id) {
          map[id] = entry;
          return map;
        },
      ),
    );

class _IncludesMap {
  factory _IncludesMap.fromJson(Map<String, dynamic> includes) =>
      _IncludesMap._(
        includes.values.map(convert.listOfMaps).fold({}, _addEntriesToMap),
      );

  _IncludesMap._(this._map);

  final Map<String, Map<String, dynamic>> _map;

  Option<Map<String, dynamic>> resolveLink(Map<String, dynamic> link) =>
      entry_utils.id(link).bind((id) => optionOf(_map[id]));
}
