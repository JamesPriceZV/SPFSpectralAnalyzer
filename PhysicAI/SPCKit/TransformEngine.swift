// TransformEngine.swift
// SPCKit
//
// Actor that executes all bulk and point-level transforms.
// Uses Accelerate (vDSP) for vectorised float math on background threads.
// Returns Sendable TransformResult values — never holds shared mutable state.

import Accelerate
@preconcurrency import Foundation

// MARK: - TransformEngine

public actor TransformEngine {

    // Shared singleton. Actors serialise access automatically.
    public static let shared = TransformEngine()
    private init() {}

    // MARK: - Entry point

    /// Dispatch an EditAction and return the resulting SubfileDeltas.
    /// Throws TransformError on validation failures.
    public func execute(
        _ action: EditAction,
        on session: EditSession
    ) async throws -> TransformResult {

        switch action {

        // MARK: Scale

        case let .scaleX(indices, factor):
            var result = TransformResult()
            for i in indices {
                let sub   = await session.resolvedSubfile(at: i)
                let delta = try await scaleX(subfile: sub, factor: Float(factor), source: session)
                result.deltas[i] = delta
            }
            return result

        case let .scaleY(indices, factor):
            var result = TransformResult()
            let sFile = await session.sourcefile()
            for i in indices {
                let sub   = await session.resolvedSubfile(at: i)
                let delta = scaleY(subfile: sub, factor: Float(factor),
                                   ffp: sFile.header.firstX, flp: sFile.header.lastX)
                result.deltas[i] = delta
            }
            return result

        case let .scaleXY(indices, xFactor, yFactor):
            var result = TransformResult()
            for i in indices {
                let sub   = await session.resolvedSubfile(at: i)
                let sFile = await session.sourcefile()
                let delta = try scaleXY(
                    subfile: sub,
                    xFactor: Float(xFactor),
                    yFactor: Float(yFactor),
                    fileType: sFile.fileType,
                    ffp: sFile.header.firstX,
                    flp: sFile.header.lastX
                )
                result.deltas[i] = delta
            }
            return result

        // MARK: Offset

        case let .offsetX(indices, offset):
            var result = TransformResult()
            for i in indices {
                let sub   = await session.resolvedSubfile(at: i)
                let sFile = await session.sourcefile()
                let delta = try offsetX(
                    subfile: sub,
                    offset: Float(offset),
                    fileType: sFile.fileType,
                    ffp: sFile.header.firstX,
                    flp: sFile.header.lastX
                )
                result.deltas[i] = delta
            }
            return result

        case let .offsetY(indices, offset):
            var result = TransformResult()
            let sFile = await session.sourcefile()
            for i in indices {
                let sub   = await session.resolvedSubfile(at: i)
                let delta = offsetY(subfile: sub, offset: Float(offset),
                                    ffp: sFile.header.firstX, flp: sFile.header.lastX)
                result.deltas[i] = delta
            }
            return result

        // MARK: Clamp

        case let .clampY(indices, minVal, maxVal):
            guard minVal < maxVal else {
                throw TransformError.invalidClampRange(min: minVal, max: maxVal)
            }
            var result = TransformResult()
            let sFile = await session.sourcefile()
            for i in indices {
                let sub   = await session.resolvedSubfile(at: i)
                let delta = clampY(subfile: sub, min: minVal, max: maxVal,
                                   ffp: sFile.header.firstX, flp: sFile.header.lastX)
                result.deltas[i] = delta
            }
            return result

        // MARK: Expression

        case let .applyExpression(indices, expression, axis):
            let compiled = try ExpressionParser.compile(expression)
            var result   = TransformResult()
            for i in indices {
                let sub   = await session.resolvedSubfile(at: i)
                let sFile = await session.sourcefile()
                let delta = try applyExpression(
                    compiled,
                    to: sub,
                    axis: axis,
                    fileType: sFile.fileType,
                    ffp: sFile.header.firstX,
                    flp: sFile.header.lastX
                )
                result.deltas[i] = delta
            }
            return result

        // MARK: Point edits

        case let .editXPoint(subfileIndex, pointIndex, newValue):
            let sub   = await session.resolvedSubfile(at: subfileIndex)
            let sFile = await session.sourcefile()
            let delta = try editXPoint(
                subfile: sub,
                at: pointIndex,
                newValue: newValue,
                fileType: sFile.fileType,
                ffp: sFile.header.firstX,
                flp: sFile.header.lastX
            )
            return TransformResult(deltas: [subfileIndex: delta])

        case let .editYPoint(subfileIndex, pointIndex, newValue):
            let sub   = await session.resolvedSubfile(at: subfileIndex)
            let delta = editYPoint(subfile: sub, at: pointIndex, newValue: newValue)
            return TransformResult(deltas: [subfileIndex: delta])

        case let .editXYPoint(subfileIndex, pointIndex, newX, newY):
            let sub   = await session.resolvedSubfile(at: subfileIndex)
            let sFile = await session.sourcefile()
            let delta = try editXYPoint(
                subfile: sub,
                at: pointIndex,
                newX: newX,
                newY: newY,
                fileType: sFile.fileType,
                ffp: sFile.header.firstX,
                flp: sFile.header.lastX
            )
            return TransformResult(deltas: [subfileIndex: delta])

        // MARK: Metadata

        case let .editMemo(newMemo):
            let trimmed = String(newMemo.prefix(130)) // header field limit
            return TransformResult(memo: trimmed)

        case let .editAxisLabel(axis, label):
            let trimmed = String(label.prefix(10)) // fits within 30-byte combined block
            return TransformResult(axisLabels: [axis: trimmed])

        // MARK: Header metadata edits

        case let .editExperimentType(val):
            return TransformResult(experimentType: val)

        case let .editAxisUnits(axis, code):
            return TransformResult(axisUnitCodes: [axis: code])

        case let .editZUnits(code):
            return TransformResult(zUnitsCode: code)

        case let .editResolution(val):
            return TransformResult(resolution: String(val.prefix(9)))

        case let .editSourceInstrument(val):
            return TransformResult(sourceInstrument: String(val.prefix(9)))

        case let .editMethodFile(val):
            return TransformResult(methodFile: String(val.prefix(48)))

        case let .editSubfileZ(idx, zStart, zEnd):
            return TransformResult(subfileZEdits: [idx: (zStart: zStart, zEnd: zEnd)])

        case let .editZIncrement(val):
            return TransformResult(zIncrement: val)

        case let .editConcentrationFactor(val):
            return TransformResult(concentrationFactor: val)

        case let .renameSubfile(idx, name):
            return TransformResult(subfileNames: [idx: name])

        // MARK: Subfile management

        case let .addSubfiles(subfiles):
            return TransformResult(addedSubfiles: subfiles)

        case let .removeSubfiles(indices):
            return TransformResult(removedIndices: Set(indices))

        case let .reorderSubfiles(newOrder):
            return TransformResult(newSubfileOrder: newOrder)
        }
    }

    // MARK: - Scale implementations

    private func scaleX(
        subfile: Subfile,
        factor: Float,
        source: EditSession
    ) async throws -> SubfileDelta {
        // For Y-only files the X array does not exist in storage;
        // we must materialise it, scale it, and promote to XY.
        let sFile   = await source.sourcefile()
        let xIn     = subfile.resolvedXPoints(ffp: sFile.header.firstX, flp: sFile.header.lastX)
        var xOut    = [Float](repeating: 0, count: xIn.count)
        vDSP_vsmul(xIn, 1, [factor], &xOut, 1, vDSP_Length(xIn.count))

        let newFirst = Double(xOut.first ?? Float(sFile.header.firstX))
        let newLast  = Double(xOut.last  ?? Float(sFile.header.lastX))

        return SubfileDelta(
            xPoints:      xOut,
            yPoints:      subfile.yPoints,
            firstX:       newFirst,
            lastX:        newLast,
            operationLog: ["scaleX(×\(factor))"]
        )
    }

    private func scaleY(subfile: Subfile, factor: Float, ffp: Double, flp: Double) -> SubfileDelta {
        var yOut = [Float](repeating: 0, count: subfile.yPoints.count)
        vDSP_vsmul(subfile.yPoints, 1, [factor], &yOut, 1, vDSP_Length(subfile.yPoints.count))
        return SubfileDelta(
            xPoints:      subfile.xPoints,
            yPoints:      yOut,
            firstX:       subfile.xPoints?.first.map(Double.init) ?? ffp,
            lastX:        subfile.xPoints?.last.map(Double.init) ?? flp,
            operationLog: ["scaleY(×\(factor))"]
        )
    }

    private func scaleXY(
        subfile: Subfile,
        xFactor: Float,
        yFactor: Float,
        fileType: SPCFileType,
        ffp: Double,
        flp: Double
    ) throws -> SubfileDelta {
        let xIn  = subfile.resolvedXPoints(ffp: ffp, flp: flp)
        var xOut = [Float](repeating: 0, count: xIn.count)
        var yOut = [Float](repeating: 0, count: subfile.yPoints.count)
        vDSP_vsmul(xIn,              1, [xFactor], &xOut, 1, vDSP_Length(xIn.count))
        vDSP_vsmul(subfile.yPoints,  1, [yFactor], &yOut, 1, vDSP_Length(subfile.yPoints.count))
        return SubfileDelta(
            xPoints:      xOut,
            yPoints:      yOut,
            firstX:       Double(xOut.first ?? Float(ffp)),
            lastX:        Double(xOut.last  ?? Float(flp)),
            operationLog: ["scaleX(×\(xFactor)) scaleY(×\(yFactor))"]
        )
    }

    // MARK: - Offset implementations

    private func offsetX(
        subfile: Subfile,
        offset: Float,
        fileType: SPCFileType,
        ffp: Double,
        flp: Double
    ) throws -> SubfileDelta {
        let xIn  = subfile.resolvedXPoints(ffp: ffp, flp: flp)
        var xOut = [Float](repeating: 0, count: xIn.count)
        vDSP_vsadd(xIn, 1, [offset], &xOut, 1, vDSP_Length(xIn.count))
        return SubfileDelta(
            xPoints:      xOut,
            yPoints:      subfile.yPoints,
            firstX:       Double(xOut.first ?? Float(ffp)),
            lastX:        Double(xOut.last  ?? Float(flp)),
            operationLog: ["offsetX(+\(offset))"]
        )
    }

    private func offsetY(subfile: Subfile, offset: Float, ffp: Double, flp: Double) -> SubfileDelta {
        var yOut = [Float](repeating: 0, count: subfile.yPoints.count)
        vDSP_vsadd(subfile.yPoints, 1, [offset], &yOut, 1, vDSP_Length(subfile.yPoints.count))
        return SubfileDelta(
            xPoints:      subfile.xPoints,
            yPoints:      yOut,
            firstX:       subfile.xPoints?.first.map(Double.init) ?? ffp,
            lastX:        subfile.xPoints?.last.map(Double.init) ?? flp,
            operationLog: ["offsetY(+\(offset))"]
        )
    }

    // MARK: - Clamp implementation

    private func clampY(subfile: Subfile, min: Float, max: Float, ffp: Double, flp: Double) -> SubfileDelta {
        var yOut = subfile.yPoints
        // vDSP_vclip clamps in-place between min and max
        vDSP_vclip(yOut, 1, [min], [max], &yOut, 1, vDSP_Length(yOut.count))
        return SubfileDelta(
            xPoints:      subfile.xPoints,
            yPoints:      yOut,
            firstX:       subfile.xPoints?.first.map(Double.init) ?? ffp,
            lastX:        subfile.xPoints?.last.map(Double.init) ?? flp,
            operationLog: ["clampY([\(min), \(max)])"]
        )
    }

    // MARK: - Expression implementation

    private func applyExpression(
        _ compiled: CompiledExpression,
        to subfile: Subfile,
        axis: EditAxis,
        fileType: SPCFileType,
        ffp: Double,
        flp: Double
    ) throws -> SubfileDelta {
        let count = subfile.yPoints.count
        let xIn   = subfile.resolvedXPoints(ffp: ffp, flp: flp)

        var newX = xIn
        var newY = subfile.yPoints

        for i in 0 ..< count {
            let xVal = Double(xIn[i])
            let yVal = Double(subfile.yPoints[i])
            switch axis {
            case .x:
                newX[i] = Float(try compiled.evaluate(x: xVal, y: yVal))
            case .y:
                newY[i] = Float(try compiled.evaluate(x: xVal, y: yVal))
            case .both:
                newX[i] = Float(try compiled.evaluate(x: xVal, y: yVal))
                newY[i] = Float(try compiled.evaluate(x: xVal, y: yVal))
            }
        }

        return SubfileDelta(
            xPoints:      newX,
            yPoints:      newY,
            firstX:       Double(newX.first ?? Float(ffp)),
            lastX:        Double(newX.last  ?? Float(flp)),
            operationLog: ["expression('\(compiled.source)' on \(axis))"]
        )
    }

    // MARK: - Point-level edits

    private func editXPoint(
        subfile: Subfile,
        at index: Int,
        newValue: Float,
        fileType: SPCFileType,
        ffp: Double,
        flp: Double
    ) throws -> SubfileDelta {
        guard index >= 0, index < subfile.pointCount else {
            throw TransformError.pointIndexOutOfRange(index: index, count: subfile.pointCount)
        }
        var xOut = subfile.resolvedXPoints(ffp: ffp, flp: flp)
        xOut[index] = newValue

        // Validate monotonicity (X must be non-decreasing or non-increasing).
        let ascending: Bool = {
            guard let first = xOut.first, let last = xOut.last else { return true }
            return last >= first
        }()
        if ascending {
            for i in 1 ..< xOut.count where xOut[i] < xOut[i - 1] {
                throw TransformError.xMonotonicityViolation(index: i, value: xOut[i], previous: xOut[i - 1])
            }
        }

        return SubfileDelta(
            xPoints:      xOut,
            yPoints:      subfile.yPoints,
            firstX:       Double(xOut.first ?? newValue),
            lastX:        Double(xOut.last  ?? newValue),
            operationLog: ["editX[\(index)]=\(newValue)"]
        )
    }

    private func editYPoint(
        subfile: Subfile,
        at index: Int,
        newValue: Float
    ) -> SubfileDelta {
        var yOut = subfile.yPoints
        yOut[index] = newValue
        return SubfileDelta(
            xPoints:      subfile.xPoints,
            yPoints:      yOut,
            firstX:       0,
            lastX:        0,
            operationLog: ["editY[\(index)]=\(newValue)"]
        )
    }

    private func editXYPoint(
        subfile: Subfile,
        at index: Int,
        newX: Float,
        newY: Float,
        fileType: SPCFileType,
        ffp: Double,
        flp: Double
    ) throws -> SubfileDelta {
        // Validate X then delegate to editXPoint for monotonicity check
        var delta = try editXPoint(
            subfile: subfile,
            at: index,
            newValue: newX,
            fileType: fileType,
            ffp: ffp,
            flp: flp
        )
        delta.yPoints[index] = newY
        delta.operationLog   = ["editXY[\(index)]=(\(newX),\(newY))"]
        return delta
    }
}

// MARK: - TransformError

nonisolated public enum TransformError: Error, LocalizedError {
    case pointIndexOutOfRange(index: Int, count: Int)
    case xMonotonicityViolation(index: Int, value: Float, previous: Float)
    case invalidClampRange(min: Float, max: Float)
    case expressionParseError(String)
    case expressionEvaluationError(String)
    case yOnlyXEditRequiresPromotion   // editing X on a Y-only file requires user confirmation

    public var errorDescription: String? {
        switch self {
        case let .pointIndexOutOfRange(i, n):
            return "Point index \(i) is out of range (file has \(n) points)."
        case let .xMonotonicityViolation(i, v, prev):
            return "Setting X[\(i)] = \(v) violates monotonicity (previous value \(prev))."
        case let .invalidClampRange(min, max):
            return "Clamp range invalid: min (\(min)) must be less than max (\(max))."
        case let .expressionParseError(msg):
            return "Expression parse error: \(msg)"
        case let .expressionEvaluationError(msg):
            return "Expression evaluation error: \(msg)"
        case .yOnlyXEditRequiresPromotion:
            return "Editing X values in a Y-only file will promote it to XY format. Confirm to continue."
        }
    }
}
