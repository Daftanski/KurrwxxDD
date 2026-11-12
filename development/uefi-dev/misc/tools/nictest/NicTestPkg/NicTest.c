/** @file
  nictest.efi - checks of the CNIC driver protocols from the UEFI Shell.

  Usage: nictest <cn2|health|aip|fmp|nii|snp|snpf|ver|cdb> [driver name part]
         nictest eatmem alloc [pages to leave free]   (default 2048)
         nictest eatmem free
         nictest ebs                                  (ExitBootServices, then dead loop)
  Output: one "NICTEST <cmd> <item> <field>=<value> ..." line per check.
  Status values are printed as %r (Success, Unsupported, ...).
**/

#include <Uefi.h>
#include <Uefi/UefiPxe.h>
#include <Library/BaseLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/DevicePathLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiLib.h>
#include <Library/UefiRuntimeServicesTableLib.h>
#include <Protocol/AdapterInformation.h>
#include <Protocol/ComponentName2.h>
#include <Protocol/DevicePath.h>
#include <Protocol/DriverHealth.h>
#include <Protocol/DriverSupportedEfiVersion.h>
#include <Protocol/FirmwareManagement.h>
#include <Protocol/HiiConfigAccess.h>
#include <Protocol/NetworkInterfaceIdentifier.h>
#include <Protocol/PciIo.h>
#include <Protocol/ShellParameters.h>
#include <Protocol/SimpleNetwork.h>
#include <Protocol/VlanConfig.h>

#define DEFAULT_DRIVER_NAME  L"CNIC"
#define ETHER_ADDR_LEN       6
#define EAT_MAX_CHUNKS       128
#define EAT_DEFAULT_LEAVE    2048
#define EAT_VARIABLE_NAME    L"NicTestEat"

typedef struct {
  EFI_PHYSICAL_ADDRESS    Base;
  UINT64                  Pages;
} EAT_CHUNK;

STATIC EFI_GUID  mEatGuid = { 0x5C0D3A91, 0x77E1, 0x4B1F, { 0x9E, 0x24, 0x6A, 0x0F, 0x31, 0xD7, 0xC8, 0x42 } };

STATIC EFI_HANDLE  mDriver;
STATIC EFI_HANDLE  *mChildren;
STATIC UINTN       mChildCount;

/**
  Finds the children of mDriver: handles for which mDriver opened a PCI IO
  BY_CHILD_CONTROLLER. Works for any PCI driver, not only NICs.
**/
STATIC
EFI_STATUS
FindChildren (
  VOID
  )
{
  EFI_STATUS                           Status;
  EFI_HANDLE                           *Handles;
  UINTN                                Count;
  UINTN                                Index;
  EFI_OPEN_PROTOCOL_INFORMATION_ENTRY  *Info;
  UINTN                                InfoCount;
  UINTN                                Entry;

  Status = gBS->LocateHandleBuffer (ByProtocol, &gEfiPciIoProtocolGuid, NULL, &Count, &Handles);
  if (EFI_ERROR (Status)) {
    return Status;
  }

  for (Index = 0; Index < Count; Index++) {
    Status = gBS->OpenProtocolInformation (Handles[Index], &gEfiPciIoProtocolGuid, &Info, &InfoCount);
    if (EFI_ERROR (Status)) {
      continue;
    }

    for (Entry = 0; Entry < InfoCount; Entry++) {
      if ((Info[Entry].AgentHandle != mDriver) || ((Info[Entry].Attributes & EFI_OPEN_PROTOCOL_BY_CHILD_CONTROLLER) == 0)) {
        continue;
      }

      mChildren = ReallocatePool (mChildCount * sizeof (EFI_HANDLE), (mChildCount + 1) * sizeof (EFI_HANDLE), mChildren);
      if (mChildren == NULL) {
        FreePool (Info);
        FreePool (Handles);
        return EFI_OUT_OF_RESOURCES;
      }

      mChildren[mChildCount++] = Info[Entry].ControllerHandle;
    }

    FreePool (Info);
  }

  FreePool (Handles);
  return mChildCount == 0 ? EFI_NOT_FOUND : EFI_SUCCESS;
}

/**
  Finds the driver image (ComponentName2 name contains Part) and its
  children.
**/
STATIC
EFI_STATUS
FindDriver (
  IN CHAR16  *Part
  )
{
  EFI_STATUS                    Status;
  EFI_HANDLE                    *Handles;
  UINTN                         Count;
  UINTN                         Index;
  EFI_COMPONENT_NAME2_PROTOCOL  *Cn2;
  CHAR16                        *Name;

  Status = gBS->LocateHandleBuffer (ByProtocol, &gEfiComponentName2ProtocolGuid, NULL, &Count, &Handles);
  if (EFI_ERROR (Status)) {
    return Status;
  }

  for (Index = 0; Index < Count && mDriver == NULL; Index++) {
    Status = gBS->HandleProtocol (Handles[Index], &gEfiComponentName2ProtocolGuid, (VOID **)&Cn2);
    if (EFI_ERROR (Status)) {
      continue;
    }

    Status = Cn2->GetDriverName (Cn2, "en-US", &Name);
    if (EFI_ERROR (Status)) {
      Status = Cn2->GetDriverName (Cn2, "en", &Name);
    }

    if (!EFI_ERROR (Status) && (StrStr (Name, Part) != NULL)) {
      mDriver = Handles[Index];
    }
  }

  FreePool (Handles);
  if (mDriver == NULL) {
    return EFI_NOT_FOUND;
  }

  return FindChildren ();
}

/**
  Returns the controller (PCI IO) handle above a child.
**/
STATIC
EFI_HANDLE
ControllerOf (
  IN EFI_HANDLE  Child
  )
{
  EFI_STATUS                Status;
  EFI_DEVICE_PATH_PROTOCOL  *Path;
  EFI_HANDLE                Controller;

  Status = gBS->HandleProtocol (Child, &gEfiDevicePathProtocolGuid, (VOID **)&Path);
  if (EFI_ERROR (Status)) {
    return NULL;
  }

  Status = gBS->LocateDevicePath (&gEfiPciIoProtocolGuid, &Path, &Controller);
  if (EFI_ERROR (Status)) {
    return NULL;
  }

  return Controller;
}

STATIC
VOID
PrintChildPath (
  IN UINTN  Index
  )
{
  EFI_DEVICE_PATH_PROTOCOL  *Path;
  CHAR16                    *Text;

  Text = NULL;
  if (!EFI_ERROR (gBS->HandleProtocol (mChildren[Index], &gEfiDevicePathProtocolGuid, (VOID **)&Path))) {
    Text = ConvertDevicePathToText (Path, FALSE, FALSE);
  }

  Print (L"NICTEST child %u handle=%p path=%s\n", Index, mChildren[Index], Text == NULL ? L"?" : Text);
  if (Text != NULL) {
    FreePool (Text);
  }
}

