import SwiftUI
import WidgetKit

struct StationEntry: TimelineEntry {
    let date: Date
    let config: StationWidgetIntent
    let snapshot: StationSnapshot?
    /// The widget gallery's preview: sample data, no station needed.
    var preview = false
    /// No station picked yet.
    var unconfigured: Bool { config.station == nil && !preview }
}

struct StationProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StationEntry {
        StationEntry(date: Date(), config: StationWidgetIntent(), snapshot: .sample, preview: true)
    }

    func snapshot(for config: StationWidgetIntent, in context: Context) async -> StationEntry {
        if context.isPreview, config.station == nil {
            return StationEntry(date: Date(), config: config, snapshot: .sample, preview: true)
        }
        return await entry(for: config, in: context)
    }

    func timeline(for config: StationWidgetIntent, in context: Context) async -> Timeline<StationEntry> {
        let e = await entry(for: config, in: context)
        // The feed updates about every 10 minutes.
        return Timeline(entries: [e], policy: .after(Date().addingTimeInterval(15 * 60)))
    }

    private func entry(for config: StationWidgetIntent, in context: Context) async -> StationEntry {
        guard let id = config.station?.id else {
            return StationEntry(date: Date(), config: config, snapshot: nil)
        }
        // Lock screen widgets never show the photo.
        let wantsImage = config.showCamera && !context.family.isAccessory
        let snap = await StationFeed.snapshot(for: id, withImage: wantsImage)
        return StationEntry(date: Date(), config: config, snapshot: snap)
    }
}

extension WidgetFamily {
    var isAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: return true
        default: return false
        }
    }
}

extension StationSnapshot {
    static let sample = StationSnapshot(
        reading: StationReading(
            stationId: 0, name: "Iga vas", cameraLink: "", timestamp: Date(),
            temp: 1.1, minTemp: -2.4, maxTemp: 3.0, humidity: 86, windDir: "ENE",
            wind: 9, gust: 15, rain: 0, dew: -1.2, pressure: 1031),
        image: nil, fetchedAt: Date())
}

@main
struct StationWidgetBundle: WidgetBundle {
    var body: some Widget { StationWidget() }
}

struct StationWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "StationWidget", intent: StationWidgetIntent.self, provider: StationProvider()) {
            StationWidgetView(entry: $0)
        }
        .configurationDisplayName("Vremenska postaja")
        .description("Temperatura, veter in slika kamere s postaje, ki jo izberete.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryCircular, .accessoryInline,
        ])
        .contentMarginsDisabled()
    }
}
