/** @file
  DEBUG ONLY: tracks gBS pool/page allocations of all modules while the
  driver image is loaded and prints the live ones grouped by caller.
  Not for commit.
**/

#include <Uefi.h>
#include <IndustryStandard/PeImage.h>
#include <Protocol/LoadedImage.h>
#include <Library/BaseLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/DebugLib.h>
#include <Library/UefiBootServicesTableLib.h>

#include "LeakTrack.h"

#define LT_SLOTS       262144
#define LT_TOMB        1
#define LT_GROUPS      256
#define LT_IMAGES      512
#define LT_STACK_SCAN  48
#define LT_CHAIN       3

typedef struct {
  UINTN      Address;
  UINTN      Size;
  UINTN      Caller;
  UINT32     Chain[LT_CHAIN];
  UINT32     Phase;
  UINT8      Type;
  BOOLEAN    Pages;
} LT_ENTRY;

typedef struct {
  UINTN      Caller;
  UINT32     Chain[LT_CHAIN];
  UINT8      Type;
  BOOLEAN    Pages;
  UINT32     Count;
  UINTN      Bytes;
  UINT32     MinPhase;
  UINT32     MaxPhase;
} LT_GROUP;

typedef struct {
  UINTN          Base;
  UINTN          Size;
  CONST CHAR8    *Name;
} LT_IMAGE;

STATIC LT_ENTRY            *mEntries;
STATIC UINTN               mPeak;
STATIC LT_GROUP            mGroups[LT_GROUPS];
STATIC LT_IMAGE            mImages[LT_IMAGES];
STATIC UINTN               mUsed;
STATIC UINTN               mOverflow;
STATIC UINT32              mPhase;
STATIC BOOLEAN             mActive;
STATIC UINTN               mImageBase;
STATIC UINTN               mImageSize;
STATIC EFI_ALLOCATE_POOL   mOrgAllocatePool;
STATIC EFI_FREE_POOL       mOrgFreePool;
STATIC EFI_ALLOCATE_PAGES  mOrgAllocatePages;
STATIC EFI_FREE_PAGES      mOrgFreePages;

STATIC
UINTN
LtHash (
  IN UINTN  Address
  )
{
  return (UINTN)(((UINT64)Address >> 3) * 0x9E3779B97F4A7C15ULL >> 50) & (LT_SLOTS - 1);
}

STATIC
VOID
LtAdd (
  IN UINTN    Address,
  IN UINTN    Size,
  IN UINT8    Type,
  IN BOOLEAN  Pages,
  IN UINTN    Caller,
  IN UINTN    *Stack
  )
{
  EFI_TPL   OldTpl;
  UINTN     Slot;
  UINTN     Index;
  UINTN     Found;
  LT_ENTRY  *Entry;

  if (!mActive || (Address == 0)) {
    return;
  }

  OldTpl = gBS->RaiseTPL (TPL_HIGH_LEVEL);
  if (mUsed >= (LT_SLOTS * 3) / 4) {
    mOverflow++;
    gBS->RestoreTPL (OldTpl);
    return;
  }

  Slot = LtHash (Address);
  while (mEntries[Slot].Address > LT_TOMB) {
    Slot = (Slot + 1) & (LT_SLOTS - 1);
  }

  Entry          = &mEntries[Slot];
  Entry->Address = Address;
  Entry->Size    = Size;
  Entry->Type    = Type;
  Entry->Pages   = Pages;
  Entry->Caller  = Caller;
  Entry->Phase   = mPhase;
  ZeroMem (Entry->Chain, sizeof (Entry->Chain));

  // Return addresses into this image found on the stack = our call chain.
  Found = 0;
  for (Index = 0; Index < LT_STACK_SCAN && Found < LT_CHAIN; Index++) {
    if ((Stack[Index] > mImageBase) && (Stack[Index] < mImageBase + mImageSize)) {
      Entry->Chain[Found++] = (UINT32)(Stack[Index] - mImageBase);
    }
  }

  mUsed++;
  mPeak = MAX (mPeak, mUsed);
  gBS->RestoreTPL (OldTpl);
}

STATIC
VOID
LtRemove (
  IN UINTN  Address
  )
{
  EFI_TPL  OldTpl;
  UINTN    Slot;

  if (!mActive || (Address == 0)) {
    return;
  }

  OldTpl = gBS->RaiseTPL (TPL_HIGH_LEVEL);
  Slot   = LtHash (Address);
  while (mEntries[Slot].Address != 0) {
    if (mEntries[Slot].Address == Address) {
      mEntries[Slot].Address = LT_TOMB;
      mUsed--;
      break;
    }

    Slot = (Slot + 1) & (LT_SLOTS - 1);
  }

  gBS->RestoreTPL (OldTpl);
}

