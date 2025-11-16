## Quickstart: Clean, Build, and Open Project

Run these three commands from the project root:

```bash
rm -rf .DerivedData
xcodebuild -scheme Chrono -configuration Debug -destination 'platform=macOS' -derivedDataPath .DerivedData build
open Chrono.xcodeproj
```


