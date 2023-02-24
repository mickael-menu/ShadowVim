//
//  Copyright © 2023 Mickaël Menu
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation

@testable import Toolkit
import XCTest

final class VersionTests: XCTestCase {
    func testParseInvalidVersion() {
        XCTAssertNil(Version(rawValue: "invalid"))
        XCTAssertNil(Version(rawValue: "1.2.3.4"))
    }

    func testParseOnlyMajorVersion() {
        let version = Version(rawValue: "1")
        XCTAssertEqual(version, Version(major: 1, minor: 0, patch: 0))
    }

    func testParseOnlyMajorAndMinorVersions() {
        let version = Version(rawValue: "1.2")
        XCTAssertEqual(version, Version(major: 1, minor: 2, patch: 0))
    }

    func testParseAllVersions() {
        let version = Version(rawValue: "1.2.42")
        XCTAssertEqual(version, Version(major: 1, minor: 2, patch: 42))
    }

    func testParseWithPrereleaseTag() {
        let version = Version(rawValue: "1.2.3-beta")
        XCTAssertEqual(version, Version(major: 1, minor: 2, patch: 3))
    }

    func testCompareEqualVersions() {
        let v1 = Version(major: 1, minor: 2, patch: 3)
        let v2 = Version(major: 1, minor: 2, patch: 3)
        XCTAssertEqual(v1, v2)
    }

    func testCompareDifferingMajorVersions() {
        let v1 = Version(major: 1, minor: 2, patch: 3)
        let v2 = Version(major: 2, minor: 1, patch: 2)
        XCTAssertLessThan(v1, v2)
    }

    func testCompareDifferingMinorVersions() {
        let v1 = Version(major: 1, minor: 1, patch: 3)
        let v2 = Version(major: 1, minor: 2, patch: 2)
        XCTAssertLessThan(v1, v2)
    }

    func testCompareDifferingPatchVersions() {
        let v1 = Version(major: 1, minor: 2, patch: 3)
        let v2 = Version(major: 1, minor: 2, patch: 4)
        XCTAssertLessThan(v1, v2)
    }
}
