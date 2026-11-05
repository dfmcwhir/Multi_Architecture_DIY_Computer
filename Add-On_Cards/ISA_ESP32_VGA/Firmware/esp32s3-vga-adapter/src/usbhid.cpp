// Minimal USB HID host: boot protocol keyboards and mice.
#include "usbhid.h"
#include "input.h"

#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "usb/usb_host.h"
#include "esp_log.h"

static const char *TAG = "usbhid";

namespace usbhid {

static const int MAX_DEVS = 4;
static const int MAX_IFS = 3;

struct HidIf {
  uint8_t num = 0, ep = 0, proto = 0;   // proto 1 = keyboard, 2 = mouse
  uint16_t mps = 8;
  usb_transfer_t *xfer = nullptr;
  volatile bool inflight = false;
  uint8_t prev[8] = {0};                // last keyboard report
  struct Dev *dev = nullptr;
};

struct Dev {
  bool used = false;
  volatile bool gone = false;
  uint8_t addr = 0;
  usb_device_handle_t h = nullptr;
  HidIf ifs[MAX_IFS];
  int nifs = 0;
};

static usb_host_client_handle_t s_client = nullptr;
static Dev s_devs[MAX_DEVS];
static uint8_t s_newAddr[8];
static int s_newCount = 0;   // only touched from the client task

// Key repeat for USB keyboards (USB keyboards do not repeat by themselves)
static uint8_t s_repKey = 0;
static TickType_t s_repAt = 0;

// HID usage -> key code (see input.h)
static uint8_t s_usage[0x68];

static void buildTable() {
  for (int i = 0; i < 26; i++) s_usage[0x04 + i] = 'a' + i;
  const char *digits = "1234567890";
  for (int i = 0; i < 10; i++) s_usage[0x1E + i] = digits[i];
  s_usage[0x28] = 0x0D; s_usage[0x29] = 0x1B; s_usage[0x2A] = 0x08; s_usage[0x2B] = 0x09;
  s_usage[0x2C] = ' ';  s_usage[0x2D] = '-';  s_usage[0x2E] = '=';  s_usage[0x2F] = '[';
  s_usage[0x30] = ']';  s_usage[0x31] = '\\'; s_usage[0x32] = '\\'; s_usage[0x33] = ';';
  s_usage[0x34] = '\''; s_usage[0x35] = '`';  s_usage[0x36] = ',';  s_usage[0x37] = '.';
  s_usage[0x38] = '/';  s_usage[0x39] = input::K_CAPS;
  for (int i = 0; i < 12; i++) s_usage[0x3A + i] = input::K_F1 + i;
  s_usage[0x46] = input::K_PRTSC; s_usage[0x47] = input::K_SCROLL; s_usage[0x48] = input::K_PAUSE;
  s_usage[0x49] = input::K_INS;   s_usage[0x4A] = input::K_HOME;   s_usage[0x4B] = input::K_PGUP;
  s_usage[0x4C] = 0x7F;           s_usage[0x4D] = input::K_END;    s_usage[0x4E] = input::K_PGDN;
  s_usage[0x4F] = input::K_RIGHT; s_usage[0x50] = input::K_LEFT;   s_usage[0x51] = input::K_DOWN;
  s_usage[0x52] = input::K_UP;    s_usage[0x53] = input::K_NUMLOCK;
  s_usage[0x54] = '/'; s_usage[0x55] = '*'; s_usage[0x56] = '-'; s_usage[0x57] = '+';
  s_usage[0x58] = 0x0D;
  const char *kp = "1234567890.";
  for (int i = 0; i < 11; i++) s_usage[0x59 + i] = kp[i];
  s_usage[0x64] = '\\'; s_usage[0x65] = input::K_MENU;
}

static const uint8_t MOD_CODES[8] = {
  input::K_LCTRL, input::K_LSHIFT, input::K_LALT, input::K_GUI,
  input::K_RCTRL, input::K_RSHIFT, input::K_RALT, input::K_GUI,
};

static bool contains(const uint8_t *keys, uint8_t k) {
  for (int i = 2; i < 8; i++) if (keys[i] == k) return true;
  return false;
}

static void keyboardReport(HidIf &f, const uint8_t *r, int len) {
  if (len < 8) return;
  if (r[2] == 0x01) return;                  // phantom state (rollover)
  uint8_t changed = r[0] ^ f.prev[0];
  for (int i = 0; i < 8; i++)
    if (changed & (1 << i)) input::keyEvent(MOD_CODES[i], r[0] & (1 << i));
  for (int i = 2; i < 8; i++) {              // released keys
    uint8_t u = f.prev[i];
    if (u > 3 && u < sizeof s_usage && s_usage[u] && !contains(r, u))
      input::keyEvent(s_usage[u], false);
  }
  for (int i = 2; i < 8; i++) {              // newly pressed keys
    uint8_t u = r[i];
    if (u > 3 && u < sizeof s_usage && s_usage[u] && !contains(f.prev, u)) {
      uint8_t code = s_usage[u];
      input::keyEvent(code, true);
      if (code < input::K_LSHIFT) {
        s_repKey = code;
        s_repAt = xTaskGetTickCount() + pdMS_TO_TICKS(500);
      }
    }
  }
  memcpy(f.prev, r, 8);
}

static void mouseReport(const uint8_t *r, int len) {
  if (len < 3) return;
  input::mouseEvent((int8_t)r[1], (int8_t)r[2], r[0] & 7);
}

static void intrCallback(usb_transfer_t *t) {
  HidIf &f = *(HidIf *)t->context;
  if (t->status == USB_TRANSFER_STATUS_COMPLETED) {
    if (f.proto == 1) keyboardReport(f, t->data_buffer, t->actual_num_bytes);
    else mouseReport(t->data_buffer, t->actual_num_bytes);
  }
  bool ok = t->status == USB_TRANSFER_STATUS_COMPLETED || t->status == USB_TRANSFER_STATUS_TIMED_OUT;
  if (ok && !f.dev->gone && usb_host_transfer_submit(t) == ESP_OK) return;
  f.inflight = false;
}

static void clientCallback(const usb_host_client_event_msg_t *msg, void *) {
  if (msg->event == USB_HOST_CLIENT_EVENT_NEW_DEV) {
    if (s_newCount < (int)sizeof s_newAddr) s_newAddr[s_newCount++] = msg->new_dev.address;
  } else if (msg->event == USB_HOST_CLIENT_EVENT_DEV_GONE) {
    for (auto &d : s_devs)
      if (d.used && d.h == msg->dev_gone.dev_hdl) d.gone = true;
  }
}

// Synchronous control transfer with no data stage (class requests).
static volatile bool s_ctrlDone;
static void ctrlCallback(usb_transfer_t *) { s_ctrlDone = true; }

static bool control(Dev &d, uint8_t reqType, uint8_t req, uint16_t value, uint16_t index,
                    const uint8_t *data = nullptr, uint16_t len = 0) {
  usb_transfer_t *t;
  if (usb_host_transfer_alloc(sizeof(usb_setup_packet_t) + 8, 0, &t) != ESP_OK) return false;
  usb_setup_packet_t *s = (usb_setup_packet_t *)t->data_buffer;
  s->bmRequestType = reqType;
  s->bRequest = req;
  s->wValue = value;
  s->wIndex = index;
  s->wLength = len;
  if (len) memcpy(t->data_buffer + sizeof(usb_setup_packet_t), data, len);
  t->num_bytes = sizeof(usb_setup_packet_t) + len;
  t->device_handle = d.h;
  t->bEndpointAddress = 0;
  t->callback = ctrlCallback;
  t->timeout_ms = 500;
  s_ctrlDone = false;
  bool ok = false;
  if (usb_host_transfer_submit_control(s_client, t) == ESP_OK) {
    for (int i = 0; i < 50 && !s_ctrlDone; i++) usb_host_client_handle_events(s_client, pdMS_TO_TICKS(10));
    ok = s_ctrlDone && t->status == USB_TRANSFER_STATUS_COMPLETED;
  }
  if (s_ctrlDone) usb_host_transfer_free(t);   // otherwise leak rather than free in flight
  return ok;
}

static void openDevice(uint8_t addr) {
  Dev *d = nullptr;
  for (auto &x : s_devs) if (!x.used) { d = &x; break; }
  if (!d) { ESP_LOGW(TAG, "too many devices"); return; }
  *d = Dev();
  if (usb_host_device_open(s_client, addr, &d->h) != ESP_OK) return;
  d->used = true;
  d->addr = addr;

  const usb_config_desc_t *cfg;
  if (usb_host_get_active_config_descriptor(d->h, &cfg) != ESP_OK) return;
  const uint8_t *p = (const uint8_t *)cfg;
  int total = cfg->wTotalLength, off = 0;
  HidIf *cur = nullptr;
  while (off + 2 <= total && p[off] >= 2) {
    uint8_t len = p[off], type = p[off + 1];
    if (type == USB_B_DESCRIPTOR_TYPE_INTERFACE && len >= 9) {
      cur = nullptr;
      // class 3 (HID), subclass 1 (boot), protocol 1 keyboard / 2 mouse, alt 0
      if (p[off + 5] == 3 && p[off + 6] == 1 && (p[off + 7] == 1 || p[off + 7] == 2) &&
          p[off + 3] == 0 && d->nifs < MAX_IFS) {
        cur = &d->ifs[d->nifs];
        cur->num = p[off + 2];
        cur->proto = p[off + 7];
        cur->ep = 0;
        cur->dev = d;
      }
    } else if (type == USB_B_DESCRIPTOR_TYPE_ENDPOINT && len >= 7 && cur && !cur->ep) {
      uint8_t ea = p[off + 2], attr = p[off + 3];
      if ((ea & 0x80) && (attr & 3) == 3) {   // interrupt IN
        cur->ep = ea;
        cur->mps = p[off + 4] | (p[off + 5] << 8);
        d->nifs++;
        cur = nullptr;
      }
    }
    off += len;
  }

  for (int i = 0; i < d->nifs; i++) {
    HidIf &f = d->ifs[i];
    if (usb_host_interface_claim(s_client, d->h, f.num, 0) != ESP_OK) { f.ep = 0; continue; }
    control(*d, 0x21, 0x0B, 0, f.num);         // SET_PROTOCOL boot
    if (f.proto == 1) control(*d, 0x21, 0x0A, 0, f.num);   // SET_IDLE 0
    uint16_t size = f.mps < 8 ? 8 : f.mps;
    if (usb_host_transfer_alloc(size, 0, &f.xfer) != ESP_OK) continue;
    f.xfer->num_bytes = size;
    f.xfer->device_handle = d->h;
    f.xfer->bEndpointAddress = f.ep;
    f.xfer->callback = intrCallback;
    f.xfer->context = &f;
    f.inflight = usb_host_transfer_submit(f.xfer) == ESP_OK;
    ESP_LOGI(TAG, "device %d: %s on interface %d", addr, f.proto == 1 ? "keyboard" : "mouse", f.num);
  }
  if (d->nifs == 0) ESP_LOGI(TAG, "device %d has no boot keyboard/mouse", addr);
}

static void closeDevice(Dev &d) {
  for (int i = 0; i < d.nifs; i++) if (d.ifs[i].inflight) return;   // wait for transfers
  for (int i = 0; i < d.nifs; i++) {
    HidIf &f = d.ifs[i];
    if (f.proto == 1) {            // release any keys this keyboard was holding
      uint8_t none[8] = {0};
      keyboardReport(f, none, 8);
    }
    if (f.ep) usb_host_interface_release(s_client, d.h, f.num);
    if (f.xfer) usb_host_transfer_free(f.xfer);
    f.xfer = nullptr;
  }
  usb_host_device_close(s_client, d.h);
  ESP_LOGI(TAG, "device %d removed", d.addr);
  d.used = false;
}

static void setLeds(uint8_t psLeds) {
  // HID LED bits: 0 num, 1 caps, 2 scroll
  uint8_t r = ((psLeds & input::LED_NUM) ? 1 : 0) | ((psLeds & input::LED_CAPS) ? 2 : 0) |
              ((psLeds & input::LED_SCROLL) ? 4 : 0);
  for (auto &d : s_devs) {
    if (!d.used || d.gone) continue;
    for (int i = 0; i < d.nifs; i++)
      if (d.ifs[i].proto == 1) control(d, 0x21, 0x09, 0x0200, d.ifs[i].num, &r, 1);  // SET_REPORT
  }
}

static void libTask(void *arg) {
  usb_host_config_t cfg = {};
  cfg.skip_phy_setup = false;
  cfg.intr_flags = ESP_INTR_FLAG_LEVEL1;
  esp_err_t err = usb_host_install(&cfg);
  xTaskNotifyGive((TaskHandle_t)arg);
  if (err != ESP_OK) { ESP_LOGE(TAG, "usb_host_install: %d", err); vTaskDelete(nullptr); }
  for (;;) {
    uint32_t flags;
    usb_host_lib_handle_events(portMAX_DELAY, &flags);
    if (flags & USB_HOST_LIB_EVENT_FLAGS_NO_CLIENTS) usb_host_device_free_all();
  }
}

static void clientTask(void *) {
  ulTaskNotifyTake(pdTRUE, portMAX_DELAY);   // wait for usb_host_install
  buildTable();
  usb_host_client_config_t cc = {};
  cc.is_synchronous = false;
  cc.max_num_event_msg = 8;
  cc.async.client_event_callback = clientCallback;
  cc.async.callback_arg = nullptr;
  if (usb_host_client_register(&cc, &s_client) != ESP_OK) {
    ESP_LOGE(TAG, "client register failed");
    vTaskDelete(nullptr);
  }
  uint32_t ledsSeen = input::ledsVersion;
  for (;;) {
    usb_host_client_handle_events(s_client, pdMS_TO_TICKS(10));
    while (s_newCount) {
      uint8_t a = s_newAddr[--s_newCount];
      openDevice(a);
      ledsSeen = input::ledsVersion - 1;     // send current LEDs to the new keyboard
    }
    for (auto &d : s_devs) if (d.used && d.gone) closeDevice(d);
    if (ledsSeen != input::ledsVersion) {
      ledsSeen = input::ledsVersion;
      setLeds(input::leds());
    }
    // typematic repeat
    if (s_repKey) {
      if (!input::isDown(s_repKey)) s_repKey = 0;
      else if ((int32_t)(xTaskGetTickCount() - s_repAt) >= 0) {
        input::keyRepeat(s_repKey);
        s_repAt = xTaskGetTickCount() + pdMS_TO_TICKS(33);
      }
    }
  }
}

void begin() {
  TaskHandle_t client;
  xTaskCreatePinnedToCore(clientTask, "usbcli", 4096, nullptr, 3, &client, 0);
  xTaskCreatePinnedToCore(libTask, "usblib", 4096, client, 4, nullptr, 0);
}

} // namespace usbhid
