//-----------------------------------------------------------------------------
// Apple (CocoaPods) unity build for qunleashed_hardnested.
//
// Podspecs can't reference sources outside their own tree, and Xcode compiles
// each file once, so this forwarder #includes the shared C sources (one level
// up) into a single translation unit - the same approach ChameleonUltraGUI uses.
// hn_namespace.h is force-included via the podspec's OTHER_CFLAGS, so the
// crapto1 symbols are renamed here too (needed for the single Apple binary).
//
// The CMake platforms (Windows/Linux/Android) compile the files individually
// instead; this file is Apple-only and not part of the CMake target.
//-----------------------------------------------------------------------------
#include "../crapto1.c"
#include "../crypto1.c"
#include "../bucketsort.c"
#include "../parity.c"
#include "../hardnested.c"
#include "../qunleashed_hardnested_bridge.c"
#include "../hardnested/hardnested_bf_core.c"
#include "../hardnested/hardnested_bitarray_core.c"
#include "../hardnested/hardnested_bruteforce.c"
#include "../hardnested/tables.c"
#include "../pm3/commonutil.c"
#include "../pm3/ui.c"
#include "../pm3/util.c"
#include "../pm3/util_posix.c"
#include "../minlzlib/inputbuf.c"
#include "../minlzlib/dictbuf.c"
#include "../minlzlib/lzma2dec.c"
#include "../minlzlib/lzmadec.c"
#include "../minlzlib/rangedec.c"
#include "../minlzlib/xzcrc.c"
#include "../minlzlib/xzstream.c"
