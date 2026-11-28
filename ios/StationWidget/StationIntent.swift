import AppIntents
import WidgetKit

/// A weather station the user can pick in the widget's settings.
struct StationEntity: AppEntity {
    let id: Int
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Postaja"
    static var defaultQuery = StationQuery()

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

/// Stations come from the same live feed as the readings; the list is
/// searchable by name.
struct StationQuery: EntityStringQuery {
    func entities(for identifiers: [Int]) async throws -> [StationEntity] {
        let all = (try? await StationFeed.stations()) ?? []
        return identifiers.compactMap { id in
            if let s = all.first(where: { $0.stationId == id }) {
                return StationEntity(id: id, name: s.name)
            }
            // Offline: keep the pick, named from the last reading.
            return StationFeed.loadCached(id).map { StationEntity(id: id, name: $0.reading.name) }
        }
    }

    func entities(matching string: String) async throws -> [StationEntity] {
        let q = string.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return try await StationFeed.stations()
            .filter {
                q.isEmpty || $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(q)
            }
            .map { StationEntity(id: $0.stationId, name: $0.name) }
    }

    func suggestedEntities() async throws -> [StationEntity] {
        try await StationFeed.stations().map { StationEntity(id: $0.stationId, name: $0.name) }
    }
}

/// Widget settings: the station and which readings to show. The same set
/// of switches as the Android widget.
struct StationWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Vremenska postaja"
    static var description = IntentDescription("Temperatura in vreme s postaje ob cesti.")

    @Parameter(title: "Postaja")
    var station: StationEntity?

    @Parameter(title: "Slika kamere", default: true)
    var showCamera: Bool

    @Parameter(title: "Veter", default: true)
    var showWind: Bool

    @Parameter(title: "Padavine danes", default: true)
    var showRain: Bool

    @Parameter(title: "Najnižja in najvišja", default: true)
    var showMinMax: Bool

    @Parameter(title: "Vlaga", default: false)
    var showHumidity: Bool

    @Parameter(title: "Rosišče", default: false)
    var showDew: Bool

    @Parameter(title: "Zračni tlak", default: false)
    var showPressure: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Postaja \(\.$station)") {
            \.$showCamera
            \.$showWind
            \.$showRain
            \.$showMinMax
            \.$showHumidity
            \.$showDew
            \.$showPressure
        }
    }
}
