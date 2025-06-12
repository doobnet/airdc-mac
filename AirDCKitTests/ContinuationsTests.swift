@testable import AirDCKit
import Foundation
import XCTest

class ContinuationsTests: XCTestCase {
    let continuations = DefaultContinuations()

    func unknownId(_ id: Continuations.ID) -> Continuations.ID {
        id == Continuations.ID.max ? id - 1 : id + 1
    }

    func testResumeContinuationReturning() async throws {
        let data = "data".data(using: .utf8)!

        let result = try await withCheckedThrowingContinuation {
            let id = continuations.append($0)
            let _ = continuations.resumeContinuation(
                withId: id, returning: data
            )
        }

        XCTAssertEqual(result, data)
    }

    func testResumeContinuationReturningWithUnkownId() async throws {
        let data = "data".data(using: .utf8)!

        let _ = try await withCheckedThrowingContinuation {
            let id = continuations.append($0)
            let found = continuations.resumeContinuation(
                withId: unknownId(id), returning: data
            )
            XCTAssertFalse(found)

            let _ = continuations.resumeContinuation(
                withId: id, returning: data
            )
        }
    }

    func testResumeContinuationThrowing() async throws {
        struct Error: Swift.Error {}

        try await assertThrowsAsyncError(await withCheckedThrowingContinuation(
            {
                let id = continuations.append($0)
                _ = continuations.resumeContinuation(
                    withId: id, throwing: Error()
                )
            }
        ))
    }

    func testResumeContinuationThrowingWithUnkownId() async throws {
        struct Error: Swift.Error {}

        try await assertThrowsAsyncError(await withCheckedThrowingContinuation(
            {
                let id = continuations.append($0)
                let found = continuations.resumeContinuation(
                    withId: unknownId(id), throwing: Error()
                )
                XCTAssertFalse(found)

                _ = continuations.resumeContinuation(
                    withId: id, throwing: Error()
                )
            }
        ))
    }
}

/// Asserts that an asynchronous expression throws an error.
/// (Intended to function as a drop-in asynchronous version of `XCTAssertThrowsError`.)
///
/// Example usage:
///
///     await assertThrowsAsyncError(
///         try await sut.function()
///     ) { error in
///         XCTAssertEqual(error as? MyError, MyError.specificError)
///     }
///
/// - Parameters:
///   - expression: An asynchronous expression that can throw an error.
///   - message: An optional description of a failure.
///   - file: The file where the failure occurs.
///     The default is the filename of the test case where you call this function.
///   - line: The line number where the failure occurs.
///     The default is the line number where you call this function.
///   - errorHandler: An optional handler for errors that expression throws.
func assertThrowsAsyncError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (_ error: Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        // expected error to be thrown, but it was not
        let customMessage = message()
        if customMessage.isEmpty {
            XCTFail("Asynchronous call did not throw an error.", file: file, line: line)
        } else {
            XCTFail(customMessage, file: file, line: line)
        }
    } catch {
        errorHandler(error)
    }
}
