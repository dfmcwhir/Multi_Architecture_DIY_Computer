// USB host for HID boot-protocol keyboards and mice on the S3 native USB port
// (GPIO19 = D-, GPIO20 = D+). Works with a hub and with combo receivers.
#pragma once
namespace usbhid {
void begin();   // starts the USB host tasks on core 0
}