STATIC
VOID
TestCn2 (
  VOID
  )
{
  EFI_STATUS                    Status;
  EFI_COMPONENT_NAME2_PROTOCOL  *Cn2;
  CHAR8                         Lang[16];
  CHAR8                         *Pos;
  UINTN                         Len;
  UINTN                         Index;
  CHAR16                        *Name;
  EFI_HANDLE                    Controller;

  Status = gBS->HandleProtocol (mDriver, &gEfiComponentName2ProtocolGuid, (VOID **)&Cn2);
  Print (L"NICTEST cn2 protocol status=%r languages=%a\n", Status, EFI_ERROR (Status) ? "" : Cn2->SupportedLanguages);
  if (EFI_ERROR (Status)) {
    return;
  }

  for (Pos = Cn2->SupportedLanguages; *Pos != '\0'; Pos += Len + (Pos[Len] == ';')) {
    for (Len = 0; Pos[Len] != '\0' && Pos[Len] != ';'; Len++) {
    }

    AsciiStrnCpyS (Lang, sizeof (Lang), Pos, MIN (Len, sizeof (Lang) - 1));
    Status = Cn2->GetDriverName (Cn2, Lang, &Name);
    Print (L"NICTEST cn2 driver lang=%a status=%r name=%s\n", Lang, Status, EFI_ERROR (Status) ? L"" : Name);
  }

  Status = Cn2->GetDriverName (Cn2, "xx-XX", &Name);
  Print (L"NICTEST cn2 driver lang=xx-XX status=%r\n", Status);
  Status = Cn2->GetDriverName (Cn2, NULL, &Name);
  Print (L"NICTEST cn2 driver lang=NULL status=%r\n", Status);
  Status = Cn2->GetDriverName (Cn2, "en-US", NULL);
  Print (L"NICTEST cn2 driver name=NULL status=%r\n", Status);

  for (Index = 0; Index < mChildCount; Index++) {
    Controller = ControllerOf (mChildren[Index]);
    Status     = Cn2->GetControllerName (Cn2, Controller, NULL, "en-US", &Name);
    Print (L"NICTEST cn2 ctrl %u status=%r name=%s\n", Index, Status, EFI_ERROR (Status) ? L"" : Name);
    Status = Cn2->GetControllerName (Cn2, Controller, mChildren[Index], "en-US", &Name);
    Print (L"NICTEST cn2 child %u status=%r name=%s\n", Index, Status, EFI_ERROR (Status) ? L"" : Name);
  }

  Status = Cn2->GetControllerName (Cn2, mDriver, NULL, "en-US", &Name);
  Print (L"NICTEST cn2 ctrl foreign status=%r\n", Status);
}

STATIC
VOID
TestHealth (
  VOID
  )
{
  EFI_STATUS                     Status;
  EFI_DRIVER_HEALTH_PROTOCOL     *Health;
  EFI_DRIVER_HEALTH_STATUS       HealthStatus;
  EFI_DRIVER_HEALTH_HII_MESSAGE  *Messages;
  EFI_HII_HANDLE                 Form;
  UINTN                          Index;

  Status = gBS->HandleProtocol (mDriver, &gEfiDriverHealthProtocolGuid, (VOID **)&Health);
  Print (L"NICTEST health protocol status=%r\n", Status);
  if (EFI_ERROR (Status)) {
    return;
  }

  Messages = NULL;
  Form     = NULL;
  Status   = Health->GetHealthStatus (Health, NULL, NULL, &HealthStatus, &Messages, &Form);
  Print (L"NICTEST health driver status=%r health=%u messages=%p form=%p\n", Status, HealthStatus, Messages, Form);

  for (Index = 0; Index < mChildCount; Index++) {
    Messages = NULL;
    Form     = NULL;
    Status   = Health->GetHealthStatus (Health, ControllerOf (mChildren[Index]), NULL, &HealthStatus, &Messages, &Form);
    Print (L"NICTEST health ctrl %u status=%r health=%u messages=%p\n", Index, Status, HealthStatus, Messages);
    Messages = NULL;
    Status   = Health->GetHealthStatus (Health, ControllerOf (mChildren[Index]), mChildren[Index], &HealthStatus, &Messages, &Form);
    Print (L"NICTEST health child %u status=%r health=%u messages=%p\n", Index, Status, HealthStatus, Messages);
  }

  Status = Health->GetHealthStatus (Health, mDriver, NULL, &HealthStatus, NULL, NULL);
  Print (L"NICTEST health ctrl foreign status=%r\n", Status);
}

STATIC
VOID
TestAip (
  VOID
  )
{
  EFI_STATUS                        Status;
  EFI_ADAPTER_INFORMATION_PROTOCOL  *Aip;
  EFI_GUID                          *Types;
  UINTN                             TypeCount;
  UINTN                             Index;
  UINTN                             Type;
  VOID                              *Block;
  UINTN                             Size;
  EFI_ADAPTER_INFO_MEDIA_STATE      Media;

  for (Index = 0; Index < mChildCount; Index++) {
    Status = gBS->HandleProtocol (mChildren[Index], &gEfiAdapterInformationProtocolGuid, (VOID **)&Aip);
    Print (L"NICTEST aip %u protocol status=%r\n", Index, Status);
    if (EFI_ERROR (Status)) {
      continue;
    }

    Status = Aip->GetSupportedTypes (Aip, &Types, &TypeCount);
    Print (L"NICTEST aip %u types status=%r count=%u\n", Index, Status, EFI_ERROR (Status) ? 0 : TypeCount);
    for (Type = 0; !EFI_ERROR (Status) && Type < TypeCount; Type++) {
      Block       = NULL;
      Size        = 0;
      Status      = Aip->GetInformation (Aip, &Types[Type], &Block, &Size);
      Print (L"NICTEST aip %u get %g status=%r size=%u\n", Index, &Types[Type], Status, Size);
      if (!EFI_ERROR (Status) && CompareGuid (&Types[Type], &gEfiAdapterInfoMediaStateGuid)) {
        Print (L"NICTEST aip %u media state=%r\n", Index, ((EFI_ADAPTER_INFO_MEDIA_STATE *)Block)->MediaState);
      }

      if (!EFI_ERROR (Status) && CompareGuid (&Types[Type], &gEfiAdapterInfoUndiIpv6SupportGuid)) {
        Print (L"NICTEST aip %u ipv6 support=%u\n", Index, ((EFI_ADAPTER_INFO_UNDI_IPV6_SUPPORT *)Block)->Ipv6Support);
      }

      if (Block != NULL) {
        FreePool (Block);
      }

      Status = EFI_SUCCESS;
    }

    if (!EFI_ERROR (Status)) {
      FreePool (Types);
    }

    Block  = NULL;
    Status = Aip->GetInformation (Aip, &gEfiCallerIdGuid, &Block, &Size);
    Print (L"NICTEST aip %u get unknown status=%r\n", Index, Status);
    Media.MediaState = EFI_SUCCESS;
    Status           = Aip->SetInformation (Aip, &gEfiAdapterInfoMediaStateGuid, &Media, sizeof (Media));
    Print (L"NICTEST aip %u set media status=%r\n", Index, Status);
  }
}

