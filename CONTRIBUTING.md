# Contributing

## Talking to a Flipper

The app can hold two Flippers connected at once and swap between them instantly,
without the link ever dropping. `isConnected` stays true right across a swap, so
it cannot be the test for anything. Three separate questions follow, and mixing
them up is what this section exists to prevent.

### Which Flipper a request reaches — the task decides

Work made of more than one request declares itself a task:

```dart
await client.runTask(FlipperRequestPriority.background, () async {
  // every request in here goes to the Flipper the task started against
});
```

A task binds the session it starts on and keeps it, whatever the user plugs in
meanwhile, so an install cannot write half its files to one Flipper and half to
another. Requests inside it inherit that binding whatever their own priority is.

Work that outlives a single async body — a screen stream, a virtual display, an
emulation — holds `client.bindCurrentSession()` instead and runs its calls
through the handle. The stop has to reach the Flipper that has the thing open,
and by the time it is sent the user may already be looking at another one.

Anything not inside a task follows the active Flipper, which is what a tap means.

### Whether a result may still be recorded — the token decides

Reaching the right Flipper is not the same as still being relevant. Take a token
before the work and check it before writing anything a swap invalidated:

```dart
final token = client.deviceToken;
final bytes = await client.storageReadChunked(path);
if (token.isStale) return; // the app now describes a different Flipper
```

The two are not interchangeable. A firmware upload that finishes on the previous
Flipper is correct and complete *there*, and what the app records about it is
still dropped, because the screen describes another device now.

### Priority — where a request sits in the queue

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

### Reacting to a swap

`connectionStream` carries one event per transition: `connected`,
`disconnected`, `connecting`, `deviceChanged`, `modeChanged`. Answer
`deviceChanged` before filtering on anything else — a swap is a swap whether or
not the new Flipper has RPC up yet, and a handler that drops non-RPC events
would otherwise miss it and keep describing the previous device.

Every state also carries `deviceRevision`, which is absolute rather than a
difference. A listener that subscribed after the swap — a page rebuilt, a
service started late — still sees that the device it holds is not this one;
the event alone cannot tell it that, because a broadcast stream does not replay.

`modeChanged` means CLI to RPC and only that. The firmware offers no way to turn
an RPC session into a CLI one, so going that way destroys the session and builds
another, which reaches listeners as a real `disconnected`. Ask `state.rpcReady`
or `state.cliReady` rather than assembling the answer from `connected` and
`mode`.
