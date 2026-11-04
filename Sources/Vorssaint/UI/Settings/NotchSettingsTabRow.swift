// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

enum NotchSettingsTab: Int, CaseIterable, Identifiable {
    case overview, layout, displays, content, shortcuts, activity, notifications, behavior, routing, privacy
    var id: Int { rawValue }
    var symbol: String {
        ["square.grid.2x2", "paintbrush", "display.2", "rectangle.stack", "circle.grid.cross", "livephoto", "bell", "hand.point.up.left", "arrow.triangle.branch", "lock.shield"][rawValue]
    }
    func title(_ language: AppLanguage) -> String {
        // Task labels are deliberately distinct from the island's page names.
        let labels: [AppLanguage: String] = [
            .enUS: "Overview|Appearance|Displays|Pages & controls|Extensions|Live activities|Notifications|Interaction|Routing|Privacy & lock screen",
            .ptBR: "Visão geral|Aparência|Telas|Páginas e controles|Extensões|Atividades ao vivo|Notificações|Interação|Destinos|Privacidade e bloqueio",
            .tr: "Genel bakış|Görünüm|Ekranlar|Sayfalar ve denetimler|Uzantılar|Canlı etkinlikler|Bildirimler|Etkileşim|Yönlendirme|Gizlilik ve kilit ekranı",
            .ru: "Обзор|Оформление|Дисплеи|Страницы и управление|Расширения|Текущие действия|Уведомления|Взаимодействие|Назначения|Приватность и блокировка",
            .es: "Resumen|Apariencia|Pantallas|Páginas y controles|Extensiones|Actividades en directo|Notificaciones|Interacción|Destinos|Privacidad y bloqueo",
            .sk: "Prehľad|Vzhľad|Displeje|Stránky a ovládanie|Rozšírenia|Živé aktivity|Hlásenia|Interakcia|Smerovanie|Súkromie a zámok",
            .de: "Übersicht|Darstellung|Displays|Seiten und Steuerung|Erweiterungen|Live-Aktivitäten|Mitteilungen|Interaktion|Ziele|Datenschutz und Sperre",
            .fr: "Vue d’ensemble|Apparence|Écrans|Pages et commandes|Extensions|Activités en direct|Notifications|Interaction|Destinations|Confidentialité et verrouillage",
            .it: "Panoramica|Aspetto|Schermi|Pagine e controlli|Estensioni|Attività in tempo reale|Notifiche|Interazione|Destinazioni|Privacy e blocco",
            .ja: "概要|外観|ディスプレイ|ページとコントロール|拡張機能|ライブアクティビティ|通知|操作|表示先|プライバシーとロック",
            .ko: "개요|모양|디스플레이|페이지 및 제어|확장|실시간 활동|알림|상호작용|표시 위치|개인정보 및 잠금",
            .uk: "Огляд|Оформлення|Дисплеї|Сторінки й керування|Розширення|Поточні дії|Сповіщення|Взаємодія|Призначення|Приватність і блокування",
            .zhHans: "概览|外观|显示器|页面与控制|扩展|实时活动|通知|交互|显示位置|隐私与锁屏",
            .zhTW: "概覽|外觀|顯示器|頁面與控制|擴充功能|即時活動|通知|互動|顯示位置|隱私與鎖定畫面",
            .zhHK: "概覽|外觀|顯示器|頁面與控制|擴充功能|即時活動|通知|互動|顯示位置|私隱與鎖定畫面"
        ]
        return (labels[language] ?? labels[.enUS]!).components(separatedBy: "|")[rawValue]
    }
    func detail(_ language: AppLanguage) -> String {
        let descriptions: [AppLanguage: String] = [
            .enUS: "Make the island your own. Start with a task below.|Size, materials and outline.|Choose screens, shapes and visibility.|Choose pages, arrange controls and configure features.|Add and arrange buttons to the left, right and below.|Choose what stays visible while you work.|Choose alerts and system feedback.|How the island opens, closes and responds.|Choose what opens in the island or a separate window.|Screen capture, lock-screen visibility and sounds.",
            .ptBR: "Personalize a ilha. Comece por uma tarefa abaixo.|Tamanho, materiais e contorno.|Escolha telas, formas e visibilidade.|Escolha páginas, organize controles e configure recursos.|Adicione e organize botões à esquerda, à direita e abaixo.|Escolha o que fica visível enquanto você trabalha.|Escolha alertas e respostas do sistema.|Como a ilha abre, fecha e responde.|Escolha o que abre na ilha ou em outra janela.|Captura de tela, visibilidade no bloqueio e sons.",
            .tr: "Adayı kişiselleştirin. Aşağıdan bir görev seçin.|Boyut, malzemeler ve kenarlık.|Ekranları, şekilleri ve görünürlüğü seçin.|Sayfaları seçin, denetimleri düzenleyin ve özellikleri yapılandırın.|Sola, sağa ve alta düğmeler ekleyip düzenleyin.|Çalışırken nelerin görünür kalacağını seçin.|Uyarıları ve sistem geri bildirimini seçin.|Adanın açılması, kapanması ve tepki vermesi.|Nelerin adada veya ayrı pencerede açılacağını seçin.|Ekran yakalama, kilit ekranı görünürlüğü ve sesler.",
            .ru: "Настройте остров. Выберите задачу ниже.|Размер, материалы и контур.|Экраны, формы и видимость.|Выбор страниц, порядок элементов и настройка функций.|Добавление и порядок кнопок слева, справа и снизу.|Что остаётся видимым во время работы.|Уведомления и отклик системы.|Как остров открывается, закрывается и реагирует.|Что открывается в острове или отдельном окне.|Захват экрана, видимость при блокировке и звуки.",
            .es: "Personaliza la isla. Elige una tarea abajo.|Tamaño, materiales y contorno.|Elige pantallas, formas y visibilidad.|Elige páginas, ordena controles y configura funciones.|Añade y ordena botones a la izquierda, derecha y debajo.|Elige qué permanece visible mientras trabajas.|Elige avisos y respuestas del sistema.|Cómo se abre, se cierra y responde la isla.|Elige qué se abre en la isla o en otra ventana.|Captura de pantalla, visibilidad al bloquear y sonidos.",
            .sk: "Prispôsobte si ostrov. Vyberte úlohu nižšie.|Veľkosť, materiály a obrys.|Vyberte displeje, tvary a viditeľnosť.|Vyberte stránky, usporiadajte ovládanie a nastavte funkcie.|Pridajte a usporiadajte tlačidlá vľavo, vpravo a dole.|Vyberte, čo zostane viditeľné pri práci.|Vyberte upozornenia a odozvu systému.|Ako sa ostrov otvára, zatvára a reaguje.|Vyberte, čo sa otvorí v ostrove alebo inom okne.|Snímanie obrazovky, viditeľnosť pri zamknutí a zvuky.",
            .de: "Gestalte die Insel. Wähle unten eine Aufgabe.|Größe, Materialien und Umriss.|Displays, Formen und Sichtbarkeit wählen.|Seiten wählen, Steuerung anordnen und Funktionen einrichten.|Tasten links, rechts und unten hinzufügen und anordnen.|Wählen, was während der Arbeit sichtbar bleibt.|Hinweise und Systemrückmeldungen wählen.|Wie die Insel öffnet, schließt und reagiert.|Wählen, was in der Insel oder einem eigenen Fenster öffnet.|Bildschirmaufnahme, Sichtbarkeit bei Sperre und Töne.",
            .fr: "Personnalisez l’îlot. Choisissez une tâche ci-dessous.|Taille, matériaux et contour.|Choisissez les écrans, les formes et la visibilité.|Choisissez les pages, organisez les commandes et réglez les fonctions.|Ajoutez et organisez les boutons à gauche, à droite et en dessous.|Choisissez ce qui reste visible pendant votre travail.|Choisissez les alertes et les retours du système.|Comment l’îlot s’ouvre, se ferme et réagit.|Choisissez ce qui s’ouvre dans l’îlot ou une autre fenêtre.|Capture d’écran, visibilité au verrouillage et sons.",
            .it: "Personalizza l’isola. Scegli un’attività qui sotto.|Dimensioni, materiali e contorno.|Scegli schermi, forme e visibilità.|Scegli pagine, ordina controlli e configura funzioni.|Aggiungi e ordina pulsanti a sinistra, a destra e sotto.|Scegli cosa resta visibile mentre lavori.|Scegli avvisi e risposte del sistema.|Come l’isola si apre, si chiude e risponde.|Scegli cosa si apre nell’isola o in una finestra separata.|Cattura schermo, visibilità al blocco e suoni.",
            .ja: "アイランドをカスタマイズ。下から項目を選択してください。|サイズ、素材、輪郭。|画面、形状、表示方法を選択。|ページの選択、コントロールの配置、機能の設定。|左右と下にボタンを追加して配置。|作業中に表示し続ける内容を選択。|通知とシステムのフィードバックを選択。|開閉方法と操作への反応。|アイランド内または別ウィンドウに開く内容を選択。|画面キャプチャ、ロック画面での表示とサウンド。",
            .ko: "아일랜드를 꾸며보세요. 아래에서 작업을 선택하세요.|크기, 소재 및 윤곽선.|화면, 모양 및 표시 여부 선택.|페이지 선택, 제어 배치 및 기능 설정.|왼쪽, 오른쪽 및 아래에 버튼 추가 및 배치.|작업 중 계속 표시할 항목 선택.|알림 및 시스템 피드백 선택.|아일랜드의 열기, 닫기 및 반응 방식.|아일랜드 또는 별도 창에서 열 항목 선택.|화면 캡처, 잠금 화면 표시 및 소리.",
            .uk: "Налаштуйте острів. Виберіть завдання нижче.|Розмір, матеріали й контур.|Екрани, форми та видимість.|Вибір сторінок, порядок елементів і налаштування функцій.|Додавання й порядок кнопок ліворуч, праворуч і знизу.|Що залишається видимим під час роботи.|Сповіщення й відгук системи.|Як острів відкривається, закривається та реагує.|Що відкривається в острові або окремому вікні.|Захоплення екрана, видимість при блокуванні та звуки.",
            .zhHans: "定制你的灵动岛。从下方选择一项任务。|大小、材质和轮廓。|选择屏幕、形状和显示方式。|选择页面、排列控制项并配置功能。|在左侧、右侧和下方添加并排列按钮。|选择工作时持续显示的内容。|选择提醒和系统反馈。|灵动岛的打开、关闭和响应方式。|选择在灵动岛或独立窗口中打开的内容。|屏幕捕捉、锁屏显示和声音。",
            .zhTW: "自訂你的動態島。從下方選擇一項工作。|大小、材質和外框。|選擇螢幕、形狀和顯示方式。|選擇頁面、排列控制項並設定功能。|在左側、右側和下方新增並排列按鈕。|選擇工作時持續顯示的內容。|選擇提示和系統回饋。|動態島的開啟、關閉和回應方式。|選擇在動態島或獨立視窗中開啟的內容。|螢幕擷取、鎖定畫面顯示和聲音。",
            .zhHK: "自訂你的動態島。從下方選擇一項工作。|大小、材質和外框。|選擇螢幕、形狀和顯示方式。|選擇頁面、排列控制項並設定功能。|在左側、右側和下方新增並排列按鈕。|選擇工作時持續顯示的內容。|選擇提示和系統回饋。|動態島的開啟、關閉和回應方式。|選擇在動態島或獨立視窗中開啟的內容。|螢幕擷取、鎖定畫面顯示和聲音。"
        ]
        return (descriptions[language] ?? descriptions[.enUS]!).components(separatedBy: "|")[rawValue]
    }