STATIC
VOID
TestFmp (
  VOID
  )
{
  EFI_STATUS                        Status;
  EFI_FIRMWARE_MANAGEMENT_PROTOCOL  *Fmp;
  EFI_FIRMWARE_IMAGE_DESCRIPTOR     *Info;
  EFI_FIRMWARE_IMAGE_DESCRIPTOR     *Desc;
  UINTN                             Size;
  UINT32                            DescVersion;
  UINT8                             DescCount;
  UINTN                             DescSize;
  UINT32                            PackageVersion;
  CHAR16                            *PackageName;
  UINT32                            Updatable;
  UINT8                             *Junk;
  UINTN                             Index;
  UINTN                             Item;
  UINT32                            NameMaxLen;
  UINT64                            Attributes;
  UINT64                            Supported;
  CHAR16                            *Abort;

  for (Index = 0; Index < mChildCount; Index++) {
    Status = gBS->HandleProtocol (mChildren[Index], &gEfiFirmwareManagementProtocolGuid, (VOID **)&Fmp);
    if (EFI_ERROR (Status)) {
      continue;
    }

    Size   = 0;
    Status = Fmp->GetImageInfo (Fmp, &Size, NULL, &DescVersion, &DescCount, &DescSize, &PackageVersion, &PackageName);
    Print (L"NICTEST fmp %u info-size status=%r size=%u\n", Index, Status, Size);
    if (Status != EFI_BUFFER_TOO_SMALL) {
      continue;
    }

    Info   = AllocateZeroPool (Size);
    Status = Fmp->GetImageInfo (Fmp, &Size, Info, &DescVersion, &DescCount, &DescSize, &PackageVersion, &PackageName);
    Print (L"NICTEST fmp %u info status=%r descver=%u count=%u package=%x\n", Index, Status, DescVersion, DescCount, PackageVersion);
    for (Item = 0; !EFI_ERROR (Status) && Item < DescCount; Item++) {
      Desc = (EFI_FIRMWARE_IMAGE_DESCRIPTOR *)((UINT8 *)Info + Item * DescSize);
      Print (
        L"NICTEST fmp %u image %u index=%u id=%lx type=%g version=%x name=%s size=%lu attr=%lx\n",
        Index,
        Item,
        Desc->ImageIndex,
        Desc->ImageId,
        &Desc->ImageTypeId,
        Desc->Version,
        Desc->VersionName == NULL ? L"" : Desc->VersionName,
        Desc->Size,
        Desc->AttributesSetting
        );
    }

    Status = Fmp->GetPackageInfo (Fmp, &PackageVersion, &PackageName, &NameMaxLen, &Supported, &Attributes);
    Print (L"NICTEST fmp %u package status=%r\n", Index, Status);

    Junk = AllocatePool (SIZE_4KB);
    SetMem (Junk, SIZE_4KB, 0xA5);
    Updatable = 0;
    Status    = Fmp->CheckImage (Fmp, 1, Junk, 0, &Updatable);
    Print (L"NICTEST fmp %u check empty status=%r updatable=%x\n", Index, Status, Updatable);
    Updatable = 0;
    Status    = Fmp->CheckImage (Fmp, 1, Junk, SIZE_4KB, &Updatable);
    Print (L"NICTEST fmp %u check junk status=%r updatable=%x\n", Index, Status, Updatable);
    Status = Fmp->CheckImage (Fmp, 0xFF, Junk, SIZE_4KB, &Updatable);
    Print (L"NICTEST fmp %u check badindex status=%r\n", Index, Status);
    Status = Fmp->CheckImage (Fmp, 1, NULL, SIZE_4KB, &Updatable);
    Print (L"NICTEST fmp %u check null status=%r\n", Index, Status);
    Abort  = NULL;
    Status = Fmp->SetImage (Fmp, 1, Junk, SIZE_4KB, NULL, NULL, &Abort);
    Print (L"NICTEST fmp %u set junk status=%r\n", Index, Status);
    Status = Fmp->SetImage (Fmp, 1, NULL, SIZE_4KB, NULL, NULL, &Abort);
    Print (L"NICTEST fmp %u set null status=%r\n", Index, Status);
    Status = Fmp->SetImage (Fmp, 1, Junk, 0, NULL, NULL, &Abort);
    Print (L"NICTEST fmp %u set empty status=%r\n", Index, Status);
    FreePool (Junk);
    FreePool (Info);
  }
}

STATIC
UINT8
Sum8 (
  IN UINT8  *Data,
  IN UINTN  Len
  )
{
  UINT8  Sum;

  for (Sum = 0; Len > 0; Len--) {
    Sum = (UINT8)(Sum + *Data++);
  }

  return Sum;
}

STATIC
VOID
TestNii (
  VOID
  )
{
  EFI_STATUS                                 Status;
  EFI_NETWORK_INTERFACE_IDENTIFIER_PROTOCOL  *Nii;
  PXE_SW_UNDI                                *Undi;
  UINTN                                      Index;

  for (Index = 0; Index < mChildCount; Index++) {
    PrintChildPath (Index);
    Status = gBS->HandleProtocol (mChildren[Index], &gEfiNetworkInterfaceIdentifierProtocolGuid_31, (VOID **)&Nii);
    if (EFI_ERROR (Status)) {
      continue;
    }

    Print (
      L"NICTEST nii %u revision=%lx type=%u ver=%u.%u ipv6=%u ifnum=%u id=%lx\n",
      Index,
      Nii->Revision,
      Nii->Type,
      Nii->MajorVer,
      Nii->MinorVer,
      Nii->Ipv6Supported,
      Nii->IfNum,
      Nii->Id
      );
    if (Nii->Id == 0) {
      continue;
    }

    Undi = (PXE_SW_UNDI *)(UINTN)Nii->Id;
    Print (
      L"NICTEST nii %u pxe signature=%u len=%u sum=%u rev=%u ifcnt=%u ver=%u.%u impl=%x entry=%lx\n",
      Index,
      Undi->Signature == PXE_ROMID_SIGNATURE,
      Undi->Len,
      Sum8 ((UINT8 *)Undi, Undi->Len),
      Undi->Rev,
      Undi->IFcnt | (Undi->IFcntExt << 8),
      Undi->MajorVer,
      Undi->MinorVer,
      Undi->Implementation,
      Undi->EntryPoint
      );
  }
}

STATIC
VOID
TestSnp (
  VOID
  )
{
  EFI_STATUS                   Status;
  EFI_SIMPLE_NETWORK_PROTOCOL  *Snp;
  EFI_SIMPLE_NETWORK_MODE      *Mode;
  EFI_NETWORK_STATISTICS       Stats;
  UINTN                        StatsSize;
  EFI_IP_ADDRESS               Ip;
  EFI_MAC_ADDRESS              Mac;
  UINTN                        Index;

  for (Index = 0; Index < mChildCount; Index++) {
    Status = gBS->HandleProtocol (mChildren[Index], &gEfiSimpleNetworkProtocolGuid, (VOID **)&Snp);
    Print (L"NICTEST snp %u protocol status=%r\n", Index, Status);
    if (EFI_ERROR (Status)) {
      continue;
    }

    Mode = Snp->Mode;
    Print (
      L"NICTEST snp %u mode state=%u maxpacket=%u header=%u filtermask=%x filter=%x mcastmax=%u mcast=%u changeable=%u multitx=%u mediasupported=%u media=%u\n",
      Index,
      Mode->State,
      Mode->MaxPacketSize,
      Mode->MediaHeaderSize,
      Mode->ReceiveFilterMask,
      Mode->ReceiveFilterSetting,
      Mode->MaxMCastFilterCount,
      Mode->MCastFilterCount,
      Mode->MacAddressChangeable,
      Mode->MultipleTxSupported,
      Mode->MediaPresentSupported,
      Mode->MediaPresent
      );
    Print (
      L"NICTEST snp %u mac current=%02x%02x%02x%02x%02x%02x permanent=%02x%02x%02x%02x%02x%02x\n",
      Index,
      Mode->CurrentAddress.Addr[0], Mode->CurrentAddress.Addr[1], Mode->CurrentAddress.Addr[2],
      Mode->CurrentAddress.Addr[3], Mode->CurrentAddress.Addr[4], Mode->CurrentAddress.Addr[5],
      Mode->PermanentAddress.Addr[0], Mode->PermanentAddress.Addr[1], Mode->PermanentAddress.Addr[2],
      Mode->PermanentAddress.Addr[3], Mode->PermanentAddress.Addr[4], Mode->PermanentAddress.Addr[5]
      );

    StatsSize = sizeof (Stats);
    ZeroMem (&Stats, sizeof (Stats));
    Status = Snp->Statistics (Snp, FALSE, &StatsSize, &Stats);
    Print (
      L"NICTEST snp %u stats status=%r rxtotal=%lu rxgood=%lu rxdropped=%lu txtotal=%lu txgood=%lu\n",
      Index,
      Status,
      Stats.RxTotalFrames,
      Stats.RxGoodFrames,
      Stats.RxDroppedFrames,
      Stats.TxTotalFrames,
      Stats.TxGoodFrames
      );

    ZeroMem (&Ip, sizeof (Ip));
    Ip.v4.Addr[0] = 224;
    Ip.v4.Addr[3] = 1;
    ZeroMem (&Mac, sizeof (Mac));
    Status = Snp->MCastIpToMac (Snp, FALSE, &Ip, &Mac);
    Print (L"NICTEST snp %u mcast4 status=%r mac=%02x%02x%02x%02x%02x%02x\n", Index, Status, Mac.Addr[0], Mac.Addr[1], Mac.Addr[2], Mac.Addr[3], Mac.Addr[4], Mac.Addr[5]);

    ZeroMem (&Ip, sizeof (Ip));
    Ip.v6.Addr[0]  = 0xFF;
    Ip.v6.Addr[1]  = 0x02;
    Ip.v6.Addr[15] = 0x01;
    ZeroMem (&Mac, sizeof (Mac));
    Status = Snp->MCastIpToMac (Snp, TRUE, &Ip, &Mac);
    Print (L"NICTEST snp %u mcast6 status=%r mac=%02x%02x%02x%02x%02x%02x\n", Index, Status, Mac.Addr[0], Mac.Addr[1], Mac.Addr[2], Mac.Addr[3], Mac.Addr[4], Mac.Addr[5]);
  }
}

