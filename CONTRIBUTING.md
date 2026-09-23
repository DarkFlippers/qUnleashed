# Contributing

## Request priority

The app can hold two Flippers connected at once and swap between them without
the link ever dropping. Which Flipper a request reaches is decided by the task
it belongs to — `client.runTask` binds the session it starts on. Priority
decides something else: where the request sits in the queue.

The queue is ordered strictly by priority, then first come first served, with no
ageing. So the value is also the plainest statement of what a request is for.
Choose it by asking who is held up, never by whose device it is:

| priority | who is waiting |
| --- | --- |
| `rightNow` | control and cleanup for something already running: the ping pacing an upload, the delete of its half-written file, the stop that ends a screen stream, a reboot |
| `foreground` | the screen — readings that exist to be displayed, and the window the user just tapped |
| `unattended` | the device — served whether or not anyone is looking at it. A Flipper in a warm session is owed an answer because it is connected, not because it is on screen |
| `background` | nobody — bulk that outlives the screen: firmware, app installs, storage walks. Low because it is long, not because it is unimportant |

`foreground` is the only one that leaves a task's binding, because a display
reading is never part of one. Labelling bound work `foreground` sends it to
whichever Flipper is on screen: a folder listed from the wrong card, an md5
compared against the wrong file, an app exit on a Flipper with nothing open.

`unattended` sits above `background` on purpose. Both are bound, so the choice
between them is only about the queue — and a one-frame `mkdir` queued behind a
few thousand frames of firmware means the folder appears when the flash ends.