    func matches(_ query: String, language: AppLanguage) -> Bool {
        let terms = ["start customize overview", "size width height glass background translucent outline compact spacious camera capsule fit",
                     "monitor display screen physical notch pill full screen hide resolution", "page control center module music timer calendar clipboard downloads agents camera watch dictation",
                     "extension shortcut button left right bottom position rename reorder add", "resting idle pause playing music live activity",
                     "notification alert banner volume brightness battery microphone feedback track accessory capture clipboard",
                     "hover click activation delay gesture haptic open reopen home", "destination route separate window quick panel tools shelf captures scratchpad",
                     "privacy screenshot recording lock screen sound capture"]
        let editor = FeatureStrings.notchEditor(language)
        let text = FeatureStrings.notch(language)
        let localized: [String]
        switch self {
        case .overview: localized = []
        case .layout: localized = [text.size, text.width, text.maximumHeight, text.translucentBackground, text.showOutline, text.compact, text.spacious, text.custom]
        case .displays: localized = [text.allDisplays, text.builtIn, text.mainDisplay, text.followPointer, text.hideInFullscreen, text.cameraFit, text.capsuleFit, editor.hiddenUntilHover]
        case .content: localized = NotchModule.allCases.map { $0.title(language) }
        case .shortcuts: localized = [editor.addButton, editor.buttonName, editor.position, editor.bottom, editor.reorderHint]
        case .activity: localized = [text.music, text.battery, text.playingMusic, text.coverMenus, FeatureStrings.notchMusicExtras(language).pauseTimeout]
        case .notifications: localized = [text.volume, text.brightness, text.battery, text.newTrack, text.captureActivity, FeatureStrings.notchNotifications(language).hideSystemBanner]
        case .behavior: localized = [editor.opening, editor.clickOpen, editor.hoverPreview, editor.hoverExpand, editor.activationTime, editor.reopening, text.hapticFeedback, FeatureStrings.notchGestures(language).title]
        case .routing: localized = [editor.destinations, editor.hideMenuBarIcon, text.files, text.tools, text.panel]
        case .privacy: localized = [editor.privacy, text.showInCaptures, FeatureStrings.notchLockScreen(language).title]
        }
        let haystack = (title(language) + " " + detail(language) + " " + localized.joined(separator: " ") + " " + terms[rawValue]).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return query.split(whereSeparator: \.isWhitespace).allSatisfy {
            haystack.contains(String($0).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil))
        }
    }
}