STATIC
EFI_STATUS
EFIAPI
LtAllocatePool (
  IN  EFI_MEMORY_TYPE  PoolType,
  IN  UINTN            Size,
  OUT VOID             **Buffer
  )
{
  volatile UINTN  Mark;
  EFI_STATUS      Status;

  Mark   = 0;
  Status = mOrgAllocatePool (PoolType, Size, Buffer);
  if (!EFI_ERROR (Status)) {
    LtAdd ((UINTN)*Buffer, Size, (UINT8)PoolType, FALSE, (UINTN)__builtin_return_address (0), (UINTN *)&Mark);
  }

  return Status;
}

STATIC
EFI_STATUS
EFIAPI
LtFreePool (
  IN VOID  *Buffer
  )
{
  LtRemove ((UINTN)Buffer);
  return mOrgFreePool (Buffer);
}

STATIC
EFI_STATUS
EFIAPI
LtAllocatePages (
  IN     EFI_ALLOCATE_TYPE     Type,
  IN     EFI_MEMORY_TYPE       MemoryType,
  IN     UINTN                 Pages,
  IN OUT EFI_PHYSICAL_ADDRESS  *Memory
  )
{
  volatile UINTN  Mark;
  EFI_STATUS      Status;

  Mark   = 0;
  Status = mOrgAllocatePages (Type, MemoryType, Pages, Memory);
  if (!EFI_ERROR (Status)) {
    LtAdd ((UINTN)*Memory, EFI_PAGES_TO_SIZE (Pages), (UINT8)MemoryType, TRUE, (UINTN)__builtin_return_address (0), (UINTN *)&Mark);
  }

  return Status;
}

STATIC
EFI_STATUS
EFIAPI
LtFreePages (
  IN EFI_PHYSICAL_ADDRESS  Memory,
  IN UINTN                 Pages
  )
{
  LtRemove ((UINTN)Memory);
  return mOrgFreePages (Memory, Pages);
}

STATIC
VOID
LtUpdateCrc (
  VOID
  )
{
  gBS->Hdr.CRC32 = 0;
  gBS->CalculateCrc32 (gBS, gBS->Hdr.HeaderSize, &gBS->Hdr.CRC32);
}

STATIC
CONST CHAR8 *
LtPdbName (
  IN UINTN  Base
  )
{
  EFI_IMAGE_DOS_HEADER                 *Dos;
  EFI_IMAGE_OPTIONAL_HEADER_PTR_UNION  Hdr;
  EFI_IMAGE_DATA_DIRECTORY             *Dir;
  EFI_IMAGE_DEBUG_DIRECTORY_ENTRY      *Dbg;
  UINTN                                Index;
  UINT8                                *Cv;
  CONST CHAR8                          *Name;
  CONST CHAR8                          *Pos;

  Dos     = (EFI_IMAGE_DOS_HEADER *)Base;
  Hdr.Pe32 = (EFI_IMAGE_NT_HEADERS32 *)(Base + ((Dos->e_magic == EFI_IMAGE_DOS_SIGNATURE) ? Dos->e_lfanew : 0));
  if (Hdr.Pe32->Signature != EFI_IMAGE_NT_SIGNATURE) {
    return "?";
  }

  if (Hdr.Pe32->OptionalHeader.Magic == EFI_IMAGE_NT_OPTIONAL_HDR64_MAGIC) {
    if (Hdr.Pe32Plus->OptionalHeader.NumberOfRvaAndSizes <= EFI_IMAGE_DIRECTORY_ENTRY_DEBUG) {
      return "?";
    }

    Dir = &Hdr.Pe32Plus->OptionalHeader.DataDirectory[EFI_IMAGE_DIRECTORY_ENTRY_DEBUG];
  } else {
    if (Hdr.Pe32->OptionalHeader.NumberOfRvaAndSizes <= EFI_IMAGE_DIRECTORY_ENTRY_DEBUG) {
      return "?";
    }

    Dir = &Hdr.Pe32->OptionalHeader.DataDirectory[EFI_IMAGE_DIRECTORY_ENTRY_DEBUG];
  }

  if (Dir->VirtualAddress == 0) {
    return "?";
  }

  Name = NULL;
  Dbg  = (EFI_IMAGE_DEBUG_DIRECTORY_ENTRY *)(Base + Dir->VirtualAddress);
  for (Index = 0; Index < Dir->Size / sizeof (*Dbg); Index++) {
    if (Dbg[Index].Type != EFI_IMAGE_DEBUG_TYPE_CODEVIEW) {
      continue;
    }

    Cv = (UINT8 *)(Base + Dbg[Index].RVA);
    switch (*(UINT32 *)Cv) {
      case CODEVIEW_SIGNATURE_NB10:
        Name = (CONST CHAR8 *)(Cv + sizeof (EFI_IMAGE_DEBUG_CODEVIEW_NB10_ENTRY));
        break;
      case CODEVIEW_SIGNATURE_RSDS:
        Name = (CONST CHAR8 *)(Cv + sizeof (EFI_IMAGE_DEBUG_CODEVIEW_RSDS_ENTRY));
        break;
      case CODEVIEW_SIGNATURE_MTOC:
        Name = (CONST CHAR8 *)(Cv + sizeof (EFI_IMAGE_DEBUG_CODEVIEW_MTOC_ENTRY));
        break;
    }
  }

  if (Name == NULL) {
    return "?";
  }

  for (Pos = Name; *Pos != '\0'; Pos++) {
    if ((*Pos == '/') || (*Pos == '\\')) {
      Name = Pos + 1;
    }
  }

  return Name;
}

