import SwiftUI

// MARK: - Onglet Devoirs : une semaine par écran, balayage horizontal

struct HomeworkTabView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedWeek = DateFR.startOfWeek(Date())

    private var weeks: [Date] {
        var weekList: [Date] = []
        let current = DateFR.startOfWeek(Date())
        let dueDates = model.snapshot.homework.compactMap(\.due)
        if dueDates.isEmpty {
            for offset in -2...8 {
                if let wk = Calendar.current.date(byAdding: .day, value: offset * 7, to: current) {
                    weekList.append(DateFR.startOfWeek(wk))
                }
            }
            return weekList
        }
        let first = DateFR.startOfWeek(dueDates.min()!)
        let last = DateFR.startOfWeek(dueDates.max()!)
        let start = min(first, current)
        let end = max(last, current)
        var cursor = start
        while cursor <= end, weekList.count < 60 {
            weekList.append(cursor)
            guard let next = Calendar.current.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return weekList
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedWeek) {
                ForEach(weeks, id: \.self) { week in
                    WeekHomeworkPage(week: week)
                        .tag(week)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(Theme.background))
            .navigationTitle("Semaine du " + DateFR.shortTitle(selectedWeek))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if DateFR.startOfWeek(Date()) == selectedWeek {
                        BlueBadge(text: "Cette semaine")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            shiftWeek(-1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundStyle(Color(Theme.accent))
                        }
                        Button {
                            withAnimation { selectedWeek = DateFR.startOfWeek(Date()) }
                        } label: {
                            Image(systemName: "smallcircle.filled.circle")
                                .foregroundStyle(Color(Theme.accent))
                        }
                        Button {
                            shiftWeek(1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Color(Theme.accent))
                        }
                    }
                }
            }
            .refreshable {
                await model.refreshAll(silent: true)
            }
        }
    }

    private func shiftWeek(_ delta: Int) {
        guard let target = Calendar.current.date(byAdding: .day, value: delta * 7, to: selectedWeek) else { return }
        withAnimation { selectedWeek = DateFR.startOfWeek(target) }
    }
}

struct WeekHomeworkPage: View {
    @EnvironmentObject var model: AppModel
    var week: Date

    private var weekEnd: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: week) ?? week
    }

    private var inWeek: [Homework] {
        model.snapshot.homework
            .filter { hw in
                guard let due = hw.due else { return week == DateFR.startOfWeek(Date()) }
                return due >= week && due < weekEnd
            }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    private var groupedByDay: [(day: Date?, list: [Homework])] {
        let dated = Dictionary(grouping: inWeek.filter { $0.due != nil }) { DateFR.calendar.startOfDay(for: $0.due!) }
        let undated = inWeek.filter { $0.due == nil }
        var groups: [(day: Date?, list: [Homework])] = dated.sorted { $0.key < $1.key }.map { (day: Optional($0.key), list: $0.value) }
        if !undated.isEmpty {
            groups.append((day: nil, list: undated))
        }
        return groups
    }

    var body: some View {
        Group {
            if inWeek.isEmpty {
                EmptyState(icon: "checkmark.circle", title: "Aucun devoir",
                           message: "Aucun devoir récupéré pour cette semaine.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(groupedByDay, id: \.day) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.day.map { DateFR.title($0) } ?? "Date inconnue")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color(Theme.accent))
                                    .padding(.leading, 4)
                                ForEach(group.list) { hw in
                                    HomeworkRow(homework: hw)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

struct HomeworkRow: View {
    @EnvironmentObject var model: AppModel
    var homework: Homework

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        model.toggleDone(homework)
                    } label: {
                        Image(systemName: homework.done ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(homework.done ? Color(Theme.accent) : Color(Theme.textTertiary))
                    }
                    .buttonStyle(.plain)
                    Text(homework.subject)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(Theme.accent))
                    Spacer()
                }

                Text(homework.text)
                    .font(.subheadline)
                    .foregroundStyle(homework.done ? Color(Theme.textTertiary) : Color(Theme.text))
                    .strikethrough(homework.done)

                if !homework.attachments.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(homework.attachments.enumerated()), id: \.offset) { _, att in
                            if let url = att.url {
                                Link(destination: url) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "paperclip")
                                            .font(.caption)
                                        Text(att.name)
                                            .font(.caption)
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(Color(Theme.accent))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