STATIC
VOID
TestVer (
  VOID
  )
{
  EFI_STATUS                                  Status;
  EFI_DRIVER_SUPPORTED_EFI_VERSION_PROTOCOL  *Ver;

  Status = gBS->HandleProtocol (mDriver, &gEfiDriverSupportedEfiVersionProtocolGuid, (VOID **)&Ver);
  Print (L"NICTEST ver status=%r length=%u version=%x\n", Status, EFI_ERROR (Status) ? 0 : Ver->Length, EFI_ERROR (Status) ? 0 : Ver->FirmwareVersion);
}

/**
  Changes and restores SNP receive filters, multicast list, station address
  and statistics on each child.
**/
STATIC
VOID
TestSnpFilters (
  VOID
  )
{
  EFI_STATUS                   Status;
  EFI_SIMPLE_NETWORK_PROTOCOL  *Snp;
  EFI_SIMPLE_NETWORK_MODE      *Mode;
  EFI_MAC_ADDRESS              Mcast;
  EFI_MAC_ADDRESS              Mac;
  EFI_MAC_ADDRESS              SavedMcast[MAX_MCAST_FILTER_CNT];
  UINTN                        SavedMcastCount;
  UINT32                       Saved;
  UINT32                       Bit;
  UINTN                        Index;

  for (Index = 0; Index < mChildCount; Index++) {
    Status = gBS->HandleProtocol (mChildren[Index], &gEfiSimpleNetworkProtocolGuid, (VOID **)&Snp);
    if (EFI_ERROR (Status)) {
      continue;
    }

    Mode  = Snp->Mode;
    Saved = Mode->ReceiveFilterSetting;
    SavedMcastCount = MIN (Mode->MCastFilterCount, MAX_MCAST_FILTER_CNT);
    CopyMem (SavedMcast, Mode->MCastFilter, SavedMcastCount * sizeof (EFI_MAC_ADDRESS));
    Print (L"NICTEST snpf %u start state=%u mask=%x filter=%x mcast=%u\n", Index, Mode->State, Mode->ReceiveFilterMask, Saved, Mode->MCastFilterCount);

    for (Bit = 1; Bit <= EFI_SIMPLE_NETWORK_RECEIVE_PROMISCUOUS_MULTICAST; Bit <<= 1) {
      if (Bit == EFI_SIMPLE_NETWORK_RECEIVE_MULTICAST) {
        continue;
      }

      Status = Snp->ReceiveFilters (Snp, Bit, 0, FALSE, 0, NULL);
      Print (L"NICTEST snpf %u enable %x status=%r supported=%u set=%u\n", Index, Bit, Status, (Mode->ReceiveFilterMask & Bit) != 0, (Mode->ReceiveFilterSetting & Bit) != 0);
      if ((Saved & Bit) == 0) {
        Status = Snp->ReceiveFilters (Snp, 0, Bit, FALSE, 0, NULL);
        Print (L"NICTEST snpf %u disable %x status=%r set=%u\n", Index, Bit, Status, (Mode->ReceiveFilterSetting & Bit) != 0);
      }
    }

    ZeroMem (&Mcast, sizeof (Mcast));
    Mcast.Addr[0] = 0x01;
    Mcast.Addr[2] = 0x5E;
    Mcast.Addr[5] = 0xFB;
    Status        = Snp->ReceiveFilters (Snp, EFI_SIMPLE_NETWORK_RECEIVE_MULTICAST, 0, FALSE, 1, &Mcast);
    Print (L"NICTEST snpf %u mcast add status=%r count=%u\n", Index, Status, Mode->MCastFilterCount);
    Mcast.Addr[0] = 0x02;
    Status        = Snp->ReceiveFilters (Snp, EFI_SIMPLE_NETWORK_RECEIVE_MULTICAST, 0, FALSE, 1, &Mcast);
    Print (L"NICTEST snpf %u mcast unicast status=%r\n", Index, Status);
    Status = Snp->ReceiveFilters (Snp, 0, 0, TRUE, 0, NULL);
    Print (L"NICTEST snpf %u mcast reset status=%r count=%u\n", Index, Status, Mode->MCastFilterCount);
    Status = Snp->ReceiveFilters (Snp, Saved, (UINT32)~Saved & Mode->ReceiveFilterMask, FALSE, SavedMcastCount, SavedMcastCount != 0 ? SavedMcast : NULL);
    Print (L"NICTEST snpf %u restore status=%r filter=%x mcast=%u\n", Index, Status, Mode->ReceiveFilterSetting, Mode->MCastFilterCount);

    CopyMem (&Mac, &Mode->CurrentAddress, sizeof (Mac));
    Mac.Addr[5] ^= 0x80;
    Status       = Snp->StationAddress (Snp, FALSE, &Mac);
    Print (L"NICTEST snpf %u station new status=%r changeable=%u same=%u\n", Index, Status, Mode->MacAddressChangeable, CompareMem (&Mac, &Mode->CurrentAddress, ETHER_ADDR_LEN) == 0);
    Status = Snp->StationAddress (Snp, TRUE, NULL);
    Print (L"NICTEST snpf %u station reset status=%r permanent=%u\n", Index, Status, CompareMem (&Mode->PermanentAddress, &Mode->CurrentAddress, ETHER_ADDR_LEN) == 0);

    Status = Snp->Statistics (Snp, TRUE, NULL, NULL);
    Print (L"NICTEST snpf %u stats reset status=%r\n", Index, Status);
  }
}

/**
  Counts the free (conventional) pages of the memory map; Low: only below 4 GB.
**/
STATIC
UINTN
FreePageCount (
  IN BOOLEAN  Low
  )
{
  EFI_STATUS             Status;
  EFI_MEMORY_DESCRIPTOR  *Map;
  EFI_MEMORY_DESCRIPTOR  *Desc;
  UINTN                  Size;
  UINTN                  Key;
  UINTN                  DescSize;
  UINT32                 Version;
  UINTN                  Pages;
  UINT64                 End;

  Size   = 0;
  Status = gBS->GetMemoryMap (&Size, NULL, &Key, &DescSize, &Version);
  Size  += 4 * DescSize;
  Map    = AllocatePool (Size);
  if (Map == NULL) {
    return 0;
  }

  Pages  = 0;
  Status = gBS->GetMemoryMap (&Size, Map, &Key, &DescSize, &Version);
  if (!EFI_ERROR (Status)) {
    for (Desc = Map; (UINT8 *)Desc < (UINT8 *)Map + Size; Desc = NEXT_MEMORY_DESCRIPTOR (Desc, DescSize)) {
      if (Desc->Type != EfiConventionalMemory) {
        continue;
      }

      End = Desc->PhysicalStart + EFI_PAGES_TO_SIZE (Desc->NumberOfPages);
      if (!Low) {
        Pages += Desc->NumberOfPages;
      } else if (Desc->PhysicalStart < SIZE_4GB) {
        Pages += EFI_SIZE_TO_PAGES (MIN (End, SIZE_4GB) - Desc->PhysicalStart);
      }
    }
  }

  FreePool (Map);
  return Pages;
}

