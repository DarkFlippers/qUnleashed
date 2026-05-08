#pragma once

#ifdef _MSC_VER
#include <intrin.h>

#ifndef __GNUC__
#define __GNUC__ 4
#endif

#ifndef __attribute__
#define __attribute__(x)
#endif

#ifndef __builtin_bswap32
#define __builtin_bswap32(x) _byteswap_ulong((unsigned long)(x))
#endif

#ifndef __builtin_bswap64
#define __builtin_bswap64(x) _byteswap_uint64((unsigned __int64)(x))
#endif

static __inline int qunleashed_builtin_parity(unsigned int value) {
  value ^= value >> 16;
  value ^= value >> 8;
  value ^= value >> 4;
  value &= 0x0f;
  return (0x6996 >> value) & 1;
}

#ifndef __builtin_parity
#define __builtin_parity(x) qunleashed_builtin_parity((unsigned int)(x))
#endif
#endif
