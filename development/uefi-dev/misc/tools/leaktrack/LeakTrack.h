/** @file
  DEBUG ONLY: tracks gBS pool/page allocations of all modules while the
  driver image is loaded. Not for commit.
**/

#ifndef LEAK_TRACK_H_
#define LEAK_TRACK_H_

#include <Uefi.h>

VOID
LeakTrackStart (
  IN EFI_HANDLE  ImageHandle
  );

VOID
LeakTrackDump (
  IN CONST CHAR8  *Label
  );

VOID
LeakTrackEnd (
  VOID
  );

#endif /* LEAK_TRACK_H_ */
