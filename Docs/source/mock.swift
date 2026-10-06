import SwiftUI

// MARK: - Разделы с образцовым содержимым
// Настоящие данные сюда не берём: документ уйдёт другим людям, а в скриншотах
// и буфере лежит личное. Размеры и вёрстка — те же, что в приложении.

/// Плеер: обложка слева, справа название с лайком, кнопки и перемотка, у края громкость.
/// Повторяет NotchMediaView — размеры из NotchConfig.
struct MockPlayer: View {
    var body: some View {
        GeometryReader { g in
            HStack(spacing: 14) {
                artworkSample(NotchConfig.playerArtworkHeight, NotchConfig.playerArtworkHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(maxHeight: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bohemian Rhapsody").font(.system(size: 16, weight: .semibold))
                            Text("Queen").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "heart.fill").font(.system(size: 15, weight: .medium))
                            .foregroundStyle(NotchConfig.favoriteYellow).frame(width: 30, height: 30)
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 22) {
                        Image(systemName: "backward.fill").font(.system(size: 24, weight: .medium)).frame(width: 36, height: 36)
                        Image(systemName: "pause.fill").font(.system(size: 34, weight: .medium)).frame(width: 46, height: 46)
                        Image(systemName: "forward.fill").font(.system(size: 24, weight: .medium)).frame(width: 36, height: 36)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer(minLength: 4)
                    HStack(spacing: 8) {
                        Text("2:29").font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary)
                        MockSlider(axis: .horizontal, fraction: 0.42, thickness: 4, thumb: true)
                        Text("5:55").font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .frame(height: 16)
                }
                .padding(.bottom, NotchConfig.playerBottomInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                VStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.fill").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white).frame(width: 24, height: 18)
                    MockSlider(axis: .vertical, fraction: 0.6, thickness: 10, thumb: false)
                        .frame(height: max(g.size.height * 2 / 3 - 26, 30))
                }
                .frame(width: 24)
                .frame(maxHeight: .infinity)
            }
        }
    }
}

/// Полоса как NotchSlider: белая заливка на полупрозрачной подложке, у перемотки — кружок.
struct MockSlider: View {
    let axis: Axis
    let fraction: CGFloat
    let thickness: CGFloat
    let thumb: Bool

    var body: some View {
        GeometryReader { g in
            let length = axis == .horizontal ? g.size.width : g.size.height
            let knob: CGFloat = thumb ? 11 : 0
            let offset = (length - knob) * fraction
            let filled = thumb ? offset + knob / 2 : length * fraction
            ZStack(alignment: axis == .horizontal ? .leading : .bottom) {
                Capsule().fill(Color.white.opacity(0.25))
                    .frame(width: axis == .horizontal ? length : thickness, height: axis == .horizontal ? thickness : length)
                Rectangle().fill(Color.white)
                    .frame(width: axis == .horizontal ? filled : thickness, height: axis == .horizontal ? thickness : filled)
                    .frame(width: axis == .horizontal ? length : thickness, height: axis == .horizontal ? thickness : length,
                           alignment: axis == .horizontal ? .leading : .bottom)
                    .clipShape(Capsule())
                if thumb {
                    Circle().fill(Color.white).shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .frame(width: knob, height: knob).offset(x: offset)
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: axis == .horizontal ? .leading : .bottom)
        }
        .frame(width: axis == .vertical ? 16 : nil, height: axis == .horizontal ? 16 : nil)
    }
}

/// Настройки — как NotchSettingsView: переключатели и подсказки.
struct MockSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toggle("Плеер на паузе", "Обложка и эквалайзер остаются на чёлке, когда музыка на паузе. Выключите — и на паузе чёлка станет обычной.", on: true)
            toggle("Приветствие при запуске", "При каждом запуске из чёлки спускается «hello».", on: true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Громкость на чёлке").font(.system(size: 13, weight: .medium))
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                }
                Text("Системный индикатор громкости скрыт — громкость видна только на чёлке.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func toggle(_ title: String, _ detail: String, on: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Capsule().fill(on ? NotchConfig.settingsOrange : Color.white.opacity(0.2))
                .frame(width: 34, height: 20)
                .overlay(alignment: on ? .trailing : .leading) { Circle().fill(Color.white).padding(2) }
        }
    }
}

