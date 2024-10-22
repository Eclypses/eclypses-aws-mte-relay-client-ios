<center>
<img src="Eclypses.png" style="width:50%;"/>
</center>

<div align="center" style="font-size:40pt; font-weight:900; font-family:arial; margin-top:50px;" >
iOS MteRelay Swift Package For <br>Amazon Web Services</div>
<br><br><br>

# MteRelay Swift Package

### This SPM package provides out-of-the-box MTE integration into Swift iOS applications, allowing quick integration with very minimal code changes. This Amazon Web Services (AWS) Client Package requires a corresponding AWS MteRelay Server API to receive the encoded requests and relay them onto the original API. 
<br><br>

## Overview 
When you have integrated this Client Package into your iOS application and have set up and configured the corresponding MteRelay Server API, your application will make its network calls just as before except that they are now routed through the MteRelay. 

There, the URLRequest is inspected and the relevant information captured. The MteRelay checks for a corresponding MteRelay API and if not found, returns an error. However, if the MteRelay IS found, a new request is created, the original data is encoded with MTE and sent to the MteRelay API where is it decoded. 

Then, the original request is sent on to the original destination API. Any response will follow the same path in reverse.
<br><br>
## Add AWS MteRelay Swift Package to your application:
1.  Add this [AWS MteRelay Package](https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios.git) -  [HowTo](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app)
2.  Set up corresponding AWS MteRelay API to receive the requests from your application, where they will be decoded and relayed on to the original destination API.
3.  Navigate to your target’s General pane, and in the “Frameworks, Libraries, and Embedded Content” section, confirm that the MteRelay module is there. If not, add it.
<br><br>

## MteRelay Package Integration
Do the minimal setup which primarily consists of configuring the AWS MteRelay Server URL and editing your iOS application to use the MteRelay dataTask function.
- Confirm that you have the AWS MteRelay Server URL available to instantiate the MteRelay class.
- Locate the URLSession function(s) in your application where your network calls are made and ...
    - Import MteRelay
    - Create a Relay class variable, e.g. <var relay: Relay!> 
    - Add RelayResponseDelegate to class declaration and the single function this protocol requires, i.e. 
        func relayResponse(success: Bool, responseStr: String, errorMessage: String) {}. Any errors in the Relay instantiation process will be returned here.
    - In the class initializer, instantiate the Relay object


    Your class interacting with MteRelay Client must contain these elements
```swift  
import "MteRelay"

// The class were you wish to receive MteRelay responses needs to have a reference to MteRelay instance and conform to RelayResponseDelegate and StreamResponseDelegate
class <Your Class>: StreamResponseDelegate, RelayResponseDelegate {

// Class variables
var relay: Relay! 

// Returns Mte Pairing responses 
func relayResponse(success: Bool, responseStr: String, errorMessage: String?) {
    // receives Mte Pairing responses and instantiation errors.
}

func streamResponse(success: Bool, responseStr: String, errorMessage: String) {
        // Receives stream upload and download stream responses.
    }

 func streamCompletionPercentage(bytesCompleted: Double, totalBytes: Double) {
        // Useful for upload activity indicator. This is called periodically throughout the upload process with updated values.
    }

// Initializer of class interacting with MteRelay
init() async throws {
    try await instantiateMteRelay()
}

// New function to instantiate MteRelay.
    func instantiateMteRelay() async throws {
        relay = try await Relay()
        relay.relayResponseDelegate = self
        relay.streamResponseDelegate = self
        // Any Relay instantiation errors, including pairing errors, will be returned asynchronously via the RelayResponseDelegate, which should be monitored to confirm that the Relay instantiation was successful.  

        // if you need to adjust default Relay settings . . .
        // Available Relay Settings methods. See below for more information
        try relay.setPersistPairs(false) // Defaults to false
        try relay.setPairPoolSize(3) // Defaults to 3. Range 1 to 10
        try relay.setUploadChunkSize() // Defaults to 1024 * 1024 (1 MB). Range 4096 to 10485760 (10 MB)
    }
```

- If you have request headers that you wish to conceal, create a String array with the header names as the elements in the array. Content-Type will always be encrypted if it exists. The encrypted headers will be decrypted before being sent on the the original destination Server.

``` swift
let headersToEncrypt = ["Content-Type", "Auth", "<any_other_header_name>"]
```
<br><br>

### IMPORTANT - - Update your Request
- For any call you want to route through MteRelay, edit your Request URL to point to your MteServer API, i.e. https://aws-mte-server.myCompany.com/

