import CoreGraphics

struct ModuleTabLayout: Equatable {
    static let hitSize: CGFloat = 24
    static let preferredSpacing: CGFloat = 4
    static let forbiddenGap: CGFloat = 8

    let shapeWidth: CGFloat
    let notchHeight: CGFloat
    let leftFlank: CGRect
    let rightFlank: CGRect
    let leftCount: Int
    let rightCount: Int
    let leftSpacing: CGFloat
    let rightSpacing: CGFloat
    let frames: [CGRect]
    let pillFrames: [CGRect]
    let gearFrame: CGRect
    let usesIconFallback: Bool

    init(
        shapeWidth: CGFloat,
        geometry: NotchGeometry,
        moduleCount: Int,
        hitSize: CGFloat = ModuleTabLayout.hitSize,
        spacing: CGFloat = ModuleTabLayout.preferredSpacing,
        gap: CGFloat = ModuleTabLayout.forbiddenGap
    ) {
        let count = max(0, moduleCount)
        let width = max(0, shapeWidth)
        let notchHeight = max(0, geometry.notchRect.height)
        let flanks = geometry.topBandFlanks(inShapeSpace: width)
        let y = max(0, (notchHeight - hitSize) / 2)

        self.shapeWidth = width
        self.notchHeight = notchHeight
        self.leftFlank = flanks.left
        self.rightFlank = flanks.right

        guard count > 0 else {
            self.leftCount = 0
            self.rightCount = 0
            self.leftSpacing = spacing
            self.rightSpacing = spacing
            self.frames = []
            self.pillFrames = []
            self.gearFrame = .zero
            self.usesIconFallback = true
            return
        }

        if geometry.isPhysicalNotch {
            let leftCount = (count + 1) / 2
            let rightCount = count - leftCount
            let leftSpacing = Self.fittedSpacing(
                count: leftCount,
                available: flanks.left.width,
                hitSize: hitSize,
                preferred: spacing,
                gap: gap
            )
            let rightSpacing = Self.fittedSpacing(
                count: rightCount,
                available: flanks.right.width,
                hitSize: hitSize,
                preferred: spacing,
                gap: gap
            )
            let leftWidth = Self.groupWidth(
                count: leftCount,
                hitSize: hitSize,
                spacing: leftSpacing
            )
            let rightWidth = Self.groupWidth(
                count: rightCount,
                hitSize: hitSize,
                spacing: rightSpacing
            )
            let leftStart = max(flanks.left.minX, flanks.left.maxX - gap - leftWidth)
            let rightStart = max(0, min(width - rightWidth, flanks.right.minX + gap))

            var frames: [CGRect] = []
            for index in 0..<leftCount {
                frames.append(
                    CGRect(
                        x: leftStart + CGFloat(index) * (hitSize + leftSpacing),
                        y: y,
                        width: hitSize,
                        height: hitSize
                    )
                )
            }
            for index in 0..<rightCount {
                frames.append(
                    CGRect(
                        x: rightStart + CGFloat(index) * (hitSize + rightSpacing),
                        y: y,
                        width: hitSize,
                        height: hitSize
                    )
                )
            }

            self.leftCount = leftCount
            self.rightCount = rightCount
            self.leftSpacing = leftSpacing
            self.rightSpacing = rightSpacing
            self.frames = frames
            self.pillFrames = frames
            self.gearFrame = .zero
            self.usesIconFallback = true
            return
        }

        let available = min(width, geometry.notchRect.width)
        let centeredSpacing = Self.fittedSpacing(
            count: count,
            available: available,
            hitSize: hitSize,
            preferred: spacing,
            gap: 0
        )
        let groupWidth = Self.groupWidth(
            count: count,
            hitSize: hitSize,
            spacing: centeredSpacing
        )
        let start = max(0, (width - groupWidth) / 2)
        self.leftCount = count
        self.rightCount = 0
        self.leftSpacing = centeredSpacing
        self.rightSpacing = centeredSpacing
        self.frames = (0..<count).map { index in
            CGRect(
                x: start + CGFloat(index) * (hitSize + centeredSpacing),
                y: y,
                width: hitSize,
                height: hitSize
            )
        }
        self.pillFrames = frames
        self.gearFrame = .zero
        self.usesIconFallback = true
    }

    init(pillWidths: [CGFloat], shapeWidth: CGFloat, geometry: NotchGeometry) {
        let width = max(0, shapeWidth)
        let notchHeight = max(0, geometry.notchRect.height)
        let forbidden = geometry.forbiddenZone(inShapeSpace: width)
        let gearSize: CGFloat = 20
        let gearX = max(0, width - 12 - gearSize)
        let y = max(0, (notchHeight - TabPillMetrics.height) / 2)

        self.shapeWidth = width
        self.notchHeight = notchHeight
        self.leftFlank = geometry.topBandFlanks(inShapeSpace: width).left
        self.rightFlank = geometry.topBandFlanks(inShapeSpace: width).right
        self.leftCount = pillWidths.count
        self.rightCount = 0
        self.leftSpacing = TabPillMetrics.spacing
        self.rightSpacing = TabPillMetrics.spacing
        self.gearFrame = CGRect(x: gearX, y: y, width: gearSize, height: gearSize)

        let labeledWidth = Self.groupWidth(widths: pillWidths)
        let notchLeft = forbidden.minX + 6
        let rightLimit = min(gearX - 6, notchLeft)
        if 9 + labeledWidth <= rightLimit + 0.0001 {
            self.pillFrames = Self.frames(
                widths: pillWidths,
                startX: 9,
                spacing: TabPillMetrics.spacing,
                y: y,
                height: TabPillMetrics.height
            )
            self.frames = self.pillFrames
            self.usesIconFallback = false
        } else {
            let iconWidths = pillWidths.map { _ in gearSize }
            let available = max(0, rightLimit - 9)
            let iconTotal = iconWidths.reduce(0, +)
            let count = max(1, iconWidths.count - 1)
            let spacing = min(
                TabPillMetrics.spacing,
                max(0, (available - iconTotal) / CGFloat(count))
            )
            self.pillFrames = Self.frames(
                widths: iconWidths,
                startX: 9,
                spacing: spacing,
                y: y,
                height: TabPillMetrics.height
            )
            self.frames = self.pillFrames
            self.usesIconFallback = true
        }
    }

    private static func frames(widths: [CGFloat], startX: CGFloat, spacing: CGFloat, y: CGFloat, height: CGFloat) -> [CGRect] {
        var x = startX
        return widths.map { width in
            defer { x += width + spacing }
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }

    private static func groupWidth(widths: [CGFloat]) -> CGFloat {
        guard !widths.isEmpty else { return 0 }
        return widths.reduce(0, +) + CGFloat(widths.count - 1) * TabPillMetrics.spacing
    }

    private static func fittedSpacing(
        count: Int,
        available: CGFloat,
        hitSize: CGFloat,
        preferred: CGFloat,
        gap: CGFloat
    ) -> CGFloat {
        guard count > 0 else { return preferred }
        var candidate = max(0, preferred)
        while candidate > 0 {
            let total = CGFloat(count) * hitSize
                + CGFloat(count - 1) * candidate
                + gap
            if total <= available + 0.0001 {
                return candidate
            }
            candidate = max(0, candidate - 1)
        }
        return 0
    }

    private static func groupWidth(count: Int, hitSize: CGFloat, spacing: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * hitSize + CGFloat(count - 1) * spacing
    }
}
