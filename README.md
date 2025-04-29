<center>
<img src="Eclypses.png" style="width:50%;"/>
</center>

<div align="center" style="font-size:40pt; font-weight:900; font-family:arial; margin-top:50px;" >
MteRelay Mobile Client  
Swift Package</div>

![Latest Release](https://img.shields.io/github/v/release/Eclypses/eclypses-aws-mte-relay-client-ios?style=flat-square)

## Introduction  
This SPM package provides the Swift language Eclypses MteRelay Mobile Client Package and requires licensed access to an MteRelay server instance to receive the secure transmission. [Info](https://eclypses.com/mte-technology/amazon-web-services-aws/)

**Purpose of MteRelay:**  
- Securely relay HTTP requests to your server.  
- Protect sensitive headers and data with MTE encryption.  
- Stream large files efficiently.  

## Overview  
When you have integrated this Mobile Client Package into your iOS application and have set up and configured the corresponding MteRelay Server API, your application will make its network calls just as before except that they are now routed through the MteRelay.  

There, the URLRequest is inspected and the relevant information captured. The MteRelay checks for a corresponding MteRelay API and if not found, returns an error. However, if the MteRelay **IS** found, a new request is created, the original data is encoded with MTE and sent to the MteRelay API where it is decoded.  

Then, the original request is sent on to the original destination API. Any response will follow the same path in reverse.  

## Adding MteRelay Mobile Client Swift Package to Your Application
1. Add this [MteRelay Package](https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios.git) - [HowTo](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app)
2. Set up corresponding MteRelay API to receive the requests from your application, where they will be decoded and relayed on to the original destination API.
3. Navigate to your target’s General pane, and in the "Frameworks, Libraries, and Embedded Content" section, confirm that the MteRelay module is there. If not, add it.

## Table of Contents
- [Getting Started](#getting-started)
- [URLSession requests](#urlsession-requests)
- [Streamed File Upload request](#streamed-file-upload-request)
- [Streamed File Download request](#streamed-file-download-request)
- [RePair with Server](#repair-with-server)
- [Adjust Relay Settings as Necessary](#adjust-relay-settings-as-necessary)
- [Logging](#logging)
- [Contact Eclypses](#contact-eclypses)

## Getting Started  
Do the minimal setup which primarily consists of configuring the MteRelay Server URL and editing your iOS application to use the MteRelay `dataTask` function.

- Confirm that you have the MteRelay Server URL available to instantiate the `MteRelay` class.
- Locate the `URLSession` function(s) in your application where your network calls are made and:
    - Import MteRelay
    - Create a Relay class variable, e.g. `var relay: Relay!`
    - Add `RelayResponseDelegate` to class declaration and implement:

```swift
func relayResponse(success: Bool, responseStr: String, errorMessage: String) {}
```

Your class interacting with `MteRelay` must contain these elements:

```swift
import MteRelay

class YourClass: RelayResponseDelegate {

    var relay: Relay!

    func relayResponse(success: Bool, responseStr: String, errorMessage: String?) {
        // relay callback receiving responses and instantiation errors.
    }

    init() async throws {
        try await instantiateMteRelay()
    }

    func instantiateMteRelay() async throws {
        relay = try await Relay()
        relay.relayResponseDelegate = self
    }
}
```

### Update Your Request
For any call you want to route through `MteRelay`, edit your request URL to point to your `MteServer API`, i.e. `https://aws-mte-server.myCompany.com/`

## URLSession requests  
Edit your `URLSession.dataTask` function to call the corresponding function in the `MteRelay` class as shown:

```swift
await relay.dataTask(with: request, headersToEncrypt: headersToEncrypt, pathnamePrefix: pathnamePrefix) { (data, response, error) in
    if let error = error {
        // Handle the error
    }
    guard let data = data else {
        // Handle the lack of data
    }
    // Use the response and data as needed
}
```

## Streamed File Upload request  

```swift
try relay.uploadFileStream(request: request, headersToEncrypt: headersToEncrypt, pathnamePrefix: pathnamePrefix)
```

## Streamed File Download request  

```swift
await relay.download(request: request, downloadUrl: downloadUrl, headersToEncrypt: headersToEncrypt, pathnamePrefix: pathnamePrefix)
```

## RePair with Server  

```swift
 try await relay.rePairwithRelayServer(your_relay_server_url, pathnamePrefix: pathnamePrefix)
```

## Adjust Relay Settings as Necessary  

```swift
    try await relay.adjustRelaySettings(serverUrl: Settings.actualServerPath, pathnamePrefix: Settings.pathnamePrefix, newStreamChunkSize: 1048576, newPairPoolSize: 3, persistPairs: false)
```

## Logging  

```swift
    Relay.enableFileLogging(true) // (Defaults to false)
    
    try Relay.readLogFile()
    
    Relay.clearLogFile()    
```

## Contact Eclypses  

**Email:** [info@eclypses.com](mailto:info@eclypses.com)  
**Web:** [www.eclypses.com](https://www.eclypses.com)  
**Chat with us:** [Developer Portal](https://developers.eclypses.com/dashboard)  

---  
**All trademarks of Eclypses Inc.** may not be used without Eclypses Inc.'s prior written consent.
