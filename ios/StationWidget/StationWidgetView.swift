import SwiftUI
import WidgetKit

/// One reading row ("Veter", "9 km/h VSV").
struct Metric: Identifiable {
    let id: String
    let icon: String
    let label: String
    let value: String
}

/// The enabled readings in a fixed priority order; when space runs out the
/// later ones are dropped. Same order as the Android widget.
func metrics(_ r: StationReading, _ c: StationWidgetIntent, compact: Bool = false) -> [Metric] {
    var out: [Metric] = []
    if c.showWind, r.wind != nil {
        let gust = compact ? nil : Fmt.gust(r)
        out.append(Metric(id: "wind", icon: "wind", label: "Veter",
                          value: Fmt.wind(r) + (gust.map { " · \($0)" } ?? "")))
    }
    if c.showRain, let rain = r.rain {
        out.append(Metric(id: "rain", icon: "cloud.rain", label: "Padavine", value: "\(Fmt.decimal(rain)) mm"))
    }
    if c.showMinMax, r.minTemp != nil || r.maxTemp != nil {
        out.append(Metric(id: "minmax", icon: "thermometer.medium", label: "Min / maks",
                          value: "\(Fmt.degrees(r.minTemp)) / \(Fmt.degrees(r.maxTemp))"))
    }
    if c.showHumidity, let h = r.humidity {
        out.append(Metric(id: "hum", icon: "humidity", label: "Vlaga", value: "\(h) %"))
    }
    if c.showDew, let d = r.dew {
        out.append(Metric(id: "dew", icon: "drop", label: "Rosišče", value: Fmt.temp(d)))
    }
    if c.showPressure, let p = r.pressure, p > 0 {
        out.append(Metric(id: "press", icon: "gauge.with.dots.needle.33percent", label: "Tlak", value: "\(p) hPa"))
    }
    return out
}

/// The app's temperature scale (AppTheme.temperatureColor).
func temperatureColor(_ c: Double?) -> Color {
    guard let c else { return Color(hex: 0x6B7B8C) }
    switch c {
    case ...(-10): return Color(hex: 0x4A148C)
    case ...0: return Color(hex: 0x1E88E5)
    case ...5: return Color(hex: 0x26C6DA)
    case ...12: return Color(hex: 0x66BB6A)
    case ...20: return Color(hex: 0xD4E157)
    case ...27: return Color(hex: 0xFFB300)
    case ...33: return Color(hex: 0xFB8C00)
    default: return Color(hex: 0xE53935)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
    /// The app's night-road navy.
    static let night = Color(hex: 0x0E1726)
}

struct StationWidgetView: View {
    let entry: StationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content.containerBackground(for: .widget) { background }
    }

    @ViewBuilder private var content: some View {
        if entry.unconfigured {
            UnconfiguredView(family: family)
        } else if let s = entry.snapshot {
            switch family {
            case .accessoryInline:
                Text("\(s.reading.name) \(Fmt.temp(s.reading.temp))")
            case .accessoryCircular:
                CircularView(r: s.reading)
            case .accessoryRectangular:
                RectangularView(r: s.reading, config: entry.config)
            case .systemMedium:
                MediumView(s: s, config: entry.config)
            case .systemLarge:
                LargeView(s: s, config: entry.config)
            default:
                SmallView(s: s, config: entry.config)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "wifi.exclamationmark")
                Text("Podatki niso na voljo").font(.caption.bold())
            }
            .foregroundStyle(.white)
            .padding()
        }
    }

    @ViewBuilder private var background: some View {
        if family.isAccessory {
            Color.clear
        } else if let s = entry.snapshot, entry.config.showCamera,
                  let data = s.image, let ui = UIImage(data: data) {
            // Large keeps the photo in its top half (see LargeView).
            if family == .systemLarge {
                Color.night
            } else {
                Image(uiImage: ui).resizable().scaledToFill()
                    .overlay(scrim)
            }
        } else {
            LinearGradient(
                colors: [temperatureColor(entry.snapshot?.reading.temp).opacity(0.85), .night],
                startPoint: .topTrailing, endPoint: .bottomLeading)
        }
    }

    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.15), location: 0),
                .init(color: .black.opacity(0.05), location: 0.35),
                .init(color: .black.opacity(0.72), location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
    }
}

/// White text with a soft shadow, readable over any photo.
private extension View {
    func onPhoto() -> some View {
        foregroundStyle(.white).shadow(color: .black.opacity(0.45), radius: 3, y: 1)
    }
}

