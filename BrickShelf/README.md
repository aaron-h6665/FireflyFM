# BrickShelf

BrickShelf is an original SwiftUI/iOS prototype for organizing brick sets, physical copies/boxes, missing pieces, bulk inventory, storage locations, and build plans.

## Product boundaries

- Each physical box is independent. Purchase details, receipt, notes, photo, condition, location, and missing pieces belong to that box.
- Official catalog definitions are reference data and are never deleted by collection actions.
- Removing a box archives it. Missing pieces are resolved instead of erased. Quantity changes create activity records. These choices preserve provenance and make accidental loss recoverable.
- SwiftData provides offline persistence. JSON export/restore is the deletion-safe backup path in this prototype; users can save exports to iCloud Drive or another Files provider.
- LEGO.com instruction links use the public building-instructions route. BrickShelf is not affiliated with or endorsed by the LEGO Group.
- The seeded official build plan intentionally contains only a tracked sample of requirements, and the UI labels it that way. Production buildability requires a licensed/approved complete parts-catalog provider.

## Run

Open `BrickShelf.xcodeproj` in Xcode 16+ and run the `BrickShelf` scheme on an iOS 17+ simulator or device. Barcode scanning requires a physical device; the scanner includes a manual fallback.