/**
  Allocates all free memory except Leave pages. The chunk list is kept in a
  volatile variable so that a later "eatmem free" can release it.
**/
STATIC
VOID
EatMemAlloc (
  IN UINTN  Leave
  )
{
  EFI_STATUS            Status;
  EAT_CHUNK             Chunks[EAT_MAX_CHUNKS];
  UINTN                 Count;
  UINTN                 Free;
  UINTN                 Take;
  UINT64                Chunk;
  UINT64                Total;
  EFI_PHYSICAL_ADDRESS  Base;
  BOOLEAN               Low;

  Count = 0;
  Total = 0;
  for (Low = FALSE; Count < EAT_MAX_CHUNKS; Low = TRUE) {
    Chunk = BIT32;
    while (Count < EAT_MAX_CHUNKS) {
      Free = FreePageCount (Low);
      if (Free <= Leave) {
        break;
      }

      Take   = (UINTN)MIN ((UINT64)(Free - Leave), Chunk);
      Base   = SIZE_4GB - 1;
      Status = gBS->AllocatePages (Low ? AllocateMaxAddress : AllocateAnyPages, EfiBootServicesData, Take, &Base);
      if (EFI_ERROR (Status)) {
        if (Chunk == 1) {
          break;
        }

        Chunk >>= 1;
        continue;
      }

      Chunks[Count].Base  = Base;
      Chunks[Count].Pages = Take;
      Count++;
      Total += Take;
    }

    if (Low) {
      break;
    }
  }

  Status = gRT->SetVariable (EAT_VARIABLE_NAME, &mEatGuid, EFI_VARIABLE_BOOTSERVICE_ACCESS, Count * sizeof (EAT_CHUNK), Chunks);
  Print (L"NICTEST eatmem alloc status=%r chunks=%u pages=%lu free=%u low=%u\n", Status, Count, Total, FreePageCount (FALSE), FreePageCount (TRUE));
}

STATIC
VOID
EatMemFree (
  VOID
  )
{
  EFI_STATUS  Status;
  EAT_CHUNK   Chunks[EAT_MAX_CHUNKS];
  UINTN       Size;
  UINTN       Index;
  UINTN       Failed;

  Size   = sizeof (Chunks);
  Status = gRT->GetVariable (EAT_VARIABLE_NAME, &mEatGuid, NULL, &Size, Chunks);
  if (EFI_ERROR (Status)) {
    Print (L"NICTEST eatmem free status=%r chunks=0\n", Status);
    return;
  }

  Failed = 0;
  for (Index = 0; Index < Size / sizeof (EAT_CHUNK); Index++) {
    if (EFI_ERROR (gBS->FreePages (Chunks[Index].Base, (UINTN)Chunks[Index].Pages))) {
      Failed++;
    }
  }

  gRT->SetVariable (EAT_VARIABLE_NAME, &mEatGuid, 0, 0, NULL);
  Print (L"NICTEST eatmem free status=Success chunks=%u failed=%u free=%u\n", Size / sizeof (EAT_CHUNK), Failed, FreePageCount (FALSE));
}

/**
  ExitBootServices, then a dead loop. The console is gone afterwards: the
  test looks at Simics.
**/
STATIC
VOID
TestEbs (
  VOID
  )
{
  EFI_STATUS             Status;
  EFI_MEMORY_DESCRIPTOR  *Map;
  UINTN                  Size;
  UINTN                  Key;
  UINTN                  DescSize;
  UINT32                 Version;
  UINTN                  Try;

  Print (L"NICTEST ebs go\n");
  for (Try = 0; Try < 8; Try++) {
    Size   = 0;
    Status = gBS->GetMemoryMap (&Size, NULL, &Key, &DescSize, &Version);
    Size  += 8 * DescSize;
    Map    = AllocatePool (Size);
    if ((Map == NULL) || EFI_ERROR (gBS->GetMemoryMap (&Size, Map, &Key, &DescSize, &Version))) {
      continue;
    }

    Status = gBS->ExitBootServices (gImageHandle, Key);
    if (!EFI_ERROR (Status)) {
      CpuDeadLoop ();
    }
  }

  Print (L"NICTEST ebs failed status=%r\n", Status);
}

/**
  Sends one CDB to the UNDI entry point and prints the status it returns.
**/
STATIC
VOID
RunCdb (
  IN PXE_SW_UNDI  *Undi,
  IN UINT16       IfNum,
  IN UINTN        Child,
  IN CHAR16       *Name,
  IN UINT16       OpCode,
  IN UINT16       CpbSize,
  IN UINT16       DbSize,
  IN VOID         *Cpb,
  IN VOID         *Db
  )
{
  PXE_CDB  Cdb;

  ZeroMem (&Cdb, sizeof (Cdb));
  Cdb.OpCode   = OpCode;
  Cdb.OpFlags  = PXE_OPFLAGS_NOT_USED;
  Cdb.CPBsize  = CpbSize;
  Cdb.DBsize   = DbSize;
  Cdb.CPBaddr  = (UINT64)(UINTN)Cpb;
  Cdb.DBaddr   = (UINT64)(UINTN)Db;
  Cdb.StatCode  = PXE_STATCODE_INITIALIZE;
  Cdb.StatFlags = PXE_STATFLAGS_INITIALIZE;
  Cdb.IFnum     = IfNum;
  ((VOID (EFIAPI *)(UINT64))(UINTN)Undi->EntryPoint)((UINT64)(UINTN)&Cdb);
  Print (L"NICTEST cdb %u %s stat=%x flags=%x\n", Child, Name, Cdb.StatCode, Cdb.StatFlags);
}

/**
  UNDI commands with bad arguments on each child. Only commands that do not
  change the state are used; a bad one must fail with a status, not crash.
**/
STATIC
VOID
TestCdb (
  VOID
  )
{
  EFI_STATUS                                 Status;
  EFI_NETWORK_INTERFACE_IDENTIFIER_PROTOCOL  *Nii;
  PXE_SW_UNDI                                *Undi;
  UINTN                                      Index;
  UINT8                                      State;

  State = 0;
  for (Index = 0; Index < mChildCount; Index++) {
    Status = gBS->HandleProtocol (mChildren[Index], &gEfiNetworkInterfaceIdentifierProtocolGuid_31, (VOID **)&Nii);
    if (EFI_ERROR (Status) || (Nii->Id == 0)) {
      continue;
    }

    Undi  = (PXE_SW_UNDI *)(UINTN)Nii->Id;
    State = 0xFF;
    RunCdb (Undi, Nii->IfNum, Index, L"getstate", PXE_OPCODE_GET_STATE, 0, 0, NULL, NULL);
    RunCdb (Undi, Nii->IfNum, Index, L"badopcode", 0xFFFF, 0, 0, NULL, NULL);
    RunCdb (Undi, Nii->IfNum, Index, L"reset", PXE_OPCODE_RESET, 0, 0, NULL, NULL);
    RunCdb (Undi, 0xFFFF, Index, L"badifnum", PXE_OPCODE_GET_STATE, 0, 0, NULL, NULL);
    RunCdb (Undi, Nii->IfNum, Index, L"getstate-baddb", PXE_OPCODE_GET_STATE, 0, sizeof (State), NULL, &State);
    RunCdb (Undi, Nii->IfNum, Index, L"start-nocpb", PXE_OPCODE_START, 0, 0, NULL, NULL);
    RunCdb (Undi, Nii->IfNum, Index, L"transmit-nocpb", PXE_OPCODE_TRANSMIT, 0, 0, NULL, NULL);
    RunCdb (Undi, Nii->IfNum, Index, L"receive-nocpb", PXE_OPCODE_RECEIVE, 0, 0, NULL, NULL);
    RunCdb (Undi, Nii->IfNum, Index, L"getstatus-nulldb", PXE_OPCODE_GET_STATUS, 0, 8, NULL, NULL);
  }
}