<br><br>

### URLSession.dataTask function
- Edit your [func dataTask(with: URL, completionHandler: (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask] to call the corresponding function in the MteRelay class as shown here. 

```swift
await relay.dataTask(with: request, headersToEncrypt: ,headersToEncrypt) { (data, response, error) in
                    if let error = error {
                        // Handle the error
                    }
                    guard let data = data else {
                        // Handle the lack of data as appropriate
                    }
                    // Use the response and data as you wish
                }
```
<br><br>
 
### File Stream Upload Function
- Edit your file upload function to add the following functionality
```swift
var request = URLSession.request // Your original URLSession Request
let headersToEncrypt = ["Content-Type", "Auth", "<any_other_header_name>"] // Any headers you want to conceal
relay.streamResponseDelegate = self
try relay.uploadFileStream(request: request, 
                            headersToEncrypt: headersToEncrypt)
// Your success boolean, response String and any errors will be returned asynchronously via the StreamResponseDelegate
```
<br><br>

### File Stream Download Function
- Edit your file download function to add the following functionality
```swift
var request = URLSession.request // Your original URLSession Request
let downloadURL = <FileURL> // Where you want the downloaded file stored
let headersToEncrypt = ["Content-Type", "Auth", "<any_other_header_name>"] // Any headers you want to conceal
relay.streamResponseDelegate = self
await relay.download(request: request, downloadUrl: downloadUrl, headersToEncrypt: headersToEncrypt)
// Your success boolean, response String and any errors will be returned asynchronously via the StreamResponseDelegate
```
<br><br>


### RePair with MteRelay Server
Should the existing Mte pairing be broken for any reason, a rePairMte function is provided to remove the pairing between the AWS MteRelay Client and Server. Then you can reinstantiate the relay, which will rePair with the server.  
Example function

```swift
    func rePairMte() throws {

        // Remove existing pairing
        try relay.rePairMte() 

        // Destroy existing instantiation
        relay = nil

        // RePair with MteRelay Server
        Task.init {
            relay = try await Relay(relayPath: Settings.relayPath)
        }
    }
```

### Adjust Relay Settings as Necessary
- The RelaySettings actor contains a few settings that can be edited at runtime via public functions as shown below. 
```swift
// The Mobile Relay Client has the ability to persist pairing with server, even though client has been shut down. Default is false because a new pairing happens quickly at relay instantiation and has less chance of having been corrupted. 
try relay.setPersistPairs(false) // Defaults to false on each Relay instantiation

// The Mobile Relay Client provides multiple pairs used in a round-robin fashion to facilitate high throughput without collisions.  
try relay.setPairPoolSize(3) // Defaults to 3. Range 1 to 10

// Sets the maximum number of bytes processed in a single chunk. Processing often occurs on fewer bytes.
try relay.setUploadChunkSize(4096) // Defaults to 1048576. Range 4096 (4KB) to 10485760 (10 MB)

```

<br><br>
### An AWS MteRelay Client YouTube integration video will soon be available.
<br><br>

<div style="page-break-after: always; break-after: page;"></div>


# Contact Eclypses

<p align="center" style="font-weight: bold; font-size: 20pt;">Email: <a href="mailto:info@eclypses.com">info@eclypses.com</a></p>
<p align="center" style="font-weight: bold; font-size: 20pt;">Web: <a href="https://www.eclypses.com">www.eclypses.com</a></p>
<p align="center" style="font-weight: bold; font-size: 20pt;">Chat with us: <a href="https://developers.eclypses.com/dashboard">Developer Portal</a></p>
<p style="font-size: 8pt; margin-bottom: 0; margin: 100px 24px 30px 24px; " >
<b>All trademarks of Eclypses Inc.</b> may not be used without Eclypses Inc.'s prior written consent. No license for any use thereof has been granted without express written consent. Any unauthorized use thereof may violate copyright laws, trademark laws, privacy and publicity laws and communications regulations and statutes. The names, images and likeness of the Eclypses logo, along with all representations thereof, are valuable intellectual property assets of Eclypses, Inc. Accordingly, no party or parties, without the prior written consent of Eclypses, Inc., (which may be withheld in Eclypses' sole discretion), use or permit the use of any of the Eclypses trademarked names or logos of Eclypses, Inc. for any purpose other than as part of the address for the Premises, or use or permit the use of, for any purpose whatsoever, any image or rendering of, or any design based on, the exterior appearance or profile of the Eclypses trademarks and or logo(s).
</p>
