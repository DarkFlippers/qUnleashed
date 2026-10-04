## Main changes
- Version: 0.14.1 (build 14001), changes since 0.14.0 (build 14000)
* Tools: **Recovering MIFARE keys no longer looks frozen while it saves them** - a static-encrypted card produces tens of thousands of candidate keys, and writing that dictionary to the Flipper was a single step with nothing on screen moving for the whole of it. Over Bluetooth that is minutes. It now reports how far along it is, across every card in the run, and **Stop really stops it** instead of carrying on against a device you have walked away from. Reported on iOS, where Bluetooth is the only way to reach a Flipper
* Connection: **Bluetooth links negotiate their full packet size** - the size was read a moment too early on iOS and macOS, before the system had settled it, and a link that lost that race spent the rest of its life sending packets a twentieth of the size it could carry. Everything over Bluetooth was slower for it, not only key recovery
## Other changes
* Connection: a link that ends up slow now says so in the log, which is the one place a finished transfer can explain why it took as long as it did
* Quality: warnings from the connection layer are kept for a bug report. They were being dropped before anything could record them, which cost two accounts of a failure nobody could see afterwards - a packet-size read that failed, and a reboot the firmware refused
* Fixed: a candidate dictionary that failed to save no longer leaves the progress bar short for the rest of the run