/**
  HII config access with bad strings on each child: every call must return
  an error (not Success) and not crash.
**/
STATIC
VOID
TestHiiRc (
  VOID
  )
{
  EFI_STATUS                       Status;
  EFI_HII_CONFIG_ACCESS_PROTOCOL   *Hca;
  EFI_STRING                       Progress;
  EFI_STRING                       Results;
  CHAR16                           *Long;
  UINTN                            Index;
  UINTN                            Pos;

  Long = AllocatePool (8192 * sizeof (CHAR16));
  for (Pos = 0; Long != NULL && Pos < 8191; Pos++) {
    Long[Pos] = L'A';
  }

  if (Long != NULL) {
    Long[8191] = L'\0';
  }

  for (Index = 0; Index < mChildCount; Index++) {
    Status = gBS->HandleProtocol (mChildren[Index], &gEfiHiiConfigAccessProtocolGuid, (VOID **)&Hca);
    if (EFI_ERROR (Status)) {
      continue;
    }

    Status = Hca->RouteConfig (Hca, NULL, &Progress);
    Print (L"NICTEST hiirc %u route null status=%r\n", Index, Status);
    Status = Hca->RouteConfig (Hca, L"garbage", &Progress);
    Print (L"NICTEST hiirc %u route garbage status=%r\n", Index, Status);
    Status = Hca->RouteConfig (Hca, L"GUID=00000000000000000000000000000000&NAME=0041&PATH=00&OFFSET=0&WIDTH=1&VALUE=zz", &Progress);
    Print (L"NICTEST hiirc %u route badguid status=%r\n", Index, Status);
    Status = Hca->RouteConfig (Hca, L"OFFSET=FFFFFFFF&WIDTH=FFFFFFFF&VALUE=00", &Progress);
    Print (L"NICTEST hiirc %u route badoffset status=%r\n", Index, Status);
    if (Long != NULL) {
      Status = Hca->RouteConfig (Hca, Long, &Progress);
      Print (L"NICTEST hiirc %u route long status=%r\n", Index, Status);
    }

    Status = Hca->ExtractConfig (Hca, L"GUID=zz", &Progress, &Results);
    Print (L"NICTEST hiirc %u extract garbage status=%r\n", Index, Status);
    Status = Hca->ExtractConfig (Hca, NULL, NULL, &Results);
    Print (L"NICTEST hiirc %u extract noprogress status=%r\n", Index, Status);
  }

  if (Long != NULL) {
    FreePool (Long);
  }
}

/**
  Adds (nictest vlan <child> <id>) or removes (nictest vlan <child> remove <id>)
  a VLAN on a child through EFI_VLAN_CONFIG_PROTOCOL.
**/
STATIC
VOID
TestVlan (
  IN EFI_SHELL_PARAMETERS_PROTOCOL  *Params
  )
{
  EFI_STATUS                Status;
  EFI_VLAN_CONFIG_PROTOCOL  *Vlan;
  UINTN                     Index;
  BOOLEAN                   Remove;
  UINT16                    Id;

  Remove = (BOOLEAN)(Params->Argc > 4 && StrCmp (Params->Argv[3], L"remove") == 0);
  if ((Params->Argc < 4) || (StrDecimalToUintn (Params->Argv[2]) >= mChildCount)) {
    Print (L"Usage: nictest vlan <child> <id> | nictest vlan <child> remove <id>\n");
    return;
  }

  Index  = StrDecimalToUintn (Params->Argv[2]);
  Id     = (UINT16)StrDecimalToUintn (Params->Argv[Remove ? 4 : 3]);
  Status = gBS->HandleProtocol (mChildren[Index], &gEfiVlanConfigProtocolGuid, (VOID **)&Vlan);
  Print (L"NICTEST vlan %u protocol status=%r\n", Index, Status);
  if (EFI_ERROR (Status)) {
    return;
  }

  Status = Remove ? Vlan->Remove (Vlan, Id) : Vlan->Set (Vlan, Id, 0);
  Print (L"NICTEST vlan %u %s %u status=%r\n", Index, Remove ? L"remove" : L"set", Id, Status);
}

/**
  Returns the first PCI IO handle of the CNIC (Intel 8086:12A1), or NULL.
**/
STATIC
EFI_HANDLE
FindCnicController (
  VOID
  )
{
  EFI_STATUS           Status;
  EFI_HANDLE           *Handles;
  UINTN                Count;
  UINTN                Index;
  EFI_PCI_IO_PROTOCOL  *PciIo;
  UINT32               Id;
  EFI_HANDLE           Found;

  Status = gBS->LocateHandleBuffer (ByProtocol, &gEfiPciIoProtocolGuid, NULL, &Count, &Handles);
  if (EFI_ERROR (Status)) {
    return NULL;
  }

  Found = NULL;
  for (Index = 0; Index < Count && Found == NULL; Index++) {
    if (EFI_ERROR (gBS->HandleProtocol (Handles[Index], &gEfiPciIoProtocolGuid, (VOID **)&PciIo))) {
      continue;
    }

    if (!EFI_ERROR (PciIo->Pci.Read (PciIo, EfiPciIoWidthUint32, 0, 1, &Id)) && (Id == 0x12A18086)) {
      Found = Handles[Index];
    }
  }

  FreePool (Handles);
  return Found;
}

/**
  nictest connectrdp <MAC 12 hex digits>: ConnectController on the first CNIC
  controller with a remaining device path of one MAC node (only that child
  is started).
**/
STATIC
VOID
TestConnectRdp (
  IN EFI_SHELL_PARAMETERS_PROTOCOL  *Params
  )
{
  EFI_STATUS  Status;
  struct {
    MAC_ADDR_DEVICE_PATH        Mac;
    EFI_DEVICE_PATH_PROTOCOL    End;
  } Path;
  EFI_HANDLE  Drivers[2];
  EFI_HANDLE  Ctrl;
  CHAR16      *Text;
  UINTN       Byte;
  UINTN       Digit;
  UINTN       Value;

  if (Params->Argc < 3) {
    Print (L"Usage: nictest connectrdp <MAC 12 hex digits>\n");
    return;
  }

  Text = Params->Argv[2];
  if (StrLen (Text) != 12) {
    Print (L"NICTEST connectrdp bad MAC\n");
    return;
  }

  ZeroMem (&Path, sizeof (Path));
  Path.Mac.Header.Type    = MESSAGING_DEVICE_PATH;
  Path.Mac.Header.SubType = MSG_MAC_ADDR_DP;
  SetDevicePathNodeLength (&Path.Mac.Header, sizeof (MAC_ADDR_DEVICE_PATH));
  for (Byte = 0; Byte < ETHER_ADDR_LEN; Byte++) {
    Value = 0;
    for (Digit = 0; Digit < 2; Digit++) {
      CHAR16  C = Text[Byte * 2 + Digit];
      Value = (Value << 4) | (C >= L'a' ? C - L'a' + 10 : (C >= L'A' ? C - L'A' + 10 : C - L'0'));
    }

    Path.Mac.MacAddress.Addr[Byte] = (UINT8)Value;
  }

  Path.Mac.IfType = 1;
  SetDevicePathEndNode (&Path.End);

  Ctrl       = FindCnicController ();
  Drivers[0] = mDriver;
  Drivers[1] = NULL;
  Status     = gBS->ConnectController (Ctrl, Drivers, &Path.Mac.Header, FALSE);
  Print (L"NICTEST connectrdp ctrl=%p status=%r\n", Ctrl, Status);
}

