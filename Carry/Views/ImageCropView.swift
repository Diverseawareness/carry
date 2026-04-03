import SwiftUI

struct ImageCropView: View {
    let image: UIImage
    var onSave: (UIImage) -> Void
    var onCancel: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let circleInset: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            let circleDiameter = geo.size.width - circleInset * 2

            ZStack {
                Color.bgSecondary.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Title
                    Text("Crop")
                        .font(.carry.headlineBold)
                        .foregroundColor(Color.textPrimary)
                        .padding(.top, 16)

                    Spacer()

                    // Image + circle mask area
                    ZStack {
                        // The draggable/zoomable image
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: circleDiameter * scale, height: circleDiameter * scale)
                            .offset(offset)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                        clampOffset(circleDiameter: circleDiameter)
                                    }
                            )
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let newScale = lastScale * value
                                        scale = min(max(newScale, 1.0), 5.0)
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                        clampOffset(circleDiameter: circleDiameter)
                                    }
                            )

                        // Dark overlay with circle cutout
                        CropOverlay(circleDiameter: circleDiameter)
                            .fill(style: FillStyle(eoFill: true))
                            .foregroundColor(Color.black.opacity(0.5))
                            .allowsHitTesting(false)

                        // Circle border
                        Circle()
                            .strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5)
                            .frame(width: circleDiameter, height: circleDiameter)
                            .allowsHitTesting(false)
                    }
                    .frame(width: geo.size.width, height: geo.size.width)
                    .clipped()

                    Spacer()

                    // Bottom buttons
                    HStack(spacing: 12) {
                        Button {
                            onCancel()
                        } label: {
                            Text("Cancel")
                                .font(.carry.headline)
                                .foregroundColor(Color.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(Color.borderSubtle, lineWidth: 1.5)
                                )
                        }

                        Button {
                            let cropped = cropImage(circleDiameter: circleDiameter)
                            onSave(cropped)
                        } label: {
                            Text("Save")
                                .font(.carry.headlineBold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.textPrimary))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 50)
                }
            }
        }
    }

    // MARK: - Clamp offset so image can't leave the circle

    private func clampOffset(circleDiameter: CGFloat) {
        let imageSize = circleDiameter * scale
        let maxOffset = (imageSize - circleDiameter) / 2

        withAnimation(.easeOut(duration: 0.2)) {
            offset.width = min(max(offset.width, -maxOffset), maxOffset)
            offset.height = min(max(offset.height, -maxOffset), maxOffset)
        }
        lastOffset = offset
    }

    // MARK: - Crop the visible circle region

    private func cropImage(circleDiameter: CGFloat) -> UIImage {
        let imageSize = circleDiameter * scale

        // The visible circle center is at the center of the image frame.
        // offset moves the image, so the crop region relative to the image is the inverse.
        let centerX = imageSize / 2 - offset.width
        let centerY = imageSize / 2 - offset.height

        // Map from display coordinates to actual image pixels
        let imgW = CGFloat(image.size.width)
        let imgH = CGFloat(image.size.height)

        // scaledToFill: the image fills `imageSize x imageSize`
        let displayScale = max(imageSize / imgW, imageSize / imgH)
        let displayW = imgW * displayScale
        let displayH = imgH * displayScale

        // Offset of the image origin within the frame (centered)
        let originX = (imageSize - displayW) / 2
        let originY = (imageSize - displayH) / 2

        // Circle region in display space → image pixel space
        let cropDisplayX = centerX - circleDiameter / 2 - originX
        let cropDisplayY = centerY - circleDiameter / 2 - originY

        let pixelScale = 1.0 / displayScale
        let cropRect = CGRect(
            x: cropDisplayX * pixelScale,
            y: cropDisplayY * pixelScale,
            width: circleDiameter * pixelScale,
            height: circleDiameter * pixelScale
        )

        // Render square crop at output resolution
        let outputSize: CGFloat = 600
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSize, height: outputSize))
        return renderer.image { ctx in
            // Draw the source image portion into the output square
            let drawRect = CGRect(
                x: -cropRect.origin.x * (outputSize / cropRect.width),
                y: -cropRect.origin.y * (outputSize / cropRect.height),
                width: imgW * (outputSize / cropRect.width),
                height: imgH * (outputSize / cropRect.height)
            )
            image.draw(in: drawRect)
        }
    }
}

// MARK: - Circle cutout overlay shape

private struct CropOverlay: Shape {
    let circleDiameter: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addEllipse(in: CGRect(
            x: rect.midX - circleDiameter / 2,
            y: rect.midY - circleDiameter / 2,
            width: circleDiameter,
            height: circleDiameter
        ))
        return path
    }
}
