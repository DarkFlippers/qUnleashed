//-----------------------------------------------------------------------------
// bzlib stub. The hardnested bitflip tables are shipped LZ4-compressed, so the
// bz2 branch of init_bitflip_bitarrays() is never taken (searchFile never finds
// a .bz2 file). These declarations exist only so that dead branch still
// compiles and links without pulling in a real libbz2 dependency; the functions
// are never called at runtime. If .bz2 tables are ever shipped, replace this
// with a real bzlib.
//-----------------------------------------------------------------------------
#ifndef QUNLEASHED_BZLIB_STUB_H
#define QUNLEASHED_BZLIB_STUB_H

#define BZ_OK 0
#define BZ_STREAM_END 4
#define BZ_CONFIG_ERROR (-9)

typedef struct {
  char *next_in;
  unsigned int avail_in;
  unsigned int total_in_lo32;
  unsigned int total_in_hi32;
  char *next_out;
  unsigned int avail_out;
  unsigned int total_out_lo32;
  unsigned int total_out_hi32;
  void *state;
  void *bzalloc;
  void *bzfree;
  void *opaque;
} bz_stream;

static inline int BZ2_bzDecompressInit(bz_stream *strm, int verbosity, int small) {
  (void)strm;
  (void)verbosity;
  (void)small;
  return BZ_CONFIG_ERROR; // bz2 unsupported in this build
}
static inline int BZ2_bzDecompress(bz_stream *strm) {
  (void)strm;
  return BZ_CONFIG_ERROR;
}
static inline int BZ2_bzDecompressEnd(bz_stream *strm) {
  (void)strm;
  return BZ_OK;
}

#endif // QUNLEASHED_BZLIB_STUB_H
