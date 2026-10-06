import SwiftUI
import AppKit

let pageSize = CGSize(width: 595, height: 842)   // A4

struct Page<C: View>: View {
    let number: Int, total: Int
    @ViewBuilder let content: C

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            Spacer(minLength: 0)
            HStack {
                Text("NotchDeck").font(docFont(8)).foregroundStyle(Color(white: 0.65))
                Spacer()
                Text("\(number) / \(total)").font(docFont(8)).foregroundStyle(Color(white: 0.65))
            }
        }
        .padding(.horizontal, 40).padding(.top, 42).padding(.bottom, 26)
        .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

/// Заголовок раздела с картинкой и списком того, как он работает.
struct Block<C: View>: View {
    let title: String, note: String, lines: [String]
    let shotHeight: CGFloat
    @ViewBuilder let shotContent: C

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            heading(title)
            sub(note)
            shot(height: shotHeight) { shotContent }
                .scaleEffect(0.92, anchor: .topLeading)
                .frame(width: 514 * 0.92, height: (shotHeight + 24) * 0.92, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 3) { ForEach(lines, id: \.self) { bullet($0) } }
        }
    }
}

let total = 5

let page1 = Page(number: 1, total: total) {
    VStack(alignment: .leading, spacing: 0) {
        Text("NotchDeck").font(docFont(34, .bold)).foregroundStyle(ink)
        Text("Панель под чёлкой MacBook").font(docFont(14)).foregroundStyle(dim).padding(.top, 2)

        Text("Пять разделов под рукой: плеер, поиск, скриншоты, буфер обмена, переводчик.\nПриложение живёт в меню-баре — без окна. При запуске из чёлки спускается «hello».")
            .font(docFont(12)).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
            .padding(.top, 16)

        heading("Как открыть").padding(.top, 26)
        VStack(alignment: .leading, spacing: 3) {
            bullet("Наведите курсор на чёлку — она **подрастёт**, показывая, что вас заметили.")
            bullet("Задержите курсор на **полсекунды** — панель раскроется.")
            bullet("Разделы переключаются **наведением** на значок слева — нажимать не нужно.")
            bullet("Уведите мышь — панель закроется сама.")
        }.padding(.top, 6)

        VStack(alignment: .leading, spacing: 10) {
            ForEach([("обычная", CGFloat(179), CGFloat(32), false),
                     ("под курсором", 224, 37, false),
                     ("играет музыка", 287, 32, true)], id: \.0) { item in
                HStack(spacing: 12) {
                    Text(item.0).font(docFont(9)).foregroundStyle(dim)
                        .frame(width: 96, alignment: .trailing)
                    ZStack(alignment: .top) {
                        NotchShape(topRadius: 8, bottomRadius: 10).fill(Color.black)
                            .frame(width: item.1, height: item.2)
                            .overlay(alignment: .top) {
                                if item.3 {
                                    HStack(spacing: 0) {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(LinearGradient(colors: [Color(red: 0.9, green: 0.4, blue: 0.35), Color(red: 0.35, green: 0.35, blue: 0.75)],
                                                                 startPoint: .leading, endPoint: .trailing))
                                            .frame(width: 36, height: 20)
                                        Spacer(minLength: 0)
                                        HStack(spacing: 2.5) {
                                            ForEach([11.0, 8.0, 13.0, 9.0], id: \.self) { h in
                                                Capsule().fill(Color(red: 0.85, green: 0.38, blue: 0.45)).frame(width: 2.5, height: h)
                                            }
                                        }
                                    }.padding(.horizontal, 9).frame(height: 32)
                                }
                            }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.top, 18)

        sub("Пока играет музыка или видео, чёлка расширяется: слева обложка, справа эквалайзер\nв цвет обложки. На паузе столбики замирают — или чёлка сужается, если так выбрано в настройках.\nКлавиши громкости тоже показывают уровень прямо на чёлке, вместо системного индикатора.")
            .padding(.top, 12)

        heading("Что нужно знать").padding(.top, 26)
        VStack(alignment: .leading, spacing: 3) {
            bullet("**Скриншотам** нужен доступ к папке со снимками — система спросит его сама.")
            bullet("**Плееру** нужен /usr/bin/perl: с macOS 15.4 сведения о воспроизведении система отдаёт только процессам, подписанным Apple, и приложение спрашивает их через него.")
            bullet("**Переводчик** работает на системных языковых моделях Apple, без интернета. Сеть нужна только вариантам и примерам.")
            bullet("**Громкости на чёлке** нужен «Универсальный доступ»: только так можно перехватить клавиши громкости и не показывать системный индикатор.")
        }.padding(.top, 6)
    }
}

let page2 = Page(number: 2, total: total) {
    VStack(alignment: .leading, spacing: 7) {
        heading("Верхняя полоса")
        sub("Живёт рядом с чёлкой и видна из любого раздела. Слева — где вы сейчас, справа — состояние машины.")
        MockStrip(section: "Плеер").clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)).padding(.vertical, 4)
        VStack(alignment: .leading, spacing: 3) {
            bullet("**Wi-Fi** — синий, когда сеть включена; серый перечёркнутый, когда выключена. Нажатие открывает раздел Wi-Fi в настройках.")
            bullet("**Bluetooth** — открывает свой раздел настроек.")
            bullet("**Шестерёнка** — открывает Системные настройки.")
            bullet("**Заряд** — цвет означает состояние, а не уровень: проценты и так написаны цифрами.")
        }

        heading("Цвета заряда").padding(.top, 14)
        VStack(alignment: .leading, spacing: 5) {
            ForEach([("на зарядке или от сети", "зелёный, рядом появляется молния", Color.green),
                     ("ниже 20%", "красный", Color.red),
                     ("включено энергосбережение", "оранжевый", Color.orange),
                     ("от 20 до 44%", "жёлтый", Color.yellow),
                     ("45% и выше", "нейтральный серый", Color(white: 0.45))], id: \.0) { row in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(row.2).frame(width: 26, height: 10)
                    Text(row.0).font(docFont(11, .medium)).foregroundStyle(ink).frame(width: 190, alignment: .leading)
                    Text(row.1).font(docFont(11)).foregroundStyle(dim)
                }
            }
        }
        sub("Порядок важен: питание важнее всего, тревога важнее режима, уровень — в последнюю очередь.\nПоэтому на 8% с включённой экономией значок красный, а на зарядке зелёный даже при 12%.")
            .padding(.top, 8)
    }
}

