import Foundation

/// Service for interacting with the Golf Course API (https://api.golfcourseapi.com)
class GolfCourseService {
    static let shared = GolfCourseService()

    private let baseURL = AppConfig.golfCourseAPIBaseURL
    private let apiKey = AppConfig.golfCourseAPIKey
    private let session = URLSession.shared
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private init() {}

    // MARK: - Search Courses

    /// Search for golf courses by name or club name.
    /// Returns an array of matching courses (most relevant first).
    func searchCourses(query: String) async throws -> [GolfCourseResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        var components = URLComponents(string: "\(baseURL)/v1/search")!
        components.queryItems = [URLQueryItem(name: "search_query", value: query)]

        guard let url = components.url else {
            throw GolfCourseAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GolfCourseAPIError.invalidResponse
        }

        let raw = String(data: data, encoding: .utf8) ?? "(non-utf8)"
        #if DEBUG
        NSLog("[GolfCourseService] SEARCH %d url=%@ raw=%@", http.statusCode, url.absoluteString, String(raw.prefix(800)))
        #endif

        switch http.statusCode {
        case 200:
            do {
                let result = try decoder.decode(GolfCourseSearchResponse.self, from: data)
                #if DEBUG
                NSLog("[GolfCourseService] SEARCH decoded %d courses; first id=%d name=%@",
                      result.courses.count,
                      result.courses.first?.id ?? -1,
                      result.courses.first?.displayName ?? "nil")
                #endif
                return result.courses
            } catch {
                #if DEBUG
                NSLog("[GolfCourseService] SEARCH decode error: %@", String(describing: error))
                #endif
                throw error
            }
        case 401:
            throw GolfCourseAPIError.unauthorized
        default:
            throw GolfCourseAPIError.httpError(http.statusCode)
        }
    }

    // MARK: - Get Course Details

    /// Fetch full course details by ID (includes tees with holes).
    func getCourseDetails(courseId: Int) async throws -> GolfCourseResult {
        let components = URLComponents(string: "\(baseURL)/v1/courses/\(courseId)")!
        guard let url = components.url else { throw GolfCourseAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GolfCourseAPIError.invalidResponse
        }

        let raw = String(data: data, encoding: .utf8) ?? "(non-utf8)"
        #if DEBUG
        NSLog("[GolfCourseService] DETAIL %d url=%@ raw=%@", http.statusCode, url.absoluteString, String(raw.prefix(800)))
        #endif

        switch http.statusCode {
        case 200:
            // The detail endpoint may return the course directly OR wrapped in {"course": {...}}.
            // Try direct decode first; if it gives us id=0 (all fields failed), try the wrapper.
            let course = try decodeCourseResult(from: data)
            #if DEBUG
            NSLog("[GolfCourseService] DETAIL decoded id=%d name=%@ tees=%d",
                  course.id, course.displayName, course.tees?.all.count ?? 0)
            #endif
            return course
        case 401:
            throw GolfCourseAPIError.unauthorized
        case 404:
            throw GolfCourseAPIError.notFound
        default:
            throw GolfCourseAPIError.httpError(http.statusCode)
        }
    }

    // MARK: - Helpers

    /// Try to decode a GolfCourseResult from data.
    /// Handles both flat `{ "id": ... }` and wrapped `{ "course": { "id": ... } }` responses.
    private func decodeCourseResult(from data: Data) throws -> GolfCourseResult {
        // Log top-level JSON keys so we know the exact structure
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            #if DEBUG
            NSLog("[GolfCourseService] DETAIL top-level keys: [%@]", Array(json.keys).joined(separator: ", "))
            #endif
        }

        // Attempt 1: direct flat object
        if let direct = try? decoder.decode(GolfCourseResult.self, from: data), direct.id != 0 {
            return direct
        }

        // Attempt 2: wrapped in a "course" key
        if let wrapped = try? decoder.decode(WrappedCourseResponse.self, from: data),
           let course = wrapped.course, course.id != 0 {
            #if DEBUG
            NSLog("[GolfCourseService] DETAIL used wrapped 'course' key decode")
            #endif
            return course
        }

        // Attempt 3: wrapped in a "data" key
        if let wrapped = try? decoder.decode(DataCourseResponse.self, from: data),
           let course = wrapped.data, course.id != 0 {
            #if DEBUG
            NSLog("[GolfCourseService] DETAIL used wrapped 'data' key decode")
            #endif
            return course
        }

        // Fall back to direct decode (throws if truly malformed, or returns partial data)
        #if DEBUG
        NSLog("[GolfCourseService] DETAIL all decode attempts gave id=0 — returning best-effort")
        #endif
        return (try? decoder.decode(GolfCourseResult.self, from: data)) ?? GolfCourseResult.empty
    }

    private struct WrappedCourseResponse: Decodable {
        let course: GolfCourseResult?
    }
    private struct DataCourseResponse: Decodable {
        let data: GolfCourseResult?
    }
}

// MARK: - Errors

enum GolfCourseAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case notFound
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .invalidResponse: return "Invalid server response"
        case .unauthorized: return "Invalid API key"
        case .notFound: return "Course not found"
        case .httpError(let code): return "Server error (\(code))"
        }
    }
}