private struct TempDot: View {
    let temp: Double?
    var size: CGFloat = 9
    var body: some View {
        Circle().fill(temperatureColor(temp))
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
            .frame(width: size, height: size)
    }
}

private struct BigTemp: View {
    let temp: Double?
    let size: CGFloat
    var body: some View {
        Text(Fmt.bigTemp(temp))
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .contentTransition(.numericText())
    }
}

private struct UpdatedLabel: View {
    let date: Date?
    var body: some View {
        Text("ob \(Fmt.time(date))").font(.caption2.weight(.semibold)).opacity(0.85)
    }
}

private struct MetricLine: View {
    let m: Metric
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: m.icon).font(.caption2.weight(.bold)).frame(width: 14)
            Text(m.value).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

private struct SmallView: View {
    let s: StationSnapshot
    let config: StationWidgetIntent
    var body: some View {
        let r = s.reading
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 5) {
                TempDot(temp: r.temp).padding(.top, 3)
                Text(r.name).font(.subheadline.weight(.bold)).lineLimit(2)
            }
            Spacer(minLength: 0)
            BigTemp(temp: r.temp, size: 42)
            ForEach(Array(metrics(r, config, compact: true).prefix(2))) { MetricLine(m: $0) }
            UpdatedLabel(date: r.timestamp)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .onPhoto()
    }
}

private struct MediumView: View {
    let s: StationSnapshot
    let config: StationWidgetIntent
    var body: some View {
        let r = s.reading
        let list = Array(metrics(r, config, compact: true).prefix(4))
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: 5) {
                    TempDot(temp: r.temp).padding(.top, 4)
                    Text(r.name).font(.headline.weight(.bold)).lineLimit(2)
                }
                Spacer(minLength: 0)
                BigTemp(temp: r.temp, size: 52)
                UpdatedLabel(date: r.timestamp)
            }
            Spacer(minLength: 0)
            if !list.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(list) { MetricLine(m: $0) }
                }
                .padding(.vertical, 8).padding(.horizontal, 10)
                .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
        .onPhoto()
    }
}

private struct LargeView: View {
    let s: StationSnapshot
    let config: StationWidgetIntent
    var body: some View {
        let r = s.reading
        let list = Array(metrics(r, config).prefix(6))
        let image = config.showCamera ? s.image.flatMap(UIImage.init(data:)) : nil
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                if let image {
                    Color.clear.overlay(Image(uiImage: image).resizable().scaledToFill()).clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                } else {
                    LinearGradient(colors: [temperatureColor(r.temp).opacity(0.85), .night],
                                   startPoint: .topTrailing, endPoint: .bottomLeading)
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            TempDot(temp: r.temp, size: 10)
                            Text(r.name).font(.title3.weight(.bold)).lineLimit(1)
                        }
                        UpdatedLabel(date: r.timestamp)
                    }
                    Spacer()
                    BigTemp(temp: r.temp, size: 56)
                }
                .padding(.horizontal, 16).padding(.bottom, 10)
                .onPhoto()
            }
            .frame(maxHeight: list.isEmpty ? .infinity : 190)

            if !list.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                    ForEach(list) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(m.label, systemImage: m.icon)
                                .font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.65))
                            Text(m.value).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(12)
                Spacer(minLength: 0)
                Text("Vir: ceste.si · DARS")
                    .font(.caption2).foregroundStyle(.white.opacity(0.45))
                    .padding(.bottom, 10)
            }
        }
    }
}

private struct RectangularView: View {
    let r: StationReading
    let config: StationWidgetIntent
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(r.name).font(.headline).lineLimit(1).widgetAccentable()
            Text(Fmt.temp(r.temp)).font(.system(.title2, design: .rounded).weight(.bold))
            if let m = metrics(r, config, compact: true).first {
                Label(m.value, systemImage: m.icon).font(.caption).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CircularView: View {
    let r: StationReading
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -2) {
                Image(systemName: "thermometer.medium").font(.caption2)
                Text(Fmt.bigTemp(r.temp)).font(.system(.title3, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.6)
            }
        }
    }
}

private struct UnconfiguredView: View {
    let family: WidgetFamily
    var body: some View {
        if family.isAccessory {
            Text("Izberite postajo").font(.caption)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "thermometer.medium").font(.title2)
                Text("Izberite postajo").font(.headline)
                Text("Pridržite gradnik in izberite Uredi gradnik.")
                    .font(.caption).opacity(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(16)
        }
    }
}