/// Крылья громкости на свёрнутой чёлке — как NotchVolumeHUDView.
/// `shake` — сдвиг значка в момент выключения звука.
struct MockVolumeHUD: View {
    let level: CGFloat
    var shake: CGFloat = 0
    let notchHeight: CGFloat

    private var silent: Bool { level == 0 }
    private var symbol: String {
        silent ? "speaker.slash.fill"
            : level < 0.33 ? "speaker.wave.1.fill" : level < 0.66 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                    .frame(width: 16, alignment: .leading).offset(x: shake)
                Text("Sound").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(silent ? NotchConfig.volumeRed : Color.white)
            .frame(width: NotchConfig.volumeHUDWingWidth)
            Spacer(minLength: 0)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25))
                    Capsule().fill(Color.white).frame(width: max(g.size.width * level, level > 0 ? 5 : 0))
                }
            }
            .frame(height: 5).padding(.horizontal, 12)
            .frame(width: NotchConfig.volumeHUDWingWidth)
        }
        .frame(height: notchHeight)
    }
}

struct MockSearch: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Google").font(.system(size: 20, weight: .semibold, design: .rounded))
            HStack(spacing: 8) {
                Text("Введите запрос").font(.system(size: 13)).foregroundStyle(.white.opacity(0.28))
                Spacer(minLength: 0)
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary).frame(width: 22, height: 22)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(sampleFill) }
            Spacer(minLength: 0)
        }
    }
}

struct MockShots: View {
    var body: some View {
        let w: CGFloat = 122, h: CGFloat = 88
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { col in
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(LinearGradient(colors: [Color(hue: 0.55 + Double(row * 4 + col) * 0.05, saturation: 0.5, brightness: 0.75),
                                                              Color(hue: 0.75 + Double(row * 4 + col) * 0.04, saturation: 0.45, brightness: 0.55)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: w, height: h)
                            HStack(spacing: 3) {
                                ForEach(["arrow.up.forward", "xmark"], id: \.self) { s in
                                    Image(systemName: s).font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(Color(white: 0.32)).frame(width: 15, height: 15)
                                        .background { Circle().fill(Color(white: 0.9)) }
                                }
                            }.padding(4)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }
}

/// Буфер обмена: список, полоса с поиском и очисткой и — если открыт — поиск снизу.
/// Повторяет NotchClipboardView.
struct MockClipboard: View {
    var searchOpen = false

    private let items: [(String, String, Bool)] = [
        ("https://developer.apple.com/documentation/swiftui", "18:09", true),
        ("Отчёт за сентябрь — финальная версия", "18:12", false),
        ("Встреча в четверг в 15:00, переговорка 3", "17:58", false),
        ("brew install --cask iterm2", "17:40", false),
        ("Пришли, пожалуйста, отчёт до пятницы", "16:21", false),
    ]
    private let query = "отч"

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                VStack(spacing: 4) {
                    ForEach(items, id: \.0) { row($0, highlight: false) }
                }
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .clipped()

                HStack(spacing: 0) {
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold))
                        Text("Поиск").font(.system(size: 11, weight: .medium))
                        Image(systemName: searchOpen ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold)).opacity(0.7)
                    }
                    .foregroundStyle(searchOpen ? Color.white : Color.secondary)
                    .padding(.horizontal, 9).frame(height: 22)
                    .background { Capsule().fill(Color.white.opacity(searchOpen ? 0.16 : 0.07)) }
                    Spacer(minLength: 0)
                    Text("Очистить").font(.system(size: 10)).foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background { Capsule().fill(Color.white.opacity(0.10)) }
                }
            }
            .frame(height: searchOpen ? NotchConfig.sectionListHeight : nil)
            .frame(minHeight: 0, maxHeight: searchOpen ? nil : .infinity)

            if searchOpen {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(query).font(.system(size: 12))
                        Rectangle().fill(NotchConfig.accentBlue).frame(width: 1.5, height: 14)
                        Spacer(minLength: 0)
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    .padding(.horizontal, 9).frame(height: 26)
                    .background { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08)) }

                    VStack(spacing: 4) {
                        row(("Отчёт за сентябрь — финальная версия", "18:12", false))
                        row(("Пришли, пожалуйста, отчёт до пятницы", "16:21", false))
                        row(("Отчёты лежат в общей папке /Reports", "вчера", false))
                    }
                }
                .padding(.top, 10)
                .frame(height: NotchConfig.tallExtraHeight, alignment: .top)
            }
        }
    }

    private func row(_ item: (String, String, Bool), highlight: Bool = true) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(highlight ? highlighted(item.0) : AttributedString(item.0))
                    .font(.system(size: 12)).lineLimit(1)
                Text(item.1).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if item.2 {
                Image(systemName: "pin.fill").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NotchConfig.accentBlue).frame(width: 18, height: 18)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.05)) }
    }

    /// Найденное — синим и жирным, как в приложении.
    private func highlighted(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        var start = text.startIndex
        while let range = text.range(of: query, options: .caseInsensitive, range: start..<text.endIndex) {
            if let r = Range(range, in: result) {
                result[r].foregroundColor = NotchConfig.accentBlue
                result[r].inlinePresentationIntent = .stronglyEmphasized
            }
            start = range.upperBound
        }
        return result
    }
}

