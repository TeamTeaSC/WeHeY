# README

_Last Updated: July 30th 2024 by Stephen Chien (shchien@andrew.cmu.edu)_
_Note: This project builds upon the WeHe iOS client created at Northeastern University._

This file is intended to help get someone unfamilliar with the project up to speed.  To get started, follow the steps in `help/getting_started.md`.

Please refer to this documentation for more info about WeHeY: 
https://docs.google.com/document/d/1YWQ8NCLAzFhdlSfKLKHyKRzQKBljts8XiX-g1hd-Xus/edit?usp=sharing

---

## Structure

```
.
├── Assets.xcassets
├── Cells
│   ├── AppCollectionViewCell.swift
│   ├── ReplayTableViewCell.swift
│   ├── ResultTableViewCell.swift
│   ├── DPIInfoTableViewCell.swift
│   └── BitrateInfoTableViewCell.swift
├── Extensions
│   └── String+removingWhitespaces.swift
├── Networking
│   ├── ReplayRunner.swift
│   ├── Replayer.swift
│   ├── ResultWatcher.swift
│   ├── Sidechannel.swift
│   ├── MetaDataChannel.swift
│   ├── MlabConnection.swift
│   ├── WebSocketWrapper.swift
│   └── Localization.swift
├── Replay_files
|   ...
├── Stores
│   ├── App.swift
│   ├── Packet.swift
│   ├── PortMapping.swift
│   ├── Replay.swift
│   ├── Result.swift
│   └── Settings.swift
├── Utility
│   ├── Helper.swift
│   ├── LocalizedStrings.swift
│   └── LocalizationConstants.swift
├── ViewControllers
│   ├── AboutWeheViewController.swift
│   ├── AppCollectionViewController.swift
│   ├── MainMenuViewController.swift
│   ├── ConsentViewController.swift
│   ├── ReplayViewController.swift
│   ├── DPIAnalysisViewController.swift
│   ├── ResultTableViewController.swift
│   ├── SettingsViewController.swift
│   ├── WebViewController.swift
│   ├── MoreInfoTableViewController.swift
│   └── FunctionalityViewController.swift
```

### Assets
Contains assets such as the app icon and replay icons.

### Cells
Contains cell controllers for their respective table controllers.

| File                        | Screen        |   
| :--------------------------:|:-------------:|
| AppCollectionViewCell.swift      | Replay selection  |
| ReplayTableViewCell.swift        | Replay running |
| ResultTableViewCell.swift        | Previous results  |
| DPIInfoTableViewCell.swift        | Replay DPI  |
| BitrateInfoTableViewCell.swift        | Replay bitrate  |

The cells controllers contain minimal code and are only responsible for rendering themsevles.

### Extensions
Contains an extension for the stringt class that trims the string by removing whitespaces. This is used for stripping spacing characters from decoded json and in some other places.

### Networking
These classes contain the code responsible for running replays and getting their results

* `Sidechannel.swift` handles connecting to the replay server sidechannel, sending and receiving messages. The code should be fairly straightforward. The class throws `SideChannelError` exceptions and the caller is expected to handle them.

* `MlabConnection.swift` handles connecting to the Mlab servers.  It first requests MLab for the nearest sites to the user, then retrieves the IP of one server in the sites.  The caller can optionally specify a specific site when initializing this class.

* `ReplayRunner.swift` handles running the selected replay. By replay here I mean running both the original and random replays. Only one replayrunner is ever created and each app gets a new one when a replay is started. First the replay runner will load the relevant json replay file, then it will hit the `WHATSMYIPMAN` endpoint and then start the replay by creating a new Replayer. The Replayer will return to ReplayRunner either via the `replayFailed` method if an error occured or `replayDone` if everything went fine. The ReplayRunner then either starts the next (random) replay or creates a ResultWatcher to handle getting the analysis results.

* `Replayer.swift` handles running a single replay (open or random). It manages the connection with the sidechannel and the replay server (tcp or udp).

* `ResultWatcher.swift` handles requesting analysis for a replay that just finished running and then querying the server for analysis results. Once the results are returned, the watcher passes them back to the replayViewController via the `receivedResult` method so they can be saved and rendered.

* `Localization.swift` handles nearly all of the logic and networking for running localization tests.  It first retrieves IPs of a server pair forming a Y-shaped topology.  It then runs simultaneous replays with the original and random trace (in this specific order).  It then requests differentiation results from both servers.  If both replays experienced differentiation, it requests localization results from the first server and parses it. 

### Replay_Files

This folder contains all the relevant replay recordings in json format.

### Stores

These classes store and group relevant data as well as offer some functionality relevant to what they represent. 

* `App.swift` represents apps that are created based on the contents of `app_list.json`. 

* `Packet.swift` represents a single packet in a replay file.

* `PortMapping.swift` is a convenience class that stores ip and port values for a replay.

* `Replay.swift` replays a parsed json replay file. 

* `Result.swift` models a single result returned by the analysis server.

* `Settings.swift` is probably the most complex. It handles loading and saving the settings. There should ever only be one instance of this class and a reference to it should be passes along to any classes that need access to the settings. Any changes made to the attributes of the class are automatically saved to memory. The class also contains all the default settings that are used on the first run of the app.

### Utility 

* `Helper.swift` is a static class that contains some convenience methods used throughout the app. Helps with reading json files, getting mobile stats, checking if the current connection is on WiFi. Comment on `RunOnUIThread`: this app performs a lot of networking tasks so it needs to run a lot of code on background threads to not block the UI thread. This method serves as a way to either run some UI updates from a background app or come back to the main thread once the background tasks are done running.

* `LocalizedStrings.swift` contains string constants used by WeHe.

* `LocalizationConstants.swift` contains string constants used by WeHeY.

### ViewControllers

These handle rendering the UI, navigation and some simple tasks. 
 
* `ConsentViewController.swift` handles showing the consent form that a user will see when they are launching the app for the first time or if they click the option to see the form from the main menu.

* `MainMenuViewController.swift` is the main screen of the app where the user can decide what to do.

* `WebViewController.swift` handles displaying the online dashboard in the app when the "View Online Dashboard" option is selected.

* `SettingsViewController.swift` handles displaying settings to the user.

* `ResultTableViewController.swift` handles displaying previous results to the user

* `AppCollectionViewController`.swift` allows the user to select the apps they want to run replays for

* `ReplayViewController.swift` handles the process of running all the selected replays and conducting localization tests. This class could probably use the most refactoring, it slowly grew larger and larger. The rendering logic is messy, but most of it is done through the `tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell` method.

---

## Developer Options

* To force every app to experience differentiation, uncomment `FORCE DIFFERENTIATION` in `ReplayViewController.swift`.  Similarly, to randomize differentiation results, uncomment `RANDOMIZE DIFFERENTIATION`.  This allows us to proceed to localization testing. 

* To test with local servers outside of Mlab infrastructure, first add the files `ca.der` and `ca.pfx` generated by your server to the root directory (instructions on how to generate these files are found in the server GitHub) (note: don't change `ca2.der` and `ca2.pfx` since they are used by Mlab).  Then set `usingDefaultServer` in `Settings.swift` to false.

* To force certain localization results to occur, set `app.localization` to the desired value before calling `replayView.locDone` in `Localization.swift`.  To force an error to occur in `Localization.swift`, call `exitWithError`.
