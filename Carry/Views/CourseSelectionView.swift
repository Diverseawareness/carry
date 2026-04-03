import SwiftUI

/// Course selection flow: recent courses + search + tee picker.
/// Presented before GroupManagerView when creating a new round.
struct CourseSelectionView: View {
    var onBack: (() -> Void)?
    let onCourseSelected: (SelectedCourse) -> Void

    @State private var searchText = ""
    @FocusState private var isSearchFieldFocused: Bool
    @State private var searchResults: [GolfCourseResult] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var recentCourses: [RecentCourse] = Self.loadRecentCourses()
    @State private var searchDebounceTask: Task<Void, Never>?

    // Tee picker state
    @State private var selectedCourse: GolfCourseResult?
    @State private var loadingCourseId: Int?
    @State private var courseDetail: GolfCourseResult?
    @State private var showTeePicker = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if showTeePicker, let detail = courseDetail {
                    teePickerView(detail)
                } else {
                    mainListView
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                if showTeePicker {
                    Color.clear.frame(width: 40, height: 40)
                } else if let onBack = onBack {
                    Button(action: onBack) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color.pureBlack)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.bgPrimary))
                    }
                } else {
                    Color.clear.frame(width: 40, height: 40)
                }

                Spacer()

                Text(showTeePicker ? "Select Tees" : "Select Course")
                    .font(.carry.headline)
                    .foregroundColor(Color.pureBlack)

                Spacer()

                Color.clear.frame(width: 40, height: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)

            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.5)
        }
        .background(Color.white)
    }

    // MARK: - Main List (Recent + Search)

    private var mainListView: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.carry.body)
                    .foregroundColor(Color.textDisabled)

                TextField("Search golf clubs", text: $searchText)
                    .font(.system(size: 16))
                    .focused($isSearchFieldFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: searchText) { _, newValue in
                        debounceSearch(newValue)
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                        searchError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.carry.bodyLG)
                            .foregroundColor(Color.textDisabled)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSearchFieldFocused ? Color(hexString: "#333333") : Color.borderLight, lineWidth: isSearchFieldFocused ? 1.5 : 1)
            )
            .animation(.easeOut(duration: 0.15), value: isSearchFieldFocused)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 0) {
                    if searchText.isEmpty {
                        recentCoursesSection
                    } else {
                        searchResultsSection
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Recent Courses

    private var recentCoursesSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recent Courses")
                    .font(.carry.bodySMBold)
                    .foregroundColor(Color.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            if recentCourses.isEmpty {
                VStack(spacing: 6) {
                    Text("No recent courses")
                        .font(.carry.bodySM)
                        .foregroundColor(Color.textDisabled)
                    Text("Search above to find a course")
                        .font(.carry.caption)
                        .foregroundColor(Color.borderMedium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(recentCourses) { course in
                    recentCourseRow(course)
                }
            }
        }
    }

    private func recentCourseRow(_ course: RecentCourse) -> some View {
        Button {
            loadCourseDetails(courseId: course.courseId)
        } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(course.displayName)
                        .font(.carry.bodySemibold)
                        .foregroundColor(Color.pureBlack)
                    if !course.locationLabel.isEmpty {
                        Text(course.locationLabel)
                            .font(.carry.caption)
                            .foregroundColor(Color.textTertiary)
                    }
                    Text("Last played: \(course.lastTeeName) tees")
                        .font(.carry.micro)
                        .foregroundColor(Color.textDisabled)
                }

                Spacer()

                if loadingCourseId == course.courseId {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
        .buttonStyle(.plain)
        .disabled(loadingCourseId != nil)
    }

    // MARK: - Search Results

    private var searchResultsSection: some View {
        VStack(spacing: 0) {
            if isSearching {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Searching courses...")
                        .font(.carry.captionLG)
                        .foregroundColor(Color.textDisabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if let error = searchError {
                Text(error)
                    .font(.carry.captionLG)
                    .foregroundColor(Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 40)
            } else if searchResults.isEmpty && searchText.count >= 2 {
                VStack(spacing: 6) {
                    Text("No courses found")
                        .font(.carry.bodySM)
                        .foregroundColor(Color.textDisabled)
                    Text("Try a different search term")
                        .font(.carry.caption)
                        .foregroundColor(Color.borderMedium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                HStack {
                    Text("Results")
                        .font(.carry.bodySMBold)
                        .foregroundColor(Color.textPrimary)

                    if !searchResults.isEmpty {
                        Text("\(searchResults.count)")
                            .font(.carry.microSM)
                            .foregroundColor(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.textDisabled))
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

                ForEach(searchResults) { course in
                    searchResultRow(course)
                }
            }
        }
    }

    private func searchResultRow(_ course: GolfCourseResult) -> some View {
        Button {
            // Search results already include full tee data — use directly, no extra API call needed.
            if let tees = course.tees, !tees.all.isEmpty {
                selectedCourse = course
                courseDetail = course
                withAnimation(.easeInOut(duration: 0.25)) { showTeePicker = true }
            } else {
                loadCourseDetails(courseId: course.id)
            }
        } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(course.displayName)
                        .font(.carry.bodySemibold)
                        .foregroundColor(Color.pureBlack)
                        .lineLimit(1)

                    if let club = course.clubName, let cn = course.courseName, club != cn, !club.isEmpty {
                        Text(club)
                            .font(.carry.caption)
                            .foregroundColor(Color.textTertiary)
                            .lineLimit(1)
                    }

                    if !course.locationLabel.isEmpty {
                        Text(course.locationLabel)
                            .font(.carry.caption)
                            .foregroundColor(Color.textDisabled)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if loadingCourseId == course.id {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
        .buttonStyle(.plain)
        .disabled(loadingCourseId != nil)
    }

    // MARK: - Tee Picker

    private func teePickerView(_ course: GolfCourseResult) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Course info header
                VStack(spacing: 4) {
                    Text(course.displayName)
                        .font(.carry.sectionTitle)
                        .foregroundColor(Color.pureBlack)
                    if !course.locationLabel.isEmpty {
                        Text(course.locationLabel)
                            .font(.carry.captionLG)
                            .foregroundColor(Color.textTertiary)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 24)

                // Men's tees
                if let maleTees = course.tees?.male, !maleTees.isEmpty {
                    teeSectionHeader("Men's Tees")
                    ForEach(maleTees) { tee in
                        teeRow(tee, course: course)
                    }
                }

                // Women's tees
                if let femaleTees = course.tees?.female, !femaleTees.isEmpty {
                    teeSectionHeader("Women's Tees")
                        .padding(.top, 16)
                    ForEach(femaleTees) { tee in
                        teeRow(tee, course: course)
                    }
                }

                // No tees fallback
                if course.tees?.all.isEmpty ?? true {
                    VStack(spacing: 6) {
                        Text("No tee data available")
                            .font(.carry.bodySM)
                            .foregroundColor(Color.textTertiary)
                        Text("You can still select this course")
                            .font(.carry.caption)
                            .foregroundColor(Color.textDisabled)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)

                    Button {
                        selectCourse(course, tee: nil)
                    } label: {
                        Text("Continue Without Tee Data")
                            .font(.carry.bodySemibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.textPrimary))
                    }
                    .padding(.horizontal, 40)
                }

                Spacer().frame(height: 60)
            }
        }
    }

    private func teeSectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.carry.bodySMBold)
                .foregroundColor(Color.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func teeRow(_ tee: GolfCourseTeeBox, course: GolfCourseResult) -> some View {
        Button {
            selectCourse(course, tee: tee)
        } label: {
            HStack(spacing: 12) {
                // Tee colour dot — kept as it's a meaningful visual indicator
                Circle()
                    .fill(Color(hexString: tee.colorHex))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(tee.teeName ?? "Tees")
                        .font(.carry.bodySemibold)
                        .foregroundColor(Color.pureBlack)

                    HStack(spacing: 10) {
                        if let yards = tee.totalYards {
                            Text("\(yards) yds")
                                .font(.carry.micro)
                                .foregroundColor(Color.textTertiary)
                        }
                        if let par = tee.parTotal {
                            Text("Par \(par)")
                                .font(.carry.micro)
                                .foregroundColor(Color.textTertiary)
                        }
                    }
                }

                Spacer()

                // Rating / Slope
                VStack(alignment: .trailing, spacing: 2) {
                    if let cr = tee.courseRating {
                        Text(String(format: "%.1f", cr))
                            .font(.carry.bodySMBold)
                            .foregroundColor(Color.pureBlack)
                    }
                    if let sr = tee.slopeRating {
                        Text("Slope \(sr)")
                            .font(.carry.micro)
                            .foregroundColor(Color.textDisabled)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func debounceSearch(_ query: String) {
        searchDebounceTask?.cancel()
        guard query.count >= 2 else {
            searchResults = []
            searchError = nil
            isSearching = false
            return
        }

        isSearching = true
        searchError = nil

        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }

            do {
                let results = try await GolfCourseService.shared.searchCourses(query: query)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    searchResults = results
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    searchError = error.localizedDescription
                    isSearching = false
                }
            }
        }
    }

    private func loadCourseDetails(courseId: Int) {
        loadingCourseId = courseId

        Task {
            do {
                let detail = try await GolfCourseService.shared.getCourseDetails(courseId: courseId)
                await MainActor.run {
                    loadingCourseId = nil
                    selectedCourse = detail
                    courseDetail = detail
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showTeePicker = true
                    }
                }
            } catch {
                await MainActor.run {
                    loadingCourseId = nil
                    searchError = "Failed to load course: \(error.localizedDescription)"
                }
            }
        }
    }

    private func selectCourse(_ course: GolfCourseResult, tee: GolfCourseTeeBox?) {
        let teeBox: TeeBox? = tee.map { TeeBox(from: $0, courseId: String(course.id)) }
        #if DEBUG
        print("[CourseSelection] selectCourse: \(course.displayName) tee=\(tee?.teeName ?? "nil") apiHoles=\(tee?.holes?.count ?? 0) teeBoxHoles=\(teeBox?.holes?.count ?? 0)")
        if let holes = teeBox?.holes {
            let pars = holes.map { "H\($0.num)=\($0.par)" }.joined(separator: " ")
            print("[CourseSelection] Hole pars: \(pars)")
        }
        #endif

        let selected = SelectedCourse(
            courseId: course.id,
            courseName: course.displayName,
            clubName: course.clubName ?? course.displayName,
            location: course.locationLabel,
            teeBox: teeBox,
            apiTee: tee
        )

        // Prepend to recent courses so it appears next time (dedup by courseId, cap at 5)
        let recent = RecentCourse(
            courseId: course.id,
            courseName: course.courseName ?? course.displayName,
            clubName: course.clubName ?? course.displayName,
            city: course.location?.city ?? "",
            state: course.location?.state ?? "",
            lastTeeName: tee?.teeName ?? "—",
            lastPlayedDate: Date()
        )
        recentCourses.removeAll { $0.courseId == course.id }
        recentCourses.insert(recent, at: 0)
        if recentCourses.count > 5 { recentCourses = Array(recentCourses.prefix(5)) }
        Self.saveRecentCourses(recentCourses)

        onCourseSelected(selected)
    }

    // MARK: - Recent Courses Persistence

    private static let recentCoursesKey = "carry_recent_courses"

    private static func loadRecentCourses() -> [RecentCourse] {
        guard let data = UserDefaults.standard.data(forKey: recentCoursesKey),
              let courses = try? JSONDecoder().decode([RecentCourse].self, from: data) else {
            return []
        }
        return courses
    }

    private static func saveRecentCourses(_ courses: [RecentCourse]) {
        if let data = try? JSONEncoder().encode(courses) {
            UserDefaults.standard.set(data, forKey: recentCoursesKey)
        }
    }
}

// MARK: - Selected Course Result

struct SelectedCourse {
    let courseId: Int
    let courseName: String
    let clubName: String
    let location: String
    let teeBox: TeeBox?
    let apiTee: GolfCourseTeeBox?
}
