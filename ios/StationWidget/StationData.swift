import Foundation
import ImageIO
import UIKit

/// One weather station reading from the ceste.si feed
/// (`/Vremenske/Vreme/KamereInVreme`), the same source the app uses.
struct StationReading: Codable, Equatable {
    let stationId: Int
    let name: String
    let cameraLink: String
    let timestamp: Date?
    let temp: Double?
    let minTemp: Double?
    let maxTemp: Double?
    let humidity: Int?
    let windDir: String?
    let wind: Double?
    let gust: Double?
    let rain: Double?
    let dew: Double?
    let pressure: Int?
}

/// A station's latest reading plus a downscaled camera frame.
struct StationSnapshot: Codable {
    let reading: StationReading
    let image: Data?
    let fetchedAt: Date
}

enum StationFeed {
    static let endpoint = URL(string: "https://www.ceste.si/Vremenske/Vreme/KamereInVreme")!
    static let proxyHost = "prometnik-cams.dz0ny.workers.dev"
    static let proxiedHosts: Set<String> = ["kamere.dars.si", "www.drsc.si", "drsc.si", "meteo.arso.gov.si"]

    /// The feed's local times carry no zone: they are Slovenian time.
    private static let timeParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Ljubljana")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    private static var cachedList: (at: Date, stations: [StationReading])?

    /// All stations that report weather, sorted by name.
    static func stations() async throws -> [StationReading] {
        if let c = cachedList, Date().timeIntervalSince(c.at) < 300 { return c.stations }
        var req = URLRequest(url: endpoint, timeoutInterval: 20)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("promet-ios-widget/1.0 (+https://www.ceste.si/Vreme/)", forHTTPHeaderField: "User-Agent")
        let (data, res) = try await URLSession.shared.data(for: req)
        guard (res as? HTTPURLResponse)?.statusCode == 200,
              let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { throw URLError(.badServerResponse) }
        let out = list.compactMap(parse).sorted {
            $0.name.compare($1.name, locale: Locale(identifier: "sl_SI")) == .orderedAscending
        }
        cachedList = (Date(), out)
        return out
    }

    private static func parse(_ j: [String: Any]) -> StationReading? {
        guard let id = (j["stationId"] as? NSNumber)?.intValue,
              let w = j["weather"] as? [String: Any] else { return nil }
        func d(_ k: String) -> Double? { (w[k] as? NSNumber)?.doubleValue }
        let name = ((j["name"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        let dir = (w["windDirection"] as? String)?.trimmingCharacters(in: .whitespaces)
        // The feed sends 0 % humidity when the sensor has no value.
        let hum = (w["humidityPercentage"] as? NSNumber)?.intValue
        return StationReading(
            stationId: id,
            name: name.isEmpty ? "Postaja" : name,
            // Some stations list several cameras joined with ";": the first.
            cameraLink: ((j["cameraLink"] as? String) ?? "").split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? "",
            timestamp: (w["timestamp"] as? String).flatMap { timeParser.date(from: $0) },
            temp: d("outdoorTemperatureC"),
            minTemp: d("minOutdoorTemperatureC"),
            maxTemp: d("maxOutdoorTemperatureC"),
            humidity: hum == 0 ? nil : hum,
            windDir: dir?.isEmpty == true ? nil : dir,
            wind: d("windSpeedKmh"),
            gust: d("windGustKmh"),
            rain: d("dailyRainMm"),
            dew: d("dewPointC"),
            pressure: (w["pressureHpa"] as? NSNumber)?.intValue
        )
    }

    /// The camera URL through the app's edge cache (https, cached a minute).
    static func cameraURL(_ link: String) -> URL? {
        guard !link.isEmpty, var c = URLComponents(string: link) else { return nil }
        guard let host = c.host?.lowercased(), proxiedHosts.contains(host) else {
            return URL(string: link)
        }
        c.queryItems = c.queryItems?.filter { $0.name != "t" }
        if c.queryItems?.isEmpty == true { c.queryItems = nil }
        var p = URLComponents()
        p.scheme = "https"
        p.host = proxyHost
        p.path = "/cam"
        let bucket = Int(Date().timeIntervalSince1970 / 300) * 300
        p.queryItems = [URLQueryItem(name: "u", value: c.string), URLQueryItem(name: "t", value: "\(bucket)")]
        return p.url
    }

    /// The camera frame downscaled to [maxPixel] (widgets have tight memory).
    static func cameraImage(_ link: String, maxPixel: Int = 800) async -> Data? {
        guard let url = cameraURL(link) else { return nil }
        do {
            let (data, res) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15))
            guard (res as? HTTPURLResponse)?.statusCode == 200,
                  let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            return UIImage(cgImage: cg).jpegData(compressionQuality: 0.8)
        } catch {
            return nil
        }
    }

    /// Fresh snapshot for [id]; on failure the last good one (kept on disk).
    static func snapshot(for id: Int, withImage: Bool) async -> StationSnapshot? {
        do {
            guard let r = try await stations().first(where: { $0.stationId == id }) else {
                return loadCached(id)
            }
            var image: Data? = nil
            if withImage {
                image = await cameraImage(r.cameraLink) ?? loadCached(id)?.image
            }
            let snap = StationSnapshot(reading: r, image: image, fetchedAt: Date())
            save(snap)
            return snap
        } catch {
            return loadCached(id)
        }
    }

    private static func cacheURL(_ id: Int) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("station-\(id).json")
    }

    private static func save(_ s: StationSnapshot) {
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: cacheURL(s.reading.stationId), options: .atomic)
        }
    }

    static func loadCached(_ id: Int) -> StationSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL(id)) else { return nil }
        return try? JSONDecoder().decode(StationSnapshot.self, from: data)
    }
}

/// The app's formatting rules (WeatherFormat in lib/widgets/weather_details.dart).
enum Fmt {
    static func decimal(_ v: Double, _ digits: Int = 1) -> String {
        var s = String(format: "%.\(digits)f", v)
        if Double(s) == 0 { s = String(format: "%.\(digits)f", 0.0) }
        return s.replacingOccurrences(of: ".", with: ",")
    }

    static func temp(_ c: Double?) -> String { c.map { "\(decimal($0)) °C" } ?? "–" }
    static func degrees(_ c: Double?) -> String { c.map { "\(decimal($0))°" } ?? "–" }

    /// The big number, one decimal like the app: "-0,5°". Around zero the
    /// decimal is what tells frost from thaw.
    static func bigTemp(_ c: Double?) -> String { degrees(c) }

    static func compass(_ dir: String?) -> String {
        guard let d = dir?.uppercased(), !d.isEmpty else { return "" }
        let map: [Character: Character] = ["N": "S", "E": "V", "S": "J", "W": "Z"]
        return String(d.map { map[$0] ?? $0 })
    }

    static func wind(_ r: StationReading) -> String {
        guard let w = r.wind else { return "–" }
        // No direction for calm air.
        let dir = w < 1 ? "" : compass(r.windDir)
        return "\(Int(w.rounded())) km/h" + (dir.isEmpty ? "" : " \(dir)")
    }

    static func gust(_ r: StationReading) -> String? {
        r.gust.map { "sunki \(Int($0.rounded()))" }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sl_SI")
        f.timeZone = TimeZone(identifier: "Europe/Ljubljana")
        f.dateFormat = "HH:mm"
        return f
    }()

    static func time(_ d: Date?) -> String { d.map { timeFormatter.string(from: $0) } ?? "–" }
}
