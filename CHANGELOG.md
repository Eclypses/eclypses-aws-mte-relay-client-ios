# Changelog

All notable changes to this project will be documented in this file.

## [3.7.0] - 2025-04-02

### Added
- `downloadFileStream` now provides progress data via `fileStreamCompletionDelegate` when a `Content-Length` header is found in the response.

### Changed
- The `setSettings` functions are now private, replaced with new public `adjustRelaySettings` functions for modifying relay settings.
- The `getRequestBodyStream` delegate no longer returns an `Int` (`bytesReadFromApp`).
- The `rePairWithRelayServer` function now returns response data via `RelayResponseDelegate`.

### Fixed
- Ensured `pathnamePrefix` is fully functional across all applicable requests.

[3.7.0]: https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios/releases/tag/3.7.0
