//-----------------------------------------------------------------------------
// Apple (CocoaPods) unity build for qunleashed_faaccrack.
//
// Podspecs cannot reference sources outside their own tree, and Xcode compiles
// each file once, so this forwarder #includes the library's C sources (one
// level up) into a single translation unit - the same approach the hardnested
// pod uses.
//
// One translation unit per architecture, which is the difference that matters
// here: the CMake platforms compile the engine once per instruction set and
// pick between them at runtime, and this cannot. `FAACCRACK_MULTI_VARIANT` is
// therefore *not* defined for this build, and the dispatcher calls the single
// variant the architecture's own flags selected - NEON on Apple Silicon and
// iOS, the x86-64 baseline on an Intel Mac. Defining it here would make the
// dispatcher reference four objects that do not exist.
//
// `main` is renamed away by the podspec's OTHER_CFLAGS: the engine still
// carries its command-line entry point, and a library must not export one.
//-----------------------------------------------------------------------------
#include "../faaccrack.c"
#include "../faaccrack_dispatch.c"
#include "../faaccrack_bridge.c"