STATIC
UINTN
LtCollectImages (
  VOID
  )
{
  EFI_STATUS                 Status;
  EFI_HANDLE                 *Handles;
  UINTN                      Count;
  UINTN                      Index;
  UINTN                      Images;
  EFI_LOADED_IMAGE_PROTOCOL  *Image;

  Status = gBS->LocateHandleBuffer (ByProtocol, &gEfiLoadedImageProtocolGuid, NULL, &Count, &Handles);
  if (EFI_ERROR (Status)) {
    return 0;
  }

  Images = 0;
  for (Index = 0; Index < Count && Images < LT_IMAGES; Index++) {
    Status = gBS->HandleProtocol (Handles[Index], &gEfiLoadedImageProtocolGuid, (VOID **)&Image);
    if (EFI_ERROR (Status) || (Image->ImageBase == NULL)) {
      continue;
    }

    mImages[Images].Base = (UINTN)Image->ImageBase;
    mImages[Images].Size = (UINTN)Image->ImageSize;
    mImages[Images].Name = LtPdbName ((UINTN)Image->ImageBase);
    Images++;
  }

  gBS->FreePool (Handles);
  return Images;
}

STATIC
CONST CHAR8 *
LtFindImage (
  IN  UINTN  Address,
  IN  UINTN  Images,
  OUT UINTN  *Offset
  )
{
  UINTN  Index;

  for (Index = 0; Index < Images; Index++) {
    if ((Address >= mImages[Index].Base) && (Address < mImages[Index].Base + mImages[Index].Size)) {
      *Offset = Address - mImages[Index].Base;
      return mImages[Index].Name;
    }
  }

  *Offset = Address;
  return "DxeCore/unknown";
}

/**
  Hooks gBS allocation services. Call first in the entry point.

  @param[in]  ImageHandle  Driver image handle.
**/
VOID
LeakTrackStart (
  IN EFI_HANDLE  ImageHandle
  )
{
  EFI_STATUS                 Status;
  EFI_LOADED_IMAGE_PROTOCOL  *Image;
  EFI_TPL                    OldTpl;
  EFI_PHYSICAL_ADDRESS       Table;

  Status = gBS->HandleProtocol (ImageHandle, &gEfiLoadedImageProtocolGuid, (VOID **)&Image);
  if (EFI_ERROR (Status)) {
    return;
  }

  Status = gBS->AllocatePages (AllocateAnyPages, EfiBootServicesData, EFI_SIZE_TO_PAGES (LT_SLOTS * sizeof (LT_ENTRY)), &Table);
  if (EFI_ERROR (Status)) {
    return;
  }

  mEntries = (LT_ENTRY *)(UINTN)Table;
  ZeroMem (mEntries, LT_SLOTS * sizeof (LT_ENTRY));

  mImageBase = (UINTN)Image->ImageBase;
  mImageSize = (UINTN)Image->ImageSize;

  OldTpl             = gBS->RaiseTPL (TPL_HIGH_LEVEL);
  mOrgAllocatePool   = gBS->AllocatePool;
  mOrgFreePool       = gBS->FreePool;
  mOrgAllocatePages  = gBS->AllocatePages;
  mOrgFreePages      = gBS->FreePages;
  gBS->AllocatePool  = LtAllocatePool;
  gBS->FreePool      = LtFreePool;
  gBS->AllocatePages = LtAllocatePages;
  gBS->FreePages     = LtFreePages;
  LtUpdateCrc ();
  mActive = TRUE;
  gBS->RestoreTPL (OldTpl);

  DEBUG ((DEBUG_ERROR, "LEAKTRACK start, image base %p size %lx\n", mImageBase, mImageSize));
}

