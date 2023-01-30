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

import Combine
import Foundation

/// A switch (boolean) that reverts automatically to `false` after a delay.
///
/// Every time it is activated, the `false` value is debounced.
public final class TimeSwitch {
    @Atomic public private(set) var isOn: Bool = false
    private var subject = PassthroughSubject<Void, Never>()
    private var subscription: AnyCancellable!

    public init(timer: TimeInterval) {
        subscription = subject
            .debounce(for: .seconds(timer), scheduler: DispatchQueue.global())
            .sink { [unowned self] _ in
                $isOn.write { $0 = false }
            }
    }

    public func activate() {
        $isOn.write {
            $0 = true
            subject.send(())
        }
    }
}
