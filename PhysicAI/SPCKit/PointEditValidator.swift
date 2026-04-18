// PointEditValidator.swift
// SPCKit
//
// Pure validation functions for point-level edits.
// All functions are synchronous (no I/O) and can be called on any actor.
// Returns ValidationResult rather than throwing so the UI can display
// inline error messages without try/catch ceremony.

import Foundation

// MARK: - ValidationResult

nonisolated public enum ValidationResult: Sendable {
    case valid
    case warning(String)   // allowed but user should be informed
    case error(String)     // must be rejected; do not apply the edit
}

// MARK: - PointEditValidator

nonisolated public enum PointEditValidator {

    // MARK: X validation

    /// Validates setting xPoints[index] = newValue within the given array.
    /// - Parameters:
    ///   - xPoints: The current full X array (already resolved; not nil).
    ///   - index: The point index being changed.
    ///   - newValue: The proposed new X value.
    ///   - fileType: The current file type (used to warn about Y-only promotion).
    public static func validateXEdit(
        xPoints: [Float],
        index: Int,
        newValue: Float,
        fileType: SPCFileType
    ) -> ValidationResult {

        // Range check
        guard index >= 0, index < xPoints.count else {
            return .error("Index \(index) is out of range (0…\(xPoints.count - 1)).")
        }

        // IEEE 754 finite check
        guard newValue.isFinite else {
            return .error("X value must be a finite number (not NaN or Inf).")
        }

        // Monotonicity check
        var proposed = xPoints
        proposed[index] = newValue

        let ascending = proposed.first.flatMap { first in proposed.last.map { $0 >= first } } ?? true

        if ascending {
            for i in 1 ..< proposed.count {
                if proposed[i] < proposed[i - 1] {
                    return .error(
                        "Setting X[\(index)] = \(newValue) breaks ascending order " +
                        "(X[\(i-1)] = \(proposed[i-1]), X[\(i)] = \(proposed[i]))."
                    )
                }
            }
        } else {
            for i in 1 ..< proposed.count {
                if proposed[i] > proposed[i - 1] {
                    return .error(
                        "Setting X[\(index)] = \(newValue) breaks descending order " +
                        "(X[\(i-1)] = \(proposed[i-1]), X[\(i)] = \(proposed[i]))."
                    )
                }
            }
        }

        // Warn if editing X on a Y-only file (will promote to XY on save)
        if fileType == .yOnly {
            return .warning(
                "Editing X values in a Y-only file will promote it to XY format on save. " +
                "The file size will increase because X values will be stored explicitly."
            )
        }

        return .valid
    }

    // MARK: Y validation

    /// Validates setting yPoints[index] = newValue.
    public static func validateYEdit(
        yPoints: [Float],
        index: Int,
        newValue: Float,
        yExponent: UInt8
    ) -> ValidationResult {

        guard index >= 0, index < yPoints.count else {
            return .error("Index \(index) is out of range (0…\(yPoints.count - 1)).")
        }

        guard newValue.isFinite else {
            return .error("Y value must be a finite number.")
        }

        // If the file uses 16-bit Y storage (not float), check representable range.
        // yExponent != 0x80 means fixed-point. FloatY = (2^exp * IntY) / 2^16
        if yExponent != 0x80 {
            let exp = Double(Int8(bitPattern: yExponent))
            let scale = pow(2.0, exp) / pow(2.0, 16.0)
            let maxRepresentable = Float(scale * Double(Int16.max))
            let minRepresentable = Float(scale * Double(Int16.min))
            if newValue > maxRepresentable || newValue < minRepresentable {
                return .warning(
                    "Value \(newValue) may be outside the representable range " +
                    "[\(minRepresentable), \(maxRepresentable)] for 16-bit Y storage. " +
                    "SPCKit always writes IEEE 754 float Y, so the value will be preserved."
                )
            }
        }

        return .valid
    }

    // MARK: Scale factor validation

    /// Validates a user-supplied scale factor before applying a ScaleTransform.
    public static func validateScaleFactor(_ factor: Double, axis: EditAxis) -> ValidationResult {
        guard factor.isFinite else {
            return .error("Scale factor must be a finite number.")
        }
        if factor == 0 {
            return .error("Scale factor of 0 would set all \(axis) values to zero.")
        }
        if factor < 0 {
            return .warning(
                "Negative scale factor will reverse the \(axis) axis direction. " +
                "For X axis this changes the data orientation and may cause compatibility issues."
            )
        }
        if abs(factor) < 1e-6 || abs(factor) > 1e6 {
            return .warning(
                "Scale factor \(factor) is extreme and may cause loss of float precision."
            )
        }
        return .valid
    }

    // MARK: Expression validation

    /// Validates and compiles an expression string. Returns the compiled
    /// expression if valid so the UI can cache it without re-parsing.
    public static func validateExpression(
        _ expression: String,
        axis: EditAxis
    ) -> (result: ValidationResult, compiled: CompiledExpression?) {
        do {
            let compiled = try ExpressionParser.compile(expression)
            // Quick smoke test with neutral values
            _ = try compiled.evaluate(x: 1.0, y: 1.0)
            return (.valid, compiled)
        } catch let error as TransformError {
            return (.error(error.localizedDescription), nil)
        } catch {
            return (.error(error.localizedDescription), nil)
        }
    }

    // MARK: Offset validation

    public static func validateOffset(_ offset: Double, axis: EditAxis) -> ValidationResult {
        guard offset.isFinite else {
            return .error("Offset must be a finite number.")
        }
        if offset == 0 {
            return .warning("Offset of 0 has no effect.")
        }
        return .valid
    }

    // MARK: Clamp range validation

    public static func validateClampRange(min: Float, max: Float) -> ValidationResult {
        guard min.isFinite, max.isFinite else {
            return .error("Clamp bounds must be finite numbers.")
        }
        if min >= max {
            return .error("Min (\(min)) must be less than max (\(max)).")
        }
        return .valid
    }
}
