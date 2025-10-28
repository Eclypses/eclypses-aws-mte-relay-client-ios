# Changelog

All notable changes to this project will be documented in this file.

## [4.4.3] - 2025-10-28

### Added

### Changed
    - Updated MteRelay.podspec to produce a single MteRelay module
### Fixed

[4.4.3]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.4.3

## [4.4.2] - 2025-09-04

### Added

### Changed
    - Updated MteRelay.podspec to produce multiple modules
### Fixed

[4.4.2]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.4.2

## [4.4.1] - 2025-09-03

### Added

### Changed
    - Updated MteRelay.podspec to remove commented code
### Fixed

[4.4.1]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.4.1

## [4.4.0] - 2025-09-03

### Added
- MteRelay.podspec

### Changed

### Fixed

[4.4.0]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.4.0

## [4.3.4] - 2025-05-12

### Added

### Changed
- Downgraded iOS Target to v14.

### Fixed

[4.3.4]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.3.4

## [4.3.3] - 2025-05-12

### Added
- Check for Trial Version with warning

### Changed
- Set default pairPoolSize to 5.

### Fixed
- Fixed null exception where we tried to remove non-existant storedHost.
- Removed debug comments
-  

[4.3.3]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.3.3

## [4.3.2] - 2025-05-01

### Added


### Changed


### Fixed
- Fixed issue where we were prematurely discarding extra pairs before we were finishedd with them. 

[4.3.2]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.3.2

## [4.3.1] - 2025-05-01

### Added
- Improved thread safety in FileStream operations.
- Added logging Apple Unified Logging functionality with public static functions to toggle Relay.writeLogToFile, Relay.readFile, and Relay.clearFile.
- Added Relay Version to Settings

### Changed


### Fixed
- Out-of-sequence errors in FileStream operations

[4.3.1]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.3.1


## [4.3.0] - 2025-04-29

### Added
- Improved thread safety in FileStream operations.
- Added logging Apple Unified Logging functionality with public static functions to toggle Relay.writeLogToFile, Relay.readFile, and Relay.clearFile.
- Added Relay Version to Settings

### Changed


### Fixed
- Out-of-sequence errors in FileStream operations

[4.3.0]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.3.0


## [4.2.0] - 2025-04-02

### Added
- `downloadFileStream` now provides progress data via `fileStreamCompletionDelegate` when a `Content-Length` header is found in the response.

### Changed
- The `setSettings` functions are now private, replaced with new public `adjustRelaySettings` functions for modifying relay settings.
- The `getRequestBodyStream` delegate no longer returns an `Int` (`bytesReadFromApp`).
- The `rePairWithRelayServer` function now returns response data via `RelayResponseDelegate`.

### Fixed
- Ensured `pathnamePrefix` is fully functional across all applicable requests.

[4.2.0]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.2.0
