import SwiftUI

struct HomeHiddenShelfTitlesView: View {
    @Binding var titles: [String]
    @State private var newTitle = ""

    var body: some View {
        List {
            Section(header: Text("home_hidden_shelf_titles".localized), footer: Text("home_hidden_shelf_titles_footer".localized)) {
                ForEach(titles, id: \.self) { title in Text(title) }
                    .onDelete {
                        var updated = titles
                        updated.remove(atOffsets: $0)
                        save(updated)
                    }
            }
            Section {
                TextField("home_hidden_shelf_placeholder".localized, text: $newTitle)
                    .disableAutocorrection(true)
                Button("home_hidden_shelf_add".localized) {
                    save(titles + [newTitle])
                    newTitle = ""
                }
                .disabled(HomeShelfPolicy.normalize(newTitle).isEmpty || titles.count >= 64)
            }
            Section {
                Button("home_hidden_shelf_defaults".localized) { save(HomeShelfPolicy.defaultHiddenTitles) }
            }
            SpacerView()
        }
        .eeveeSettingsStyle()
    }

    private func save(_ values: [String]) {
        let updated = HomeShelfPolicy.sanitizedTitles(values)
        // Save here as well as updating the parent binding: the parent page
        // is offscreen, and Spotify may be closed directly from this editor.
        UserDefaults.homeHiddenShelfTitles = updated
        titles = updated
    }
}