/// A small set of user decisions, with specialist editors inside each area.
enum NotchSettingsWorkspace: Int, CaseIterable, Identifiable {
    case overview, design, content, activity, behavior, privacy
    var id: Int { rawValue }
    var sections: [NotchSettingsTab] {
        switch self {
        case .overview: return [.overview]
        case .design: return [.displays, .layout]
        case .content: return [.content, .shortcuts]
        case .activity: return [.activity, .notifications]
        case .behavior: return [.behavior, .routing]
        case .privacy: return [.privacy]
        }
    }
    static func containing(_ section: NotchSettingsTab) -> Self {
        allCases.first { $0.sections.contains(section) } ?? .overview
    }
    var symbol: String { sections[0].symbol }
    func title(_ language: AppLanguage) -> String {
        if language == .enUS {
            return ["Quick setup", "Design & displays", "Content & buttons", "Activities & alerts", "Behavior", "Privacy"][rawValue]
        }
        return sections[0].title(language)
    }
}

/// A single shared style makes the entire padded label a hit target, including
/// otherwise transparent space. Used for navigation, cards and choices.
struct NotchSettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The disclosure's whole header is a button, rather than only its chevron.
/// Applying this to the settings root also covers nested feature editors.
struct NotchSettingsDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    configuration.label
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(NotchSettingsButtonStyle())
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded {
                configuration.content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NotchSettingsNavigationButton: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                .padding(.horizontal, 10)
                .background(selected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(NotchSettingsButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Compact menu retained for callers that need a single navigation control.
struct NotchSettingsTabRow: View {
    @Binding var tab: NotchSettingsTab
    let language: AppLanguage
    let canOpen: Bool
    var showsOpenButton = true
    let open: () -> Void
    var body: some View {
        HStack {
            Menu {
                ForEach(NotchSettingsWorkspace.allCases) { group in
                    Section(group.title(language)) {
                        ForEach(group.sections) { section in
                            Button(section.title(language)) { tab = section }
                        }
                    }
                }
            } label: {
                Label(tab.title(language), systemImage: tab.symbol)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8).contentShape(Rectangle())
            }.menuStyle(.borderlessButton)
            if showsOpenButton {
                Button(action: open) { Image(systemName: "arrow.up.forward.app") }
                    .disabled(!canOpen).accessibilityLabel(FeatureStrings.notch(language).open)
            }
        }
    }
}
