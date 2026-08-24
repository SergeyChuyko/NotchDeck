import SwiftUI

/// Раздел «Плеер»: обложка по центру, под ней название, полоса перемотки и кнопки.
/// Показывает то, что играет в системе, — хоть трек в Музыке, хоть видео в браузере.
struct NotchMediaView: View {

    @ObservedObject var media: NotchMedia
    @ObservedObject var controller: NotchController

    /// Какая из трёх кнопок под курсором.
    @State private var hoveredControl: Int?
    /// Позиция, которую пользователь тащит прямо сейчас. Пока она есть, время и полоса
    /// показывают её, а не то, что приходит от плеера, — иначе ползунок дёргался бы.
    @State private var scrubbing: TimeInterval?

    var body: some View {
        Group {
            if let failure = media.failure {
                message(failure, tint: .orange)
            } else if let track = media.track {
                player(track)
            } else {
                message("Ничего не играет. Включите музыку или видео — раздел подхватит их сам.",
                        tint: .secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func message(_ text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)

            refreshButton
        }
    }

    /// Плеер иногда молчит: браузер не прислал метаданные, уведомление потерялось.
    /// Эта кнопка переспрашивает систему, не трогая само воспроизведение. Живёт только
    /// в пустом состоянии — там от неё есть толк; над играющим треком обновлять нечего.
    private var refreshButton: some View {
        control(index: 3, name: "arrow.triangle.2.circlepath", size: 11) {
            media.reload()
        }
        .help("Обновить плеер")
    }

    // MARK: - Плеер

    private func player(_ track: NotchMedia.Track) -> some View {
        GeometryReader { geometry in
            VStack(spacing: 6) {
                artwork(fitting: geometry.size)
                titles(track)

                Spacer(minLength: 0)

                if track.duration > 0 {
                    progress(track)
                }

                controls
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Заголовок и подпись под ним. Названия может не быть вовсе — видео в браузере часто
    /// не публикует ни его, ни исполнителя. Тогда показываем сам источник: «Arc», «Telegram».
    private func captions(_ track: NotchMedia.Track) -> (title: String, subtitle: String) {
        if track.title.isEmpty {
            return (track.application.isEmpty ? "Идёт воспроизведение" : track.application, "")
        }
        return (track.title, track.artist.isEmpty ? track.application : track.artist)
    }

    /// Одна строка на название и одна на исполнителя: в столбик места по высоте мало,
    /// а название видео бывает длиной в абзац — в две строки оно съедало бы обложку.
    private func titles(_ track: NotchMedia.Track) -> some View {
        let captions = captions(track)

        return VStack(spacing: 1) {
            Text(captions.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            if !captions.subtitle.isEmpty {
                Text(captions.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity)
    }

    /// Пропорции самой картинки: у альбомов обложка квадратная, у видео — широкая.
    /// Крайности зажимаем, чтобы совсем узкая или длинная не перекосила раздел.
    private var artworkAspect: CGFloat {
        guard let size = media.artwork?.size, size.width > 0, size.height > 0 else { return 1 }
        return min(max(size.width / size.height, 0.6), 2.2)
    }

    /// Размер считаем сами, а не через `.aspectRatio` с `maxWidth`/`maxHeight`:
    /// такая рамка занимает весь отведённый прямоугольник целиком, и картинка в оверлее
    /// снова растягивается на него — ровно тот случай, когда широкое превью резалось в квадрат.
    private func artworkSize(fitting available: CGSize) -> CGSize {
        // Всё остальное теперь стоит под обложкой, а не сбоку: название с исполнителем,
        // полоса и кнопки. Их высоту вычитаем первой — им место нужнее.
        let reserved: CGFloat = 92
        let maxHeight = min(96, max(36, available.height - reserved))
        // По ширине обложка ограничена слабее: широкое превью видео тут не мешает,
        // но растянуться на весь раздел ему тоже незачем.
        let maxWidth = available.width * 0.6
        let aspect = artworkAspect

        let width = min(maxWidth, maxHeight * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    private func artwork(fitting available: CGSize) -> some View {
        let size = artworkSize(fitting: available)

        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .frame(width: size.width, height: size.height)
            .overlay {
                if let image = media.artwork {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Image(systemName: "play.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .animation(.easeInOut(duration: 0.2), value: artworkAspect)
    }

    /// Мост присылает позицию редко, поэтому между его сообщениями досчитываем её сами.
    /// Время по краям полосы, а не строкой под ней: в столбик высота на счету,
    /// и отдельная строка отняла бы её у обложки.
    private func progress(_ track: NotchMedia.Track) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let position = scrubbing ?? media.position(at: context.date)
            let fraction = min(max(position / track.duration, 0), 1)

            HStack(spacing: 8) {
                timeCode(position)
                seekBar(track, fraction: fraction)
                timeCode(track.duration)
            }
            .frame(maxWidth: 380)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 14)
    }

    /// Полоса перемотки. Своя, а не системный Slider: окно панели никогда не активно,
    /// и готовые элементы управления в нём ведут себя ненадёжно.
    private func seekBar(_ track: NotchMedia.Track, fraction: CGFloat) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(Color.primary.opacity(scrubbing == nil ? 0.5 : 0.8))
                    .frame(width: width * fraction)

                // Кружок появляется только на перемотке — иначе он лишний шум.
                if scrubbing != nil {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 8, height: 8)
                        .offset(x: width * fraction - 4)
                }
            }
            .frame(height: 3)
            // Полоса тонкая, попасть в неё курсором тяжело — ловим на всю высоту строки.
            .frame(height: 14)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Пока тянут, панель не должна закрыться, даже если курсор
                        // соскользнёт с её края.
                        controller.setInteractionLocked(true)
                        scrubbing = position(at: value.location.x, width: width, of: track)
                    }
                    .onEnded { value in
                        media.seek(to: position(at: value.location.x, width: width, of: track))
                        scrubbing = nil
                        controller.setInteractionLocked(false)
                    }
            )
        }
        .frame(height: 14)
    }

    private func position(at x: CGFloat, width: CGFloat, of track: NotchMedia.Track) -> TimeInterval {
        guard width > 0 else { return 0 }
        return min(max(x / width, 0), 1) * track.duration
    }

    private func timeCode(_ time: TimeInterval) -> some View {
        Text(Self.timeCode(time))
            .font(.system(size: 9))
            // Без этого подписи дёргаются по ширине на каждой секунде.
            .monospacedDigit()
            .foregroundStyle(.secondary)
            // Полоса тянется, подписи — нет: иначе они отъедали бы у неё ширину.
            .fixedSize()
    }

    /// Часы показываем только когда они есть: у трека это «3:41», у длинного видео «2:12:45».
    private static func timeCode(_ time: TimeInterval) -> String {
        let total = Int(time.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60

        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Кнопки

    private var controls: some View {
        HStack(spacing: 14) {
            control(index: 0, name: "backward.fill", size: 12) { media.previousTrack() }
            control(index: 1, name: media.isPlaying ? "pause.fill" : "play.fill", size: 15) {
                media.togglePlayPause()
            }
            control(index: 2, name: "forward.fill", size: 12) { media.nextTrack() }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func control(index: Int, name: String, size: CGFloat,
                         action: @escaping () -> Void) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .medium))
            .frame(width: size + 16, height: size + 16)
            .background {
                Circle().fill(Color.primary.opacity(hoveredControl == index ? 0.12 : 0))
            }
            .contentShape(Circle())
            .onHover { hovering in
                hoveredControl = hovering ? index : (hoveredControl == index ? nil : hoveredControl)
            }
            .onTapGesture(perform: action)
    }
}
