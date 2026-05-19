import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            PlayerPopoverView()
        }
        .frame(minWidth: 360, minHeight: 400)
    }
}
