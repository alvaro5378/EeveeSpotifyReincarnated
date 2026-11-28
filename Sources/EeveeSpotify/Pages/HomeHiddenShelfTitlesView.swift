import SwiftUI

struct HomeHiddenShelfTitlesView: View {
    @Binding var titles: [String]
    @State private var newTitle = ""

    var body: some View {
        List {
            Section(header: Text("home_hidden_shelf_titles".localized), footer: Text("home_hidden_shelf_titles_footer".localized)) {
                ForEach(titles, id: \.self) { title in Text(title) }
                    .onDelete { titles.remove(atOffsets: $0) }
            }
            Section {
                TextField("home_hidden_shelf_placeholder".localized, text: $newTitle)
                    .disableAutocorrection(true)
                Button("home_hidden_shelf_add".localized) {
                    titles = HomeShelfPolicy.sanitizedTitles(titles + [newTitle])
                    newTitle = ""
                }
                .disabled(HomeShelfPolicy.normalize(newTitle).isEmpty || titles.count >= 64)
            }
            Section {
                Button("home_hidden_shelf_defaults".localized) { titles = HomeShelfPolicy.defaultHiddenTitles }
            }
            SpacerView()
        }
        .eeveeSettingsStyle()
    }
}