/**
  A foreign agent opens the NII of child 0 EXCLUSIVE, then the driver is
  disconnected from the controller: must return a status (error or
  success), not hang or crash. Everything is restored at the end.
**/
STATIC
VOID
TestHold (
  VOID
  )
{
  EFI_STATUS  Status;
  EFI_HANDLE  Ctrl;
  VOID        *Nii;
  EFI_HANDLE  Drivers[2];

  Ctrl = ControllerOf (mChildren[0]);
  Status = gBS->OpenProtocol (mChildren[0], &gEfiNetworkInterfaceIdentifierProtocolGuid_31, &Nii, gImageHandle, NULL, EFI_OPEN_PROTOCOL_EXCLUSIVE);
  Print (L"NICTEST hold open exclusive status=%r\n", Status);
  if (EFI_ERROR (Status)) {
    return;
  }

  Status = gBS->DisconnectController (Ctrl, mDriver, NULL);
  Print (L"NICTEST hold disconnect status=%r\n", Status);
  Status = gBS->CloseProtocol (mChildren[0], &gEfiNetworkInterfaceIdentifierProtocolGuid_31, gImageHandle, NULL);
  Print (L"NICTEST hold close status=%r\n", Status);
  Drivers[0] = mDriver;
  Drivers[1] = NULL;
  Status     = gBS->DisconnectController (Ctrl, mDriver, NULL);
  Print (L"NICTEST hold disconnect again status=%r\n", Status);
  Status = gBS->ConnectController (Ctrl, Drivers, NULL, TRUE);
  Print (L"NICTEST hold reconnect status=%r\n", Status);
}

/**
  SNP state machine on each child: calls in the wrong state, double
  Start / Initialize / Shutdown / Stop, reinitialize cycles. The children
  start Initialized (the stack above uses them). First the Initialized
  state is checked, then Shutdown + Stop, then the Stopped state. At the
  end the state is restored (Start + Initialize), unless KeepStopped.
**/
STATIC
VOID
TestSnpState (
  IN BOOLEAN  KeepStopped
  )
{
  EFI_STATUS                   Status;
  EFI_SIMPLE_NETWORK_PROTOCOL  *Snp;
  UINTN                        Index;
  UINT8                        Frame[1514];
  UINTN                        Size;
  UINT32                       Interrupt;
  UINTN                        Cycle;

#define SNPST(Name, Expr)  do {                                                                  \
    Status = (Expr);                                                                             \
    Print (L"NICTEST snpst %u %a status=%r state=%u\n", Index, Name, Status, Snp->Mode->State);  \
  } while (0)

  SetMem (Frame, sizeof (Frame), 0xFF);
  for (Index = 0; Index < mChildCount; Index++) {
    if (EFI_ERROR (gBS->HandleProtocol (mChildren[Index], &gEfiSimpleNetworkProtocolGuid, (VOID **)&Snp))) {
      continue;
    }

    SNPST ("initial", EFI_SUCCESS);
    SNPST ("init-start", Snp->Start (Snp));
    SNPST ("init-initialize", Snp->Initialize (Snp, 0, 0));
    SNPST ("init-getstatus", Snp->GetStatus (Snp, &Interrupt, NULL));
    SNPST ("init-getstatus-null", Snp->GetStatus (Snp, NULL, NULL));
    SNPST ("init-transmit-tiny", Snp->Transmit (Snp, 0, 4, Frame, NULL, NULL, NULL));
    SNPST ("init-transmit-null", Snp->Transmit (Snp, 0, 60, NULL, NULL, NULL, NULL));
    SNPST ("init-stop", Snp->Stop (Snp));
    SNPST ("shutdown", Snp->Shutdown (Snp));
    SNPST ("shutdown-again", Snp->Shutdown (Snp));
    SNPST ("started-initialize-bad", Snp->Initialize (Snp, 0, 0));
    SNPST ("shutdown-2", Snp->Shutdown (Snp));
    Size = sizeof (Frame);
    SNPST ("started-transmit", Snp->Transmit (Snp, 0, 60, Frame, NULL, NULL, NULL));
    SNPST ("started-receive", Snp->Receive (Snp, NULL, &Size, Frame, NULL, NULL, NULL));
    SNPST ("started-getstatus", Snp->GetStatus (Snp, &Interrupt, NULL));
    SNPST ("started-reset", Snp->Reset (Snp, FALSE));
    SNPST ("start-again", Snp->Start (Snp));
    SNPST ("stop", Snp->Stop (Snp));
    Size = sizeof (Frame);
    SNPST ("stopped-initialize", Snp->Initialize (Snp, 0, 0));
    SNPST ("stopped-transmit", Snp->Transmit (Snp, 0, 60, Frame, NULL, NULL, NULL));
    SNPST ("stopped-receive", Snp->Receive (Snp, NULL, &Size, Frame, NULL, NULL, NULL));
    SNPST ("stopped-getstatus", Snp->GetStatus (Snp, &Interrupt, NULL));
    SNPST ("stopped-filters", Snp->ReceiveFilters (Snp, 0, 0, FALSE, 0, NULL));
    SNPST ("stopped-station", Snp->StationAddress (Snp, TRUE, NULL));
    SNPST ("stopped-stats", Snp->Statistics (Snp, TRUE, NULL, NULL));
    SNPST ("stopped-shutdown", Snp->Shutdown (Snp));
    SNPST ("stopped-reset", Snp->Reset (Snp, FALSE));
    SNPST ("stopped-stop", Snp->Stop (Snp));
    if (KeepStopped) {
      continue;
    }

    for (Cycle = 0; Cycle < 3; Cycle++) {
      SNPST ("cycle-start", Snp->Start (Snp));
      SNPST ("cycle-initialize", Snp->Initialize (Snp, 0, 0));
      SNPST ("cycle-shutdown", Snp->Shutdown (Snp));
      SNPST ("cycle-stop", Snp->Stop (Snp));
    }

    SNPST ("restore-start", Snp->Start (Snp));
    SNPST ("restore-initialize", Snp->Initialize (Snp, 0, 0));
  }

#undef SNPST
}

/**
  One SNP call pattern on every child, to see which one damages the data
  path (nictest snpdamage <mode>): init2 = Initialize on an Initialized
  child; cycle = Shutdown + Initialize; stopstart = Shutdown, Stop, Start,
  Initialize; reset = Reset. The test pings afterwards.
**/
STATIC
VOID
TestSnpDamage (
  IN CHAR16  *Mode
  )
{
  EFI_STATUS                   Status;
  EFI_SIMPLE_NETWORK_PROTOCOL  *Snp;
  UINTN                        Index;

  for (Index = 0; Index < mChildCount; Index++) {
    if (EFI_ERROR (gBS->HandleProtocol (mChildren[Index], &gEfiSimpleNetworkProtocolGuid, (VOID **)&Snp))) {
      continue;
    }

    if (StrCmp (Mode, L"init2") == 0) {
      Status = Snp->Initialize (Snp, 0, 0);
      Print (L"NICTEST snpdamage %u init2 status=%r\n", Index, Status);
    } else if (StrCmp (Mode, L"cycle") == 0) {
      Status = Snp->Shutdown (Snp);
      Print (L"NICTEST snpdamage %u shutdown status=%r\n", Index, Status);
      Status = Snp->Initialize (Snp, 0, 0);
      Print (L"NICTEST snpdamage %u initialize status=%r filter=%x mask=%x\n", Index, Status, Snp->Mode->ReceiveFilterSetting, Snp->Mode->ReceiveFilterMask);
    } else if (StrCmp (Mode, L"cyclefilter") == 0) {
      Status = Snp->ReceiveFilters (Snp, Snp->Mode->ReceiveFilterMask & (EFI_SIMPLE_NETWORK_RECEIVE_UNICAST | EFI_SIMPLE_NETWORK_RECEIVE_BROADCAST), 0, FALSE, 0, NULL);
      Print (L"NICTEST snpdamage %u filters status=%r filter=%x\n", Index, Status, Snp->Mode->ReceiveFilterSetting);
    } else if (StrCmp (Mode, L"stopstart") == 0) {
      Status = Snp->Shutdown (Snp);
      Print (L"NICTEST snpdamage %u shutdown status=%r\n", Index, Status);
      Status = Snp->Stop (Snp);
      Print (L"NICTEST snpdamage %u stop status=%r\n", Index, Status);
      Status = Snp->Start (Snp);
      Print (L"NICTEST snpdamage %u start status=%r\n", Index, Status);
      Status = Snp->Initialize (Snp, 0, 0);
      Print (L"NICTEST snpdamage %u initialize status=%r\n", Index, Status);
    } else if (StrCmp (Mode, L"reset") == 0) {
      Status = Snp->Reset (Snp, FALSE);
      Print (L"NICTEST snpdamage %u reset status=%r\n", Index, Status);
    }
  }
}

