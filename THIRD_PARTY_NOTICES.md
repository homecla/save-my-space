# Third-party notices

Save My Space is licensed under the GNU Affero General Public License v3.0 (see `LICENSE`).
It uses the following third-party components:

| Component | Version | License | Used by |
|---|---|---|---|
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | 1.8.2 | Apache License 2.0 with Runtime Library Exception | `smspace` CLI (statically linked) |

The Apache License 2.0 is compatible with version 3 of the GNU GPL/AGPL, so the combined
work can be distributed under the AGPL-3.0. The full text of the Apache License 2.0 is
available at https://www.apache.org/licenses/LICENSE-2.0.

The project also links against macOS system frameworks (Foundation, AppKit, SwiftUI,
CryptoKit, CoreServices, UniformTypeIdentifiers, Observation). These are "System Libraries"
under section 1 of the AGPL-3.0 and are not part of the Corresponding Source.
