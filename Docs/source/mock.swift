import SwiftUI

// MARK: - Разделы с образцовым содержимым
// Настоящие данные сюда не берём: документ уйдёт другим людям, а в скриншотах
// и буфере лежит личное. Размеры и вёрстка — те же, что в приложении.

struct MockPlayer: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                artworkSample(104, 104)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .frame(width: 27, height: 27)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Bohemian Rhapsody").font(.system(size: 13, weight: .semibold))
                Text("Queen").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 6)
                VStack(spacing: 3) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(Color.white.opacity(0.5)).frame(width: g.size.width * 0.42)
                        }.frame(height: 3)
                    }.frame(height: 3)
                    HStack {
                        Text("2:29").font(.system(size: 9)).monospacedDigit()
                        Spacer()
                        Text("5:55").font(.system(size: 9)).monospacedDigit()
                    }.foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    Image(systemName: "backward.fill").font(.system(size: 12, weight: .medium)).frame(width: 28, height: 28)
                    Image(systemName: "pause.fill").font(.system(size: 15, weight: .medium)).frame(width: 31, height: 31)
                    Image(systemName: "forward.fill").font(.system(size: 12, weight: .medium)).frame(width: 28, height: 28)
                }
                .frame(maxWidth: .infinity, alignment: .center).padding(.top, 6)
            }
        }
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

struct MockClipboard: View {
    let items = [("Привет, меня зовут Сергей", "18:10", false),
                 ("https://developer.apple.com/documentation", "18:09", true),
                 ("NotchDeck", "17:52", false)]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.0) { item in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.0).font(.system(size: 13)).lineLimit(1)
                        Text(item.1).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if item.2 {
                        Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(sampleFill) }
            }
            Spacer(minLength: 0)
            Text("Очистить").font(.system(size: 10)).foregroundStyle(.secondary)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background { Capsule().fill(sampleFill) }
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

struct MockTranslator: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text("Русский").frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary).frame(width: 28, height: 18)
                    .background { Capsule().fill(sampleFill) }
                Text("English").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 10) {
                sampleBlock(fills: true) { Text("Привет, как дела?").font(.system(size: 13)) }
                sampleBlock(fills: true) { Text("Hello, how are you?").font(.system(size: 13)) }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "doc.on.doc").font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55)).frame(width: 20, height: 20)
                            .background { Circle().fill(.white.opacity(0.10)) }.padding(5)
                    }
            }
        }
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
