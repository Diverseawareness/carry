import SwiftUI

@MainActor
struct ShareCardRenderer {
    /// Renders a ResultsShareCard to a UIImage at 2x scale (retina).
    static func render(data: ShareCardData, theme: ShareCardTheme = .dark) -> UIImage? {
        let view = ResultsShareCard(data: data, theme: theme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        return renderer.uiImage
    }
}
