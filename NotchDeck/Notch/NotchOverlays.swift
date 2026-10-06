import SwiftUI

// MARK: - Приветствие

/// «hello» при первом запуске — пишется от руки, как на новом Mac.
struct NotchGreetingView: View {

    /// Высота чёлки: под ней надпись и живёт, сверху её закрыл бы вырез.
    let notchHeight: CGFloat

    @State private var progress: CGFloat = 0

    var body: some View {
        HelloShape()
            .trim(from: 0, to: progress)
            .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .padding(.horizontal, 18)
            .padding(.top, notchHeight + 8)
            .padding(.bottom, 14)
            .onAppear {
                // Чуть позже, чем начнёт раскрываться плашка: писать в ещё узкой
                // было бы некуда.
                withAnimation(.easeInOut(duration: NotchConfig.greetingWriteDuration).delay(0.25)) {
                    progress = 1
                }
            }
    }
}

/// Одним росчерком, без отрывов — только так `trim` рисует надпись «рукой».
/// Обвести контур шрифта не вышло бы: у буквы он двойной, и рука шла бы по краям.
struct HelloShape: Shape {

    /// В этой системе координат нарисован путь; при выводе подгоняется под рамку.
    private static let canvas = CGRect(x: 6, y: 2, width: 220, height: 84)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

        path.move(to: p(10, 78))
        // h
        path.addCurve(to: p(56, 20), control1: p(30, 70), control2: p(52, 40))
        path.addCurve(to: p(42, 18), control1: p(59, 6), control2: p(46, 4))
        path.addCurve(to: p(34, 80), control1: p(38, 34), control2: p(36, 60))
        path.addCurve(to: p(58, 52), control1: p(40, 62), control2: p(48, 52))
        path.addCurve(to: p(66, 72), control1: p(68, 52), control2: p(68, 64))
        path.addCurve(to: p(78, 78), control1: p(64, 80), control2: p(70, 82))
        // e
        path.addCurve(to: p(100, 58), control1: p(88, 74), control2: p(100, 66))
        path.addCurve(to: p(86, 56), control1: p(100, 50), control2: p(90, 48))
        path.addCurve(to: p(100, 80), control1: p(82, 66), control2: p(88, 80))
        path.addCurve(to: p(124, 62), control1: p(110, 80), control2: p(118, 72))
        // l
        path.addCurve(to: p(138, 14), control1: p(132, 48), control2: p(140, 24))
        path.addCurve(to: p(126, 22), control1: p(136, 4), control2: p(126, 6))
        path.addCurve(to: p(128, 74), control1: p(126, 40), control2: p(124, 62))
        path.addCurve(to: p(146, 72), control1: p(131, 82), control2: p(140, 80))
        // l
        path.addCurve(to: p(160, 14), control1: p(154, 58), control2: p(162, 24))
        path.addCurve(to: p(148, 22), control1: p(158, 4), control2: p(148, 6))
        path.addCurve(to: p(150, 74), control1: p(148, 40), control2: p(146, 62))
        path.addCurve(to: p(170, 70), control1: p(153, 82), control2: p(162, 80))
        // o и хвостик
        path.addCurve(to: p(192, 52), control1: p(176, 60), control2: p(182, 52))
        path.addCurve(to: p(188, 80), control1: p(180, 52), control2: p(174, 78))
        path.addCurve(to: p(194, 52), control1: p(202, 82), control2: p(206, 58))
        path.addCurve(to: p(222, 52), control1: p(200, 56), control2: p(210, 58))

        // Вписываем с сохранением пропорций и по центру рамки.
        let canvas = Self.canvas
        let scale = min(rect.width / canvas.width, rect.height / canvas.height)
        let offsetX = rect.midX - canvas.midX * scale
        let offsetY = rect.midY - canvas.midY * scale
        return path.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: offsetX, ty: offsetY))
    }
}

// MARK: - Громкость

/// Что видно на чёлке, пока меняют громкость: слева динамик и «Sound», справа уровень.
/// Середину закрывает физическая чёлка, поэтому всё живёт в крыльях.
struct NotchVolumeHUDView: View {

    @ObservedObject var volume: NotchVolume
    let notchHeight: CGFloat

    /// Сколько раз значок дёрнулся — каждое выключение звука запускает тряску заново.
    @State private var shakes = 0

    private var level: CGFloat { volume.isMuted ? 0 : CGFloat(volume.level) }
    private var isSilent: Bool { volume.isMuted || volume.level == 0 }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    // Значок меняет ширину с числом волн — без рамки «Sound» прыгал бы.
                    .frame(width: 16, alignment: .leading)
                    // Звук выключили — значок коротко дёргается влево-вправо.
                    .keyframeAnimator(initialValue: CGFloat(0), trigger: shakes) { content, offset in
                        content.offset(x: offset)
                    } keyframes: { _ in
                        LinearKeyframe(-3, duration: 0.04)
                        LinearKeyframe(3, duration: 0.06)
                        LinearKeyframe(-2.5, duration: 0.06)
                        LinearKeyframe(2, duration: 0.05)
                        LinearKeyframe(0, duration: 0.05)
                    }
                Text("Sound")
                    .font(.system(size: 11, weight: .semibold))
            }
            // Белый, пока звук есть; красный — когда выключен.
            .foregroundStyle(isSilent ? NotchConfig.volumeRed : Color.white)
            .animation(.easeOut(duration: 0.15), value: isSilent)
            .onChange(of: isSilent) { _, silent in
                if silent { shakes += 1 }
            }
            .onAppear {
                // Плашку могли вызвать самим выключением — тогда onChange уже не увидит перехода.
                if isSilent { shakes += 1 }
            }
            .frame(width: NotchConfig.volumeHUDWingWidth, alignment: .center)

            Spacer(minLength: 0)

            // Полоса шириной во всё правое крыло, минус поля — как и левое.
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25))
                    Capsule().fill(Color.white)
                        .frame(width: max(geometry.size.width * level, level > 0 ? 5 : 0))
                }
            }
            .frame(height: 5)
            .padding(.horizontal, 12)
            .frame(width: NotchConfig.volumeHUDWingWidth)
            .animation(.easeOut(duration: 0.12), value: level)
        }
        .frame(height: notchHeight)
    }

    private var symbol: String {
        if volume.isMuted || volume.level == 0 { return "speaker.slash.fill" }
        return volume.level < 0.33 ? "speaker.wave.1.fill"
            : volume.level < 0.66 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }
}
