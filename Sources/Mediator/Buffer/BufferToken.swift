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
import Toolkit

/// Ownership token for the shared buffer content.
final class BufferToken {
    
    enum Owner {
        case nvim
        case ui
    }
    
    @Atomic private(set) var owner: Owner? = nil
    
    private let logger: Logger?
    private let onRelease: (Owner) -> Void
    private var autoReleaseSubject = PassthroughSubject<Void, Never>()
    private var autoReleaseSubscription: AnyCancellable!

    public init(
        releaseTimer: TimeInterval = 0.3,
        logger: Logger?,
        onRelease: @escaping (Owner) -> Void
    ) {
        self.logger = logger
        self.onRelease = onRelease
        self.autoReleaseSubscription = autoReleaseSubject
            .debounce(for: .seconds(releaseTimer), scheduler: DispatchQueue.global())
            .sink { [weak self] in self?.release() }
    }
    
    public func tryAcquire(for newOwner: Owner) -> Bool {
        switch owner {
        case newOwner:
            // Already acquired by this owner.
            autoReleaseSubject.send()
            return true
            
        case nil:
            $owner.write { $0 = newOwner }
            autoReleaseSubject.send()
            logger?.t("Acquired by \(newOwner)")
            return true
            
        default:
            // Already acquired by the other owner.
            logger?.t("Failed to acquire for \(newOwner)")
            return false
        }
    }
    
    private func release() {
        $owner.write { owner in
            guard let formerOwner = owner else {
                return
            }
            owner = nil
            logger?.t("Released by \(formerOwner)")
            onRelease(formerOwner)
        }
    }
}
