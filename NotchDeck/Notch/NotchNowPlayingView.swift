import SwiftUI

/// Что видно на расширенной чёлке, пока жива сессия плеера: слева обложка, справа
/// эквалайзер. Середину закрывает физическая чёлка, поэтому содержимое живёт
/// только по краям — в «крыльях».
struct NotchNowPlayingView: View {

    @ObservedObject var media: NotchMedia
    /// Высота чёлки: по ней выравниваем содержимое, чтобы шло вровень с меню-баром.
    let notchHeight: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            artwork
            Spacer(minLength: 0)
            NotchEqualizerView(color: media.accent, isPlaying: media.isPlaying)
        }
        .padding(.horizontal, NotchConfig.mediaWingPadding)
        .frame(height: notchHeight)
    }

    /// Обложка сохраняет свои пропорции: у альбома она квадратная, у видео широкая,
    /// и вписывать превью в квадрат значило бы срезать ему бока.
    private var artworkSize: CGSize {
        let side = NotchConfig.mediaArtworkHeight(notchHeight: notchHeight)
        guard let size = media.artwork?.size, size.width > 0, size.height > 0 else {
            return CGSize(width: side, height: side)
        }

        let aspect = min(max(size.width / size.height, 0.7), NotchConfig.mediaArtworkMaxAspect)
        return CGSize(width: (side * aspect).rounded(), height: side)
    }

    private var artwork: some View {
        let size = artworkSize

        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.white.opacity(0.12))
            .frame(width: size.width, height: size.height)
            .overlay {
                if let image = media.artwork {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        // Без явной рамки после aspectRatio вьюха раздаётся больше
                        // предложенного размера, и обрезка идёт уже по раздутой — картинка
                        // вылезала за края.
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    // У видео в браузере обложки часто нет — тогда просто цветной значок.
                    Image(systemName: "play.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(media.accent)
                }
            }
    }
}

/// Четыре столбика, которые «дышат».
///
/// Это не индикатор громкости — уровень звука нам никто не отдаёт. Столбики просто
/// показывают, что воспроизведение идёт, поэтому их периоды и сдвиги заданы вручную
/// и намеренно разные: с одинаковыми они шагали бы в ногу и выглядели бы механически.
///
/// Высоты считаются от часов, а не от переключения состояния с `repeatForever`.
/// В той схеме бесконечная анимация держалась на единственной смене флага в `onAppear`:
/// стоило любой перерисовке или `withAnimation` на общем предке её погасить — и столбики
/// замирали навсегда, потому что флаг больше не менялся и запускать анимацию заново
/// было нечем. Здесь состояния нет вовсе: есть время — есть движение.
struct NotchEqualizerView: View {

    let color: Color
    let isPlaying: Bool

    private let low: [CGFloat] = [3, 5, 3, 4]
    private let high: [CGFloat] = [11, 8, 13, 9]
    /// Полный цикл каждого столбика. Числа взаимно непериодичные, чтобы рисунок
    /// не повторялся на глазах.
    private let periods: [Double] = [0.84, 1.10, 0.72, 0.96]
    /// Сдвиг фазы: без него все четыре стартовали бы из одной точки.
    private let phases: [Double] = [0, 0.35, 0.7, 1.05]
    /// На паузе столбики замирают на одной высоте: разнобой без движения читался бы
    /// как поломка, а ровный ряд — как остановленное воспроизведение.
    private let paused: CGFloat = 4

    var body: some View {
        // paused: на паузе таймлайн не будит вьюху вовсе и тактов не жжёт.
        TimelineView(.animation(paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            HStack(alignment: .center, spacing: 2.5) {
                ForEach(low.indices, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: height(index, at: time))
                }
            }
            .frame(height: 14)
            .opacity(isPlaying ? 1 : 0.5)
            .animation(.easeOut(duration: 0.2), value: isPlaying)
        }
    }

    private func height(_ index: Int, at time: Double) -> CGFloat {
        guard isPlaying else { return paused }

        let phase = (time / periods[index] + phases[index]) * 2 * .pi
        // sin даёт -1...1, а нам нужна доля 0...1 между низом и верхом столбика.
        let fraction = CGFloat((sin(phase) + 1) / 2)
        return low[index] + (high[index] - low[index]) * fraction
    }
}
