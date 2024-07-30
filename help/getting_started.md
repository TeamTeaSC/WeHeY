# Getting Started

_Last Updated: July 30th 2024 by Stephen Chien (shchien@andrew.cmu.edu)_

## Requirements

 * Xcode supporting swift 4
 * [cocoapods](https://cocoapods.org/) for dependency management

 ## Preparing the repository

 1. Clone the repository
 1. Navigate to the repository in your terminal
 1. Run `git checkout WeHeY` 
 1. Run `pod install` (note: this can take around 5-10 minutes, be patient)
 1. After the installion is done, open the repository in xcode <b> by clicking the `wehe.xcworkspace` file </b>. This is important, opening the repository through Xcode for the first time may cause the dependencies to not be detected and produce errors
 
 *By following the above steps, everything should build with no errors out of the box, no need to change any other settings.

 ## Submitting a build to the app store

 1. Go to `xcode` -> `preferences` -> `accounts` and login with the `wehe@ccs.neu.edu` apple id account
 1.  If an error occurs during compilation, click on it and make the appropriate changes (for example, you may have to set the signing group. since you are logged in you should be able to just select an existing signing group). 
 1.  Select `generic iOS device` as your compilation target in the top left corner of xcode
 1.  Go to `product` -> `archive`
 1.  Follow the instructions. If a certificate error occurs, click through to manage certificates and press the `+` sign to generate a new certificate
 1.  You can manage the submitted builds at the [iTunes connect pannel](https://itunesconnect.apple.com/)