import 'package:flutter_test/flutter_test.dart';
import 'package:promet/services/place_search_service.dart';

void main() {
  test('parsePhoton reads names, kinds and drops duplicates', () {
    const body = '''
{"features":[
 {"geometry":{"coordinates":[14.5,46.05]},"properties":{"name":"Ljubljana","osm_key":"boundary","osm_value":"administrative","type":"city"}},
 {"geometry":{"coordinates":[14.506,46.051]},"properties":{"name":"Ljubljana","osm_key":"place","osm_value":"city","type":"city"}},
 {"geometry":{"coordinates":[14.506,46.051]},"properties":{"name":"Ljubljana","osm_key":"place","osm_value":"city","type":"city"}},
 {"geometry":{"coordinates":[13.73,45.54]},"properties":{"street":"Šmarska cesta","housenumber":"4","city":"Koper","osm_key":"building","type":"house"}},
 {"geometry":{},"properties":{"name":"broken"}}
]}''';
    final hits = parsePhoton(body);
    expect(hits.map((h) => h.subtitle), ['občina', 'mesto', 'Koper, naslov']);
    expect(hits.last.place.name, 'Šmarska cesta 4');
    expect(parsePhoton('nope'), isEmpty);
  });
}
