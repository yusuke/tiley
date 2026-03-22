import SwiftUI

/// Renders the desktop wallpaper as a background, matching macOS display modes
/// (Fill, Fit, Stretch, Center, Tile).
struct DesktopPictureBackgroundView: View {
    let nsImage: NSImage
    let info: MainWindowView.DesktopPictureInfo
    let size: CGSize

    var body: some View {
        desktopPictureView(nsImage: nsImage, info: info, size: size)
    }

    /// Returns the frame size for a Fill-mode image that fully covers the area with no gaps.
    private func fillFrameSize(image: CGSize, grid: CGSize) -> CGSize {
        let imgW = image.width
        let imgH = max(1, image.height)
        let scaleX = grid.width / imgW
        let scaleY = grid.height / imgH
        let scale = max(scaleX, scaleY)
        return CGSize(width: imgW * scale, height: imgH * scale)
    }

    // MARK: - Desktop picture rendering

    @ViewBuilder
    private func desktopPictureView(nsImage: NSImage, info: MainWindowView.DesktopPictureInfo, size: CGSize) -> some View {
        let scalingValue = info.scaling
        let allowClipping = info.allowClipping
        let bg = info.fillColor ?? Color.black

        // Tile: macOS renders tiles at 1 image pixel = 1 physical pixel.
        // Scale down by ratio of composite width to screen width.
        if info.isTiled {
            let imagePixelSize = info.originalImageSize ?? nsImage.size
            let tilePtOnScreen = CGSize(
                width: imagePixelSize.width / info.screenScale,
                height: imagePixelSize.height / info.screenScale
            )
            let gridScale = info.screenSize.width > 0 ? size.width / info.screenSize.width : 1.0
            let tileSize = CGSize(
                width: tilePtOnScreen.width * gridScale,
                height: tilePtOnScreen.height * gridScale
            )
            Canvas { ctx, canvasSize in
                guard let resolvedImage = ctx.resolveSymbol(id: 0) else { return }
                let startY = canvasSize.height.truncatingRemainder(dividingBy: tileSize.height)
                var x: CGFloat = 0
                while x < canvasSize.width {
                    var y: CGFloat = startY - tileSize.height
                    while y < canvasSize.height {
                        ctx.draw(resolvedImage, in: CGRect(origin: CGPoint(x: x, y: y), size: tileSize))
                        y += tileSize.height
                    }
                    x += tileSize.width
                }
            } symbols: {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: tileSize.width, height: tileSize.height)
                    .tag(0)
            }
            .frame(width: size.width, height: size.height)

        // scaleAxesIndependently (= 1): stretch to fill
        } else if scalingValue == NSImageScaling.scaleAxesIndependently.rawValue {
            Image(nsImage: nsImage)
                .resizable(resizingMode: .stretch)
                .frame(width: size.width, height: size.height)

        // scaleNone (= 2): center at 1:1 physical pixel ratio, with fill color background
        } else if scalingValue == NSImageScaling.scaleNone.rawValue {
            let gridScale = info.screenSize.width > 0 ? size.width / info.screenSize.width : 1.0
            let imagePixelSize = info.originalImageSize ?? nsImage.size
            let displaySize = CGSize(
                width: imagePixelSize.width / info.screenScale * gridScale,
                height: imagePixelSize.height / info.screenScale * gridScale
            )
            ZStack {
                bg.frame(width: size.width, height: size.height)
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: displaySize.width, height: displaySize.height)
            }
            .frame(width: size.width, height: size.height)

        // scaleProportionallyUpOrDown (= 3): fill (clipping=true) or fit (clipping=false)
        } else if allowClipping {
            let fillSize = fillFrameSize(image: nsImage.size, grid: size)
            Image(nsImage: nsImage)
                .resizable()
                .frame(width: fillSize.width, height: fillSize.height)
                .frame(width: size.width, height: size.height, alignment: .center)
                .clipped()
        } else {
            let imageSize = info.originalImageSize ?? nsImage.size
            let imageAspect = imageSize.width / max(1, imageSize.height)
            let gridAspect = size.width / max(1, size.height)
            if imageAspect >= gridAspect {
                let fitHeight = size.width / imageAspect
                ZStack {
                    bg.frame(width: size.width, height: size.height)
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: size.width, height: fitHeight)
                }
            } else {
                let fitWidth = size.height * imageAspect
                ZStack {
                    bg.frame(width: size.width, height: size.height)
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: fitWidth, height: size.height)
                }
            }
        }
    }
}