/// Что выдвинуто под переводчиком — как NotchTranslator.Drawer в приложении.
enum MockDrawer { case none, details, history, favorites }

/// Переводчик: те же колонки через 34 pt, полоса кнопок снизу и выдвижная часть.
/// Повторяет NotchTranslatorView — высоты из NotchConfig.
struct MockTranslator: View {
    var drawer: MockDrawer = .none

    private let gap: CGFloat = 34
    private let green = NotchConfig.englishGreen

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                HStack(spacing: gap) {
                    Text(drawer == .details ? "English" : "Русский").frame(maxWidth: .infinity, alignment: .leading)
                    Text(drawer == .details ? "Русский" : "English").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: gap) {
                    sampleBlock(fills: true) { source }
                        .overlay(alignment: .bottomTrailing) { corner("xmark") }
                    sampleBlock(fills: true) { Text(drawer == .details ? "бежать" : "Hello, how are you? Long time no see").font(.system(size: 13)) }
                        .overlay(alignment: .bottomTrailing) { corner("doc.on.doc") }
                        .overlay(alignment: .topTrailing) { star }
                }
                .overlay {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary).frame(width: 28, height: 18)
                        .background { Capsule().fill(Color.white.opacity(0.10)) }
                }

                HStack(spacing: 0) {
                    barButton("История", "clock.arrow.circlepath", open: drawer == .history)
                    barButton("Избранное", drawer == .favorites ? "star.fill" : "star", open: drawer == .favorites,
                              iconColor: NotchConfig.favoriteYellow)
                        .padding(.leading, 6)
                    Spacer(minLength: 0)
                    barButton("Варианты и примеры", "text.book.closed", open: drawer == .details)
                }
            }
            .frame(height: NotchConfig.sectionListHeight)

            if drawer != .none {
                Group {
                    switch drawer {
                    case .details: details
                    case .favorites: favorites
                    default: history
                    }
                }
                .padding(.top, 10)
                .frame(height: NotchConfig.tallExtraHeight, alignment: .top)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// В обычном виде — с бледной подсказкой недописанного слова.
    @ViewBuilder private var source: some View {
        if drawer == .details {
            Text("run").font(.system(size: 13))
        } else {
            Text("Привет, как дела? Давно не ви\(Text("делись").foregroundStyle(Color.white.opacity(0.3)))")
                .font(.system(size: 13))
        }
    }

    private func corner(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55)).frame(width: 20, height: 20)
            .background { Circle().fill(.white.opacity(0.10)) }.padding(5)
    }

    /// Залитая: на снимках перевод уже сохранён — так видно, как звёздочка выглядит отмеченной.
    private var star: some View {
        Image(systemName: drawer == .details ? "star" : "star.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(NotchConfig.favoriteYellow)
            .frame(width: 30, height: 30).padding(4)
    }

    private func barButton(_ title: String, _ icon: String, open: Bool, iconColor: Color? = nil) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(iconColor ?? (open ? Color.white : Color.secondary))
            Text(title).font(.system(size: 11, weight: .medium))
            Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.7)
        }
        .foregroundStyle(open ? Color.white : Color.secondary)
        .padding(.horizontal, 9).frame(height: 22)
        .background { Capsule().fill(Color.white.opacity(open ? 0.16 : 0.07)) }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
    }

    // Образцы взяты из тех же источников, что и в приложении: словарь Яндекса и Tatoeba.
    private var details: some View {
        HStack(alignment: .top, spacing: gap) {
            VStack(alignment: .leading, spacing: 8) {
                label("Варианты")
                group("глагол", [("бежать", "flee, run away"), ("работать", "work"),
                                 ("управлять", "manage"), ("запустить", "start, launch")])
                group("существительное", [("бег", ""), ("запуск", "launch")])
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                label("Примеры")
                example("Why is he running away?", "Почему он убегает?")
                example("His patience is running out.", "Его терпение на исходе.")
                example("The buses run until midnight.", "Автобусы ходят до полуночи.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12))
    }

    private func group(_ pos: String, _ variants: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(pos).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.white.opacity(0.4))
            ForEach(variants, id: \.0) { v in
                Text("\(v.0)  \(Text(v.1).foregroundStyle(green.opacity(0.75)))")
            }
        }
    }

    private func example(_ en: String, _ ru: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(en).foregroundStyle(green)
            Text(ru).foregroundStyle(.secondary)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                label("Недавние")
                Spacer()
                Text("Очистить").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            VStack(spacing: 2) {
                row("Привет, как дела? Давно не виделись", "Hello, how are you? Long time no see", ru: true, english: green)
                row("deadline", "крайний срок", ru: false)
                row("Встреча переносится на четверг", "The meeting is postponed to Thursday", ru: true)
                row("I'll get back to you", "Я вам отвечу", ru: false)
                row("Спасибо за помощь", "Thanks for the help", ru: true)
                row("to be honest", "честно говоря", ru: false)
            }
        }
    }

    private var favorites: some View {
        let yellow = NotchConfig.favoriteYellow
        return VStack(alignment: .leading, spacing: 4) {
            label("Сохранённые")
            VStack(spacing: 2) {
                row("Привет, как дела? Давно не виделись", "Hello, how are you? Long time no see", ru: true, english: yellow)
                row("It's not my cup of tea", "Это не моё", ru: false, english: yellow)
                row("Не откладывай на завтра", "Don't put it off until tomorrow", ru: true, english: yellow)
                row("to be on the same page", "быть на одной волне", ru: false, english: yellow)
                row("отличная идея", "a great idea", ru: true, english: yellow)
                row("serendipity", "счастливая случайность", ru: false, english: yellow)
            }
        }
    }

    private func row(_ source: String, _ target: String, ru: Bool, english: Color? = nil) -> some View {
        let english = english ?? green
        return HStack(alignment: .firstTextBaseline, spacing: gap) {
            Text(source).foregroundStyle(ru ? Color.white : english).frame(maxWidth: .infinity, alignment: .leading)
            Text(target).foregroundStyle(ru ? english : Color.white).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12)).lineLimit(1)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.04)) }
    }
}

/// Верхняя полоса панели целиком.
struct MockStrip: View {
    let section: String
    var body: some View {
        HStack(spacing: 2) {
            Text(section).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Image(systemName: "wifi").font(.system(size: 11, weight: .medium))
                .foregroundStyle(NotchConfig.accentBlue).frame(width: 20, height: 20)
            BluetoothGlyph().stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                .frame(width: 8, height: 12).frame(width: 20, height: 20)
            Image(systemName: "gearshape").font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary).frame(width: 20, height: 20)
            HStack(spacing: 2) {
                Image(systemName: "battery.75percent").font(.system(size: 13))
                Text("64%").font(.system(size: 11, weight: .medium)).monospacedDigit()
            }
            .foregroundStyle(.secondary).padding(.leading, 6)
        }
        .padding(.horizontal, 14).frame(width: 514, height: 32)
        .background(Color.black).environment(\.colorScheme, .dark)
    }
}