/**
  Prints live allocations made since LeakTrackStart, grouped by caller.

  @param[in]  Label  Name of the dump point.
**/
VOID
LeakTrackDump (
  IN CONST CHAR8  *Label
  )
{
  UINTN        Slot;
  UINTN        Index;
  UINTN        Groups;
  UINTN        Images;
  UINTN        Bytes;
  UINTN        Offset;
  LT_ENTRY     *Entry;
  LT_GROUP     *Group;
  CONST CHAR8  *Name;

  if (mOrgAllocatePool == NULL) {
    return;
  }

  mActive = FALSE;
  ZeroMem (mGroups, sizeof (mGroups));
  Groups = 0;
  Bytes  = 0;

  for (Slot = 0; Slot < LT_SLOTS; Slot++) {
    Entry = &mEntries[Slot];
    if (Entry->Address <= LT_TOMB) {
      continue;
    }

    Bytes += Entry->Size;
    for (Index = 0; Index < Groups; Index++) {
      Group = &mGroups[Index];
      if ((Group->Caller == Entry->Caller) && (Group->Type == Entry->Type) &&
          (Group->Pages == Entry->Pages) &&
          (CompareMem (Group->Chain, Entry->Chain, sizeof (Group->Chain)) == 0))
      {
        break;
      }
    }

    if (Index == Groups) {
      if (Groups == LT_GROUPS) {
        continue;
      }

      Group = &mGroups[Groups++];
      Group->Caller   = Entry->Caller;
      Group->Type     = Entry->Type;
      Group->Pages    = Entry->Pages;
      Group->MinPhase = Entry->Phase;
      CopyMem (Group->Chain, Entry->Chain, sizeof (Group->Chain));
    }

    Group = &mGroups[Index];
    Group->Count++;
    Group->Bytes   += Entry->Size;
    Group->MinPhase = MIN (Group->MinPhase, Entry->Phase);
    Group->MaxPhase = MAX (Group->MaxPhase, Entry->Phase);
  }

  Images = LtCollectImages ();
  DEBUG ((
    DEBUG_ERROR,
    "LEAKTRACK %a phase %u: live %lu allocs %lu bytes, groups %lu, overflow %lu, peak %lu\n",
    Label,
    mPhase,
    mUsed,
    Bytes,
    Groups,
    mOverflow,
    mPeak
    ));
  for (Index = 0; Index < Groups; Index++) {
    Group = &mGroups[Index];
    Name  = LtFindImage (Group->Caller, Images, &Offset);
    DEBUG ((
      DEBUG_ERROR,
      "LEAKTRACK  n=%u bytes=%lu %a type=%u phase=%u-%u caller=%a+%lx chain=%x,%x,%x\n",
      Group->Count,
      Group->Bytes,
      Group->Pages ? "pages" : "pool",
      Group->Type,
      Group->MinPhase,
      Group->MaxPhase,
      Name,
      Offset,
      Group->Chain[0],
      Group->Chain[1],
      Group->Chain[2]
      ));
  }

  mPhase++;
  mActive = TRUE;
}

/**
  Restores gBS allocation services. Call last in the unload handler.
**/
VOID
LeakTrackEnd (
  VOID
  )
{
  EFI_TPL  OldTpl;

  if (mOrgAllocatePool == NULL) {
    return;
  }

  OldTpl             = gBS->RaiseTPL (TPL_HIGH_LEVEL);
  mActive            = FALSE;
  gBS->AllocatePool  = mOrgAllocatePool;
  gBS->FreePool      = mOrgFreePool;
  gBS->AllocatePages = mOrgAllocatePages;
  gBS->FreePages     = mOrgFreePages;
  LtUpdateCrc ();
  gBS->RestoreTPL (OldTpl);

  gBS->FreePages ((UINTN)mEntries, EFI_SIZE_TO_PAGES (LT_SLOTS * sizeof (LT_ENTRY)));
  mEntries = NULL;
}
