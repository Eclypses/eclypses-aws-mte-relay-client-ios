# Changelog

All notable changes to this project will be documented in this file.

## [4.3.2] - 2025-05-01

### Added


### Changed


### Fixed
- Fixed issue where we were prematurely discarding extra pairs before we were finishedd with them. 

[4.3.2]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/4.3.1

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
