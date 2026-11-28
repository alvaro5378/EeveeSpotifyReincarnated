import SwiftUI

struct HomeSettingsView: View {
    @State private var hidden = Set(UserDefaults.homeHidden)
    @State private var recommendationsHidden = UserDefaults.homeRecommendationsHidden

    private static let rows: [(HomePart, String, Color)] = [
        (.pills, "rectangle.3.group.fill", .blue),
        (.shortcuts, "square.grid.2x2.fill", .purple),
        (.promos, "megaphone.fill", .orange),
        (.previews, "play.square.stack.fill", .pink),
        (.dj, "waveform", .green),
    ]

    var body: some View {
        List {
            Section(header: Text("home_hide".localized), footer: Text("restart_is_required_description".localized)) {
                ForEach(Self.rows, id: \.0) { part, icon, color in
                    toggle(part, icon: icon, color: color)
                }
            }

            Section(footer: Text("home_episode_carousels_footer".localized)) {
                toggle(.episodeCarousels, icon: "mic.fill", color: Color(hex: "#30B0C7"))
            }

            Section(footer: Text("home_recommendations_footer".localized)) {
                SettingsToggle(title: "home_recommendations".localized, icon: "rectangle.stack.badge.minus", color: .blue,
                               isOn: $recommendationsHidden)
            }

            SettingsResetSection(visible: !hidden.isEmpty || recommendationsHidden) {
                hidden = []
                recommendationsHidden = false
            }

            RestartSection(visible: hidden != HomeDeclutter.launchHidden || recommendationsHidden != HomeFeedResponses.enabled)

            SpacerView()
        }
        .eeveeSettingsStyle()
        .onChange(of: hidden) { UserDefaults.homeHidden = HomePart.allCases.filter($0.contains) }
        .onChange(of: recommendationsHidden) { UserDefaults.homeRecommendationsHidden = $0 }
    }

    private func toggle(_ part: HomePart, icon: String, color: Color) -> some View {
        SettingsToggle(title: "home_\(part.rawValue)".localized, icon: icon, color: color, isOn: Binding(
            get: { hidden.contains(part) },
            set: { if $0 { hidden.insert(part) } else { hidden.remove(part) } }
        ))
    }
}
