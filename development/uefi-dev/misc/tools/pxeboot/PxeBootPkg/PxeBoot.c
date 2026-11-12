/** @file
  PXE / HTTP boot test app.

  From the shell: pxeboot <MAC> [http], e.g. pxeboot 0A0000080318. Boots the
  PXEv4 (or HTTPv4) device of that port the same way the boot manager does.
  Started as the NBP (no shell parameters): prints a marker and returns.
**/

#include <Uefi.h>
#include <Library/BaseLib.h>
#include <Library/DevicePathLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiLib.h>
#include <Protocol/LoadFile.h>
#include <Protocol/ShellParameters.h>

/**
  Checks if a device path is MAC(<Mac>)/IPv4(...)[/Uri(...)] at its end.

  @param[in]  DevicePath  Device path to check.
  @param[in]  Mac         MAC address, first byte most significant.
  @param[in]  Http        TRUE: HTTPv4 path (with Uri node). FALSE: PXEv4 path.

  @retval  TRUE   Boot device path of this MAC.
  @retval  FALSE  Other device path.
**/
STATIC
BOOLEAN
IsBootIp4Path (
  IN EFI_DEVICE_PATH_PROTOCOL  *DevicePath,
  IN UINT64                    Mac,
  IN BOOLEAN                   Http
  )
{
  EFI_DEVICE_PATH_PROTOCOL  *Node;
  EFI_DEVICE_PATH_PROTOCOL  *Next;
  MAC_ADDR_DEVICE_PATH      *MacNode;
  UINT64                    NodeMac;
  UINTN                     Index;

  for (Node = DevicePath; !IsDevicePathEnd (Node); Node = NextDevicePathNode (Node)) {
    if ((DevicePathType (Node) == MESSAGING_DEVICE_PATH) && (DevicePathSubType (Node) == MSG_MAC_ADDR_DP)) {
      break;
    }
  }

  if (IsDevicePathEnd (Node)) {
    return FALSE;
  }

  Next = NextDevicePathNode (Node);
  if (DevicePathSubType (Next) != MSG_IPv4_DP) {
    return FALSE;
  }

  Next = NextDevicePathNode (Next);
  if (Http) {
    if (IsDevicePathEnd (Next) || (DevicePathSubType (Next) != MSG_URI_DP)) {
      return FALSE;
    }

    Next = NextDevicePathNode (Next);
  }

  if (!IsDevicePathEnd (Next)) {
    return FALSE;
  }

  MacNode = (MAC_ADDR_DEVICE_PATH *)Node;
  NodeMac = 0;
  for (Index = 0; Index < 6; Index++) {
    NodeMac = LShiftU64 (NodeMac, 8) | MacNode->MacAddress.Addr[Index];
  }

  return NodeMac == Mac;
}

/**
  Finds the PXEv4 or HTTPv4 boot device path of a port.

  @param[in]  Mac   MAC address of the port.
  @param[in]  Http  TRUE: HTTPv4. FALSE: PXEv4.

  @return  Copy of the device path (caller frees), or NULL if not found.
**/
STATIC
EFI_DEVICE_PATH_PROTOCOL *
FindBootIp4Path (
  IN UINT64   Mac,
  IN BOOLEAN  Http
  )
{
  EFI_DEVICE_PATH_PROTOCOL  *DevicePath;
  EFI_DEVICE_PATH_PROTOCOL  *Found;
  EFI_HANDLE                *Handles;
  UINTN                     Count;
  UINTN                     Index;
  EFI_STATUS                Status;

  Status = gBS->LocateHandleBuffer (ByProtocol, &gEfiLoadFileProtocolGuid, NULL, &Count, &Handles);
  if (EFI_ERROR (Status)) {
    return NULL;
  }

  Found = NULL;
  for (Index = 0; Index < Count; Index++) {
    DevicePath = DevicePathFromHandle (Handles[Index]);
    if ((DevicePath != NULL) && IsBootIp4Path (DevicePath, Mac, Http)) {
      // HTTP boot reinstalls (frees) the handle device path during LoadFile.
      Found = DuplicateDevicePath (DevicePath);
      break;
    }
  }

  FreePool (Handles);
  return Found;
}

/**
  Entry point.

  @param[in]  ImageHandle  Image handle of this app.
  @param[in]  SystemTable  System table.

  @retval  EFI_SUCCESS  NBP ran and returned success.
  @retval  Others       Usage error, no boot device, or boot failed.
**/
EFI_STATUS
EFIAPI
PxeBootMain (
  IN EFI_HANDLE        ImageHandle,
  IN EFI_SYSTEM_TABLE  *SystemTable
  )
{
  EFI_SHELL_PARAMETERS_PROTOCOL  *Params;
  EFI_DEVICE_PATH_PROTOCOL       *DevicePath;
  EFI_HANDLE                     Nbp;
  BOOLEAN                        Http;
  EFI_STATUS                     Status;

  Status = gBS->HandleProtocol (ImageHandle, &gEfiShellParametersProtocolGuid, (VOID **)&Params);
  if (EFI_ERROR (Status)) {
    Print (L"PXEBOOT: NBP running\n");
    return EFI_SUCCESS;
  }

  Http = (Params->Argc == 3) && (StrCmp (Params->Argv[2], L"http") == 0);
  if ((Params->Argc != 2) && !Http) {
    Print (L"Usage: pxeboot <MAC, e.g. 0A0000080318> [http]\n");
    return EFI_INVALID_PARAMETER;
  }

  DevicePath = FindBootIp4Path (StrHexToUint64 (Params->Argv[1]), Http);
  if (DevicePath == NULL) {
    Print (L"PXEBOOT: no %s device for MAC %s\n", Http ? L"HTTPv4" : L"PXEv4", Params->Argv[1]);
    return EFI_NOT_FOUND;
  }

  Status = gBS->LoadImage (TRUE, ImageHandle, DevicePath, NULL, 0, &Nbp);
  FreePool (DevicePath);
  Print (L"PXEBOOT: LoadImage %r\n", Status);
  if (EFI_ERROR (Status)) {
    return Status;
  }

  Status = gBS->StartImage (Nbp, NULL, NULL);
  Print (L"PXEBOOT: StartImage %r\n", Status);
  return Status;
}
