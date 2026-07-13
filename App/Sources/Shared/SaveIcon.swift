import SwiftUI

/// Save action icon. Uses the system symbol so stroke weight matches neighboring
/// toolbar icons (`xmark`, `doc.on.doc`, `pin`, …) at every Dynamic Type / scale.
struct SaveIcon: View {
    var body: some View {
        Image(systemName: "square.and.arrow.down")
    }
}