let page3 = Page(number: 3, total: total) {
    VStack(alignment: .leading, spacing: 22) {
        Block(title: "Плеер", note: "Показывает то, что играет в системе: Музыку, Spotify, видео в браузере.",
              lines: ["Обложка слева, справа название и исполнитель. Если источник не назвал трек — покажет само приложение, например «Arc».",
                      "Кнопки назад, пауза и вперёд, под ними перемотка: **потяните кружок**, чтобы перемотать.",
                      "**Сердечко** (у видео — палец вверх) отмечает трек в самом плеере. Появляется, только если плеер это умеет.",
                      "Справа — **громкость** системы: потяните полосу, нажмите на динамик, чтобы выключить звук."],
              shotHeight: 166) { MockPlayer() }

        Block(title: "Поиск", note: "Запрос уходит в Google в браузере по умолчанию.",
              lines: ["Наберите запрос и нажмите **Enter** или лупу.",
                      "Панель закроется сама, а строка очистится."],
              shotHeight: 100) { MockSearch() }
    }
}

let page4 = Page(number: 4, total: total) {
    VStack(alignment: .leading, spacing: 22) {
        Block(title: "Скриншоты", note: "Последние снимки экрана, свежие сверху. Синяя папка у заголовка открывает их в Finder.",
              lines: ["**Клик** — снимок копируется в буфер, рамка мигает зелёным.",
                      "**Перетаскивание** — файл уходит прямо в письмо, чат или папку.",
                      "**Стрелка** открывает снимок, **крестик** отправляет его в Корзину.",
                      "Правая кнопка: показать в Finder или открыть."],
              shotHeight: 190) { MockShots() }

        Block(title: "Буфер обмена", note: "История того, что копировалось.",
              lines: ["**Клик по записи** возвращает её в буфер.",
                      "Закреплённые записи не вытесняются новыми.",
                      "**Поиск** внизу вытягивает панель и ищет по всей истории.",
                      "**Очистить** рядом убирает всё, кроме закреплённого."],
              shotHeight: 152) { MockClipboard() }
    }
}

let page5 = Page(number: 5, total: total) {
    VStack(alignment: .leading, spacing: 22) {
        Block(title: "Переводчик", note: "Русский и английский, обе стороны.",
              lines: ["Слева оригинал, справа перевод — язык определяется сам, по тому, как вы пишете.",
                      "Недописанное слово подсказывается бледным текстом — **Tab** дописывает его.",
                      "**Звёздочка** сохраняет перевод в избранное, иконка внизу копирует его.",
                      "**История**, **Избранное** и **Варианты и примеры** внизу вытягивают панель вниз."],
              shotHeight: 166) { MockTranslator() }

        VStack(alignment: .leading, spacing: 7) {
            heading("Мелочи, которые пригодятся")
            VStack(alignment: .leading, spacing: 3) {
                bullet("Панель не закрывается, пока вы печатаете в поиске или переводчике, — даже если курсор ушёл.")
                bullet("Название раздела всегда написано слева в верхней полосе: значки слева без подписей, но подсказка появляется при наведении.")
                bullet("Всё, что делает панель, обратимо: снимки уходят в Корзину, буфер чистится только по кнопке.")
                bullet("**Настройки** — шестерёнка последней строкой в списке разделов, под прокруткой: плеер на паузе, приветствие при запуске, громкость на чёлке.")
            }
        }
    }
}

// MARK: - Сборка PDF

MainActor.assumeIsolated {
    let url = URL(fileURLWithPath: "/Users/sergeia.i./NotchDeck/Docs/NotchDeck.pdf")
    var box = CGRect(origin: .zero, size: pageSize)
    guard let consumer = CGDataConsumer(url: url as CFURL),
          let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
        print("не удалось создать PDF"); exit(1)
    }

    @MainActor func add<C: View>(_ page: C) {
        let renderer = ImageRenderer(content: page)
        renderer.render { size, draw in
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
        }
    }

    add(page1); add(page2); add(page3); add(page4); add(page5)
    context.closePDF()
    print("готово: \(url.path)")
}
