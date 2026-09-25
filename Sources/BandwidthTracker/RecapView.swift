import SwiftUI

struct RecapView: View {
    @EnvironmentObject var history: HistoryStore
    @State private var monthOffset: Int = 0

    private var calendar: Calendar { HistoryStore.jakartaCalendar }
    private var now: Date { Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            thisWeek
            dividerLine
            thisMonth
            dividerLine
            monthCalendar
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    // MARK: - This Week

    private var weekDays: [Date] {
        var days: [Date] = []
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        guard let weekStart = calendar.date(from: components) else { return [] }
        for i in 0..<7 {
            if let d = calendar.date(byAdding: .day, value: i, to: weekStart) {
                days.append(d)
            }
        }
        return days
    }

    private var weekTotal: UInt64 {
        weekDays.reduce(UInt64(0)) { $0 &+ history.total(day: HistoryStore.dayKey($1)) }
    }

    private var weekMax: UInt64 {
        weekDays.map { history.total(day: HistoryStore.dayKey($0)) }.max() ?? 1
    }

    private var thisWeek: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("THIS WEEK").sectionLabel()
                Spacer()
                Text(ByteFormat.bytes(weekTotal))
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            VStack(spacing: 8) {
                ForEach(weekDays, id: \.self) { d in
                    weekRow(date: d)
                }
            }
        }
    }

    private func weekRow(date: Date) -> some View {
        let key = HistoryStore.dayKey(date)
        let total = history.total(day: key)
        let dayName = shortDayName(date)
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let frac = weekMax > 0 ? CGFloat(total) / CGFloat(weekMax) : 0
        let barColor: Color = isToday
            ? Color.primary.opacity(0.85)
            : Color.primary.opacity(0.35)

        return HStack(spacing: 10) {
            Text(dayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isToday ? .primary : .secondary)
                .frame(width: 32, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule().fill(barColor)
                        .frame(width: max(total == 0 ? 0 : 3, geo.size.width * frac))
                }
            }
            .frame(height: 6)

            Text(total == 0 ? "—" : ByteFormat.bytes(total))
                .font(.system(size: 11, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(total == 0 ? .tertiary : .secondary)
                .frame(width: 70, alignment: .trailing)
        }
    }

    // MARK: - This Month

    private var monthTotal: UInt64 {
        guard let range = calendar.range(of: .day, in: .month, for: now),
              let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else { return 0 }
        var sum: UInt64 = 0
        for offset in 0..<range.count {
            if let d = calendar.date(byAdding: .day, value: offset, to: monthStart) {
                sum &+= history.total(day: HistoryStore.dayKey(d))
            }
        }
        return sum
    }

    private var monthNameYear: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.timeZone = HistoryStore.jakartaTZ
        return f.string(from: now).uppercased()
    }

    private var thisMonth: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("THIS MONTH").sectionLabel()
                Text(monthNameYear)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(ByteFormat.bytes(monthTotal))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Month calendar

    private var displayedMonth: Date {
        calendar.date(byAdding: .month, value: monthOffset, to: now) ?? now
    }

    private var monthCalendar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    monthOffset -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Text(displayedMonthLabel).sectionLabel()

                Button {
                    monthOffset += 1
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(monthOffset >= 0 ? .tertiary : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(monthOffset >= 0)

                Spacer()
            }
            calendarGrid
        }
    }

    private var displayedMonthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.timeZone = HistoryStore.jakartaTZ
        return f.string(from: displayedMonth).uppercased()
    }

    private var calendarGrid: some View {
        let target = displayedMonth
        let range = calendar.range(of: .day, in: .month, for: target) ?? 1..<31
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: target)) ?? target

        // Compute leading empty cells (Monday = 0 index)
        let weekdayOfFirst = calendar.component(.weekday, from: monthStart)
        let mondayFirst = (weekdayOfFirst + 5) % 7 // Mon=0, Sun=6
        let totalCells = mondayFirst + range.count
        let rows = Int(ceil(Double(totalCells) / 7.0))
        let cellCount = rows * 7

        let dayValues: [UInt64] = (0..<range.count).map { i in
            guard let d = calendar.date(byAdding: .day, value: i, to: monthStart) else { return 0 }
            return history.total(day: HistoryStore.dayKey(d))
        }
        let maxDay = dayValues.max() ?? 0

        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(["M","T","W","T","F","S","S"], id: \.self) { d in
                    Text(d)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<cellCount, id: \.self) { idx in
                    if idx < mondayFirst || idx - mondayFirst >= range.count {
                        Color.clear.frame(height: 40)
                    } else {
                        let dayNumber = idx - mondayFirst + 1
                        let dayDate = calendar.date(byAdding: .day, value: dayNumber - 1, to: monthStart) ?? monthStart
                        calendarCell(dayNumber: dayNumber, date: dayDate, total: dayValues[dayNumber - 1], maxDay: maxDay)
                    }
                }
            }
        }
    }

    private func calendarCell(dayNumber: Int, date: Date, total: UInt64, maxDay: UInt64) -> some View {
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let isFuture = date > now && !isToday
        let intensity: Double = maxDay > 0 ? min(1.0, Double(total) / Double(maxDay)) : 0
        let fillOpacity: Double = intensity * (isToday ? 0.28 : 0.22)

        return VStack(spacing: 2) {
            Text("\(dayNumber)")
                .font(.system(size: 11, weight: isToday ? .semibold : .medium))
                .foregroundStyle(isFuture ? .tertiary : (isToday ? .primary : .secondary))
            Text(ByteFormat.shortBytes(total))
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isFuture ? .tertiary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(fillOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isToday ? Color.primary.opacity(0.85) : Color.clear, lineWidth: 1)
        )
        .help(total > 0 ? "\(HistoryStore.dayKey(date)) · \(ByteFormat.bytes(total))" : HistoryStore.dayKey(date))
    }

    // MARK: - Helpers

    private var dividerLine: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
    }

    private func shortDayName(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        f.timeZone = HistoryStore.jakartaTZ
        return f.string(from: date)
    }
}