/**
  nictest txfill: on child 0 transmit raw broadcast frames without
  recycling (GetStatus) until Transmit refuses, then recycle and send again.
  The Tx ring must refuse cleanly and recover.
**/
STATIC
VOID
TestTxFill (
  VOID
  )
{
  EFI_STATUS                   Status;
  EFI_SIMPLE_NETWORK_PROTOCOL  *Snp;
  UINT8                        Frame[60];
  UINTN                        Sent;
  UINTN                        Tries;
  UINT32                       Interrupt;
  VOID                         *TxBuf;
  UINTN                        Recycled;

  if (EFI_ERROR (gBS->HandleProtocol (mChildren[0], &gEfiSimpleNetworkProtocolGuid, (VOID **)&Snp))) {
    return;
  }

  SetMem (Frame, sizeof (Frame), 0xFF);
  CopyMem (Frame + 6, &Snp->Mode->CurrentAddress, 6);
  Frame[12] = 0x88;
  Frame[13] = 0xB5;
  Sent      = 0;
  Status    = EFI_SUCCESS;
  while (Sent < 100000) {
    Status = Snp->Transmit (Snp, 0, sizeof (Frame), Frame, NULL, NULL, NULL);
    if (EFI_ERROR (Status)) {
      break;
    }

    Sent++;
  }

  Print (L"NICTEST txfill sent=%u refused status=%r\n", Sent, Status);
  Recycled = 0;
  for (Tries = 0; Tries < 2000; Tries++) {
    TxBuf = NULL;
    Status = Snp->GetStatus (Snp, &Interrupt, &TxBuf);
    if (!EFI_ERROR (Status) && (TxBuf != NULL)) {
      Recycled++;
    }

    gBS->Stall (1000);
  }

  Print (L"NICTEST txfill recycled=%u\n", Recycled);
  Status = Snp->Transmit (Snp, 0, sizeof (Frame), Frame, NULL, NULL, NULL);
  Print (L"NICTEST txfill again status=%r\n", Status);
}

/**
  nictest samemac: child 1 gets the MAC of child 0 (StationAddress), then
  everything is restored (StationAddress reset).
**/
STATIC
VOID
TestSameMac (
  VOID
  )
{
  EFI_STATUS                   Status;
  EFI_SIMPLE_NETWORK_PROTOCOL  *Snp0;
  EFI_SIMPLE_NETWORK_PROTOCOL  *Snp1;

  if ((mChildCount < 2) ||
      EFI_ERROR (gBS->HandleProtocol (mChildren[0], &gEfiSimpleNetworkProtocolGuid, (VOID **)&Snp0)) ||
      EFI_ERROR (gBS->HandleProtocol (mChildren[1], &gEfiSimpleNetworkProtocolGuid, (VOID **)&Snp1)))
  {
    return;
  }

  Status = Snp1->StationAddress (Snp1, FALSE, &Snp0->Mode->CurrentAddress);
  Print (L"NICTEST samemac set status=%r same=%u\n", Status, CompareMem (&Snp1->Mode->CurrentAddress, &Snp0->Mode->CurrentAddress, 6) == 0);
  Status = Snp1->StationAddress (Snp1, TRUE, NULL);
  Print (L"NICTEST samemac reset status=%r restored=%u\n", Status, CompareMem (&Snp1->Mode->CurrentAddress, &Snp1->Mode->PermanentAddress, 6) == 0);
}

EFI_STATUS
EFIAPI
NicTestMain (
  IN EFI_HANDLE        ImageHandle,
  IN EFI_SYSTEM_TABLE  *SystemTable
  )
{
  EFI_STATUS                     Status;
  EFI_SHELL_PARAMETERS_PROTOCOL  *Params;
  CHAR16                         *Cmd;

  Status = gBS->HandleProtocol (ImageHandle, &gEfiShellParametersProtocolGuid, (VOID **)&Params);
  if (EFI_ERROR (Status) || (Params->Argc < 2)) {
    Print (L"Usage: nictest <cn2|health|aip|fmp|nii|snp|snpf|ver|cdb|ebs|eatmem alloc|eatmem free> [driver name part]\n");
    return EFI_INVALID_PARAMETER;
  }

  Cmd = Params->Argv[1];
  if (StrCmp (Cmd, L"ebs") == 0) {
    TestEbs ();
    return EFI_DEVICE_ERROR;
  }

  if (StrCmp (Cmd, L"eatmem") == 0) {
    if ((Params->Argc > 2) && (StrCmp (Params->Argv[2], L"alloc") == 0)) {
      EatMemAlloc (Params->Argc > 3 ? StrDecimalToUintn (Params->Argv[3]) : EAT_DEFAULT_LEAVE);
    } else if ((Params->Argc > 2) && (StrCmp (Params->Argv[2], L"free") == 0)) {
      EatMemFree ();
    } else {
      Print (L"Usage: nictest eatmem <alloc [pages to leave]|free>\n");
      return EFI_INVALID_PARAMETER;
    }

    Print (L"NICTEST done\n");
    return EFI_SUCCESS;
  }

  Status = FindDriver ((Params->Argc > 2) && (StrCmp (Cmd, L"vlan") != 0) && (StrCmp (Cmd, L"connectrdp") != 0) && (StrCmp (Cmd, L"snpstate") != 0) && (StrCmp (Cmd, L"snpdamage") != 0) ? Params->Argv[2] : DEFAULT_DRIVER_NAME);
  Print (L"NICTEST find status=%r driver=%p children=%u\n", Status, mDriver, mChildCount);
  if (EFI_ERROR (Status) && !((StrCmp (Cmd, L"connectrdp") == 0) && (mDriver != NULL))) {
    return Status;
  }

  if (StrCmp (Cmd, L"cn2") == 0) {
    TestCn2 ();
  } else if (StrCmp (Cmd, L"health") == 0) {
    TestHealth ();
  } else if (StrCmp (Cmd, L"aip") == 0) {
    TestAip ();
  } else if (StrCmp (Cmd, L"fmp") == 0) {
    TestFmp ();
  } else if (StrCmp (Cmd, L"nii") == 0) {
    TestNii ();
  } else if (StrCmp (Cmd, L"snp") == 0) {
    TestSnp ();
  } else if (StrCmp (Cmd, L"snpf") == 0) {
    TestSnpFilters ();
  } else if (StrCmp (Cmd, L"ver") == 0) {
    TestVer ();
  } else if (StrCmp (Cmd, L"cdb") == 0) {
    TestCdb ();
  } else if (StrCmp (Cmd, L"hiirc") == 0) {
    TestHiiRc ();
  } else if (StrCmp (Cmd, L"vlan") == 0) {
    TestVlan (Params);
  } else if (StrCmp (Cmd, L"connectrdp") == 0) {
    TestConnectRdp (Params);
    Status = EFI_SUCCESS;
  } else if (StrCmp (Cmd, L"hold") == 0) {
    TestHold ();
  } else if (StrCmp (Cmd, L"txfill") == 0) {
    TestTxFill ();
  } else if (StrCmp (Cmd, L"samemac") == 0) {
    TestSameMac ();
  } else if (StrCmp (Cmd, L"snpdamage") == 0) {
    TestSnpDamage (Params->Argc > 2 ? Params->Argv[2] : L"");
  } else if (StrCmp (Cmd, L"snpstate") == 0) {
    TestSnpState ((BOOLEAN)(Params->Argc > 2 && StrCmp (Params->Argv[2], L"stop") == 0));
  } else {
    Print (L"NICTEST unknown command %s\n", Cmd);
    Status = EFI_INVALID_PARAMETER;
  }

  FreePool (mChildren);
  Print (L"NICTEST done\n");
  return Status;
}
