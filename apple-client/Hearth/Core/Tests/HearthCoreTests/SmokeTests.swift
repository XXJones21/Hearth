//
//  SmokeTests.swift
//  HearthCoreTests
//
//  That the test target links the package at all. Worth its own file: every
//  later suite in here assumes a working `xcodebuild test` cycle, and when
//  that cycle breaks it is nearly always the target, not the assertion.
//

import XCTest
@testable import HearthCore

final class SmokeTests: XCTestCase {
    func testPackageLinks() {
        XCTAssertEqual(HearthState.IDLE, HearthState.IDLE)
    }
}
