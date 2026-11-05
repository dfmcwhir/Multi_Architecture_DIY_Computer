//
// KEYBOARD, MOUSE AND SERIAL CONSOLE INTERFACE FOR THE 6502 SBC VIDEO CARD
//
// Based on: KEYBOARD, SERIAL AND DISPLAY INTERFACE  (c) GRANT SEARLE 2007-17
//   http://searle.hostei.com/grant/MonitorKeyboard/index.html
//   (Use a search engine to look for "Grant Searle" if the page has moved.)
//
// Reworked for a parallel 6502 bus interface on the PICO9918 video card.
// The display output of the original (8-bit, 4-bit and TWI display links and
// the ANSI interpreter) has been removed - the PICO9918 is the display now.
//
// Version 2: adds a PS/2 mouse on PC4 (clock) and PC0 (data).
//
// What it does
// ------------
//  * PS/2 keyboard -> ASCII key codes -> 6502 (read at $7F1E)
//  * Serial RX (115200 8N1)          -> same queue -> 6502
//  * PS/2 mouse                      -> same queue, as escaped packets
//                                       (only after the 6502 turns them on)
//  * 6502 writes to $7F1E            -> serial TX (plus escaped commands)
//
// 6502 register map (decoded by VDPGLUE.PLD)
// ------------------------------------------
//   $7F1E read : next byte from the queue (reading it acknowledges it)
//   $7F1E write: byte to send out of the serial port, or a command (below)
//   $7F1F read : status   D7 = KBAVAIL  (1 = byte waiting)          -> BIT sets N
//                         D6 = DBUSY    (1 = TX byte not taken yet)  -> BIT sets V
//   KBAVAIL also drives /KBIRQ (SBC IRQ5) through the GAL.
//
// Byte stream the 6502 reads from $7F1E
// -------------------------------------
//   $00-$FE        a key (PS/2 keyboard, or a byte from the serial port)
//   $FF $FF        a literal $FF byte that arrived on the serial port
//   $FF $01 b x y  mouse report (only sent while mouse reports are on):
//                    b = buttons: bit0 left, bit1 right, bit2 middle
//                    x = signed movement, right = positive (-128..+127)
//                    y = signed movement, DOWN  = positive (screen direction)
//                  Movement is accumulated between reports, and only one
//                  report is queued at a time, so the mouse can't flood the
//                  key queue: a slow reader just gets bigger x/y values.
//   The keyboard never produces $FF, so only $FF needs escaping.
//
// Commands the 6502 writes to $7F1E
// ---------------------------------
//   $FF $01   mouse reports on
//   $FF $00   mouse reports off (default after reset), pending motion cleared
//   $FF $FF   send a literal $FF out of the serial port
//   any other byte   sent out of the serial port
//
// ATmega328P pin use (DIP-28, 11.0592 MHz crystal)
// ------------------------------------------------
//   PB0-PB5  AVR bus D0-D5  (to '573 D inputs and '574 Q outputs)
//   PD6-PD7  AVR bus D6-D7
//   PB6-PB7  crystal
//   PC0      MOUSE DATA  (pull-up 4.7k-10k)   - was the optional /CTS input
//   PC1      KB clock    (pull-up)
//   PC2      KB data     (pull-up)
//   PC3      /RTS out
//   PC4      MOUSE CLOCK (pull-up 4.7k-10k)
//   PC5      KBAVAIL out -> GAL pin 14   (10k pull-down)
//   PC6      /RESET - keep it as reset (using it as I/O needs the RSTDISBL
//            fuse, which stops ISP programming)
//   PD0      RXD
//   PD1      TXD
//   PD2      INT0 <- /KBRD (GAL pin 17)  - byte acknowledge
//   PD3      <- DBUSY (GAL pin 22)       - 6502 has written a TX byte
//   PD4      /DOE  -> '574 /OE and GAL pin 23 (10k pull-up)
//   PD5      LE    -> '573 LE (10k pull-down)
//
// Handshakes
// ----------
//  Queue path (AVR -> 6502), through a 74HCT573:
//    1. With KBAVAIL low, the AVR drives the byte onto its bus, pulses LE to
//       latch it in the '573, releases the bus and sets KBAVAIL.
//    2. The 6502 reads $7F1E; /KBRD (the '573's /OE) pulses low.
//    3. INT0 fires on the rising edge of /KBRD (end of the read) and clears
//       KBAVAIL. Only then is the '573 reloaded.
//
//  TX path (6502 -> AVR), through a 74HCT574:
//    1. The 6502 checks DBUSY = 0, then writes $7F1E. The GAL clocks the byte
//       into the '574 and sets its DBUSY register.
//    2. The AVR sees DBUSY, pulls /DOE low (the '574 drives the AVR bus),
//       reads the byte and holds /DOE low until the GAL clears DBUSY.
//    3. If the TX buffer is full the AVR doesn't take the byte, so DBUSY stays
//       set and the 6502 waits - nothing is lost.
//
// Build: avr-gcc -mmcu=atmega328p -Os  (Atmel Studio: ATmega328P, -Os)
// Fuses: external full-swing or low-power crystal, as in the original design.
//

#define F_CPU 11059200ul
#define USART_BAUD 115200ul
#define USART_UBBR_VALUE ((F_CPU/(USART_BAUD<<4))-1)

// 1 = US keyboard layout, 0 = UK layout (the original tables)
#define KB_LAYOUT_US 1

#define PS2BUFSIZE  32      // raw bytes per PS/2 device (power of 2)
#define HOSTBUFSIZE 128     // bytes waiting for the 6502 (power of 2)
#define TXBUFSIZE   256     // serial TX bytes (uint8_t indices wrap at 256)

#define ESC_BYTE    0xFF    // stream escape (see header)
#define ESC_MOUSE   0x01

#include <avr/interrupt.h>
#include <avr/pgmspace.h>
#include <avr/io.h>
#include <util/delay.h>
#include <stdint.h>

// ---------------------------------------------------------------- pins
#define KBAVAIL_BIT  PC5
#define RTS_BIT      PC3
#define KB_CLK_BIT   PC1
#define KB_DATA_BIT  PC2
#define MS_CLK_BIT   PC4
#define MS_DATA_BIT  PC0
#define DBUSY_BIT    PD3
#define DOE_BIT      PD4
#define LE_BIT       PD5

#define BUS_B_MASK   0x3F   // PB0-PB5 = D0-D5
#define BUS_D_MASK   0xC0   // PD6-PD7 = D6-D7

// ---------------------------------------------------------------- PS/2 devices
typedef struct
{
	uint8_t clkMask, dataMask;          // bit masks on port C
	uint8_t buf[PS2BUFSIZE];            // received bytes
	volatile uint8_t in, out;
	volatile uint8_t bitCount;          // position in the current frame
	volatile uint8_t shift;             // receive / transmit shift register
	volatile uint8_t writeActive;       // host -> device frame in progress
	volatile uint8_t writeParity;
	volatile uint16_t lastTick;         // tick of the last clock edge
	// command queue (bytes the device must each acknowledge with 0xFA)
	uint8_t cmd[3];
	uint8_t cmdLen, cmdIdx;
	uint8_t awaitAck;
	uint16_t ackTick;
} ps2dev_t;

static ps2dev_t kb = { .clkMask = 1 << KB_CLK_BIT, .dataMask = 1 << KB_DATA_BIT };
static ps2dev_t ms = { .clkMask = 1 << MS_CLK_BIT, .dataMask = 1 << MS_DATA_BIT };

static volatile uint16_t tick;          // ~2 ms, from Timer2
static uint8_t lastPinC;

// keyboard translation state
unsigned char kbShift;
unsigned char kbCrtl;
unsigned char kbAlt;
unsigned char kbCaps;
unsigned char kbNumLock;
unsigned char kbScrollLock;
unsigned char prevKbCode;

// ---------------------------------------------------------------- queues
// Bytes for the 6502. Filled by the USART RX ISR and the main loop,
// emptied by the main loop.
unsigned char hostBuf[HOSTBUFSIZE];
volatile uint8_t hostIn;
volatile uint8_t hostOut;

// Serial TX. Filled by the main loop, emptied by the UDRE ISR.
unsigned char txBuf[TXBUFSIZE];
volatile uint8_t txIn;
volatile uint8_t txOut;

// mouse report state
static uint8_t mouseOn;                 // 6502 has turned reports on
static uint8_t msButtons, msLastButtons;
static int16_t msDX, msDY;              // accumulated, screen direction
static uint8_t msDirty;
static uint8_t msPending;               // a report is still in the host queue
static uint8_t msEndIdx;                // host queue index of its last byte

// ---------------------------------------------------------------- key maps
// Keycode values up to 131 (max returned from a 102 key keyboard).
// 128+ = function keys: F1-F12 = 129-140, shifted F1-F12 = 141-152.
// Esc gives 3 (Ctrl-C) as in the original.

#if KB_LAYOUT_US
const unsigned char kbNormal[132] PROGMEM = {
	0 , 137 , 0 , 133 , 131 , 129 , 130 , 140 , 0 , 138 , 136 , 134 , 132 , 9 , 96 , 0 ,
	0 , 0 , 0 , 0 , 0 , 113 , 49 , 0 , 0 , 0 , 122 , 115 , 97 , 119 , 50 , 0 ,
	0 , 99 , 120 , 100 , 101 , 52 , 51 , 0 , 0 , 32 , 118 , 102 , 116 , 114 , 53 , 0 ,
	0 , 110 , 98 , 104 , 103 , 121 , 54 , 0 , 0 , 0 , 109 , 106 , 117 , 55 , 56 , 0 ,
	0 , 44 , 107 , 105 , 111 , 48 , 57 , 0 , 0 , 46 , 47 , 108 , 59 , 112 , 45 , 0 ,
	0 , 0 , 39 , 0 , 91 , 61 , 0 , 0 , 0 , 0 , 13 , 93 , 0 , 92 , 0 , 0 ,
	0 , 92 , 0 , 0 , 0 , 0 , 8 , 0 , 0 , 49 , 0 , 52 , 55 , 0 , 0 , 0 ,
	48 , 46 , 50 , 53 , 54 , 56 , 3 , 0 , 139 , 43 , 51 , 45 , 42 , 57 , 0 , 0 ,
	0 , 0 , 0 , 135};

const unsigned char kbShifted[132] PROGMEM = {
	0 , 149 , 0 , 145 , 143 , 141 , 142 , 152 , 0 , 150 , 148 , 146 , 144 , 9 , 126 , 0 ,
	0 , 0 , 0 , 0 , 0 , 81 , 33 , 0 , 0 , 0 , 90 , 83 , 65 , 87 , 64 , 0 ,
	0 , 67 , 88 , 68 , 69 , 36 , 35 , 0 , 0 , 32 , 86 , 70 , 84 , 82 , 37 , 0 ,
	0 , 78 , 66 , 72 , 71 , 89 , 94 , 0 , 0 , 0 , 77 , 74 , 85 , 38 , 42 , 0 ,
	0 , 60 , 75 , 73 , 79 , 41 , 40 , 0 , 0 , 62 , 63 , 76 , 58 , 80 , 95 , 0 ,
	0 , 0 , 34 , 0 , 123 , 43 , 0 , 0 , 0 , 0 , 13 , 125 , 0 , 124 , 0 , 0 ,
	0 , 124 , 0 , 0 , 0 , 0 , 8 , 0 , 0 , 49 , 0 , 52 , 55 , 0 , 0 , 0 ,
	48 , 46 , 50 , 53 , 54 , 56 , 3 , 0 , 151 , 43 , 51 , 45 , 42 , 57 , 0 , 0 ,
	0 , 0 , 0 , 147};
#else
// UK layout (original tables; shifted Backspace/keypad row and shifted F7 fixed)
const unsigned char kbNormal[132] PROGMEM = {
	0 , 137 , 0 , 133 , 131 , 129 , 130 , 140 , 0 , 138 , 136 , 134 , 132 , 07 , 06 , 0 ,
	0 , 0 , 0 , 0 , 0 , 113 , 49 , 0 , 0 , 0 , 122 , 115 , 97 , 119 , 50 , 0 ,
	0 , 99 , 120 , 100 , 101 , 52 , 51 , 59 , 0 , 32 , 118 , 102 , 116 , 114 , 53 , 0 ,
	0 , 110 , 98 , 104 , 103 , 121 , 54 , 7 , 8 , 44 , 109 , 106 , 117 , 55 , 56 , 0 ,
	0 , 44 , 107 , 105 , 111 , 48 , 57 , 0 , 0 , 46 , 47 , 108 , 59 , 112 , 45 , 0 ,
	0 , 0 , 39 , 0 , 91 , 61 , 0 , 0 , 0 , 0 , 13 , 93 , 0 , 35 , 0 , 0 ,
	0 , 92 , 0 , 0 , 0 , 0 , 8 , 0 , 0 , 49 , 0 , 52 , 55 , 0 , 0 , 0 ,
	48 , 46 , 50 , 53 , 54 , 56 , 03 , 0 , 139 , 43 , 51 , 45 , 42 , 57 , 0 , 0 ,
	0 , 0 , 0 , 135};

const unsigned char kbShifted[132] PROGMEM = {
	0 , 149 , 0 , 145 , 143 , 141 , 142 , 152 , 0 , 150 , 148 , 146 , 144 , 0 , 172 , 0 ,
	0 , 0 , 0 , 0 , 0 , 81 , 33 , 0 , 0 , 0 , 90 , 83 , 65 , 87 , 34 , 0 ,
	0 , 67 , 88 , 68 , 69 , 36 , 163 , 58 , 0 , 32 , 86 , 70 , 84 , 82 , 37 , 0 ,
	0 , 78 , 66 , 72 , 71 , 89 , 94 , 0 , 0 , 76 , 77 , 74 , 85 , 38 , 42 , 0 ,
	0 , 60 , 75 , 73 , 79 , 41 , 40 , 0 , 0 , 62 , 63 , 76 , 58 , 80 , 95 , 0 ,
	0 , 0 , 64 , 0 , 123 , 43 , 0 , 0 , 0 , 0 , 13 , 125 , 0 , 126 , 0 , 0 ,
	0 , 124 , 0 , 0 , 0 , 0 , 8 , 0 , 0 , 49 , 0 , 52 , 55 , 0 , 0 , 0 ,
	48 , 46 , 50 , 53 , 54 , 56 , 03 , 0 , 151 , 43 , 51 , 45 , 42 , 57 , 0 , 0 ,
	0 , 0 , 0 , 147};
#endif


// ---------------------------------------------------------------- small helpers
static inline uint16_t getTick(void)
{
	uint16_t t;
	cli(); t = tick; sei();
	return t;
}

// Port C read-modify-write from main-loop code must not be interrupted:
// the INT0 ISR clears KBAVAIL on the same port.
static inline void portcSet(volatile uint8_t *reg, uint8_t mask, uint8_t on)
{
	uint8_t s = SREG;
	cli();
	if (on) *reg |= mask; else *reg &= ~mask;
	SREG = s;
}

// ---------------------------------------------------------------- AVR bus
static inline void busDrive(uint8_t v)
{
	PORTB = (PORTB & ~BUS_B_MASK) | (v & BUS_B_MASK);
	PORTD = (PORTD & ~BUS_D_MASK) | (v & BUS_D_MASK);
	DDRB |= BUS_B_MASK;
	DDRD |= BUS_D_MASK;
}

static inline void busRelease(void)
{
	DDRB &= ~BUS_B_MASK;
	DDRD &= ~BUS_D_MASK;
	PORTB &= ~BUS_B_MASK;   // no pull-ups
	PORTD &= ~BUS_D_MASK;
}

static inline uint8_t busRead(void)
{
	return (PINB & BUS_B_MASK) | (PIND & BUS_D_MASK);
}

// ---------------------------------------------------------------- host queue
static uint8_t hostCount(void)
{
	return (uint8_t)(hostIn - hostOut) & (HOSTBUFSIZE - 1);
}

static uint8_t hostFree(void)
{
	return (HOSTBUFSIZE - 1) - hostCount();
}

// /RTS: low = OK for the far end to send, high = stop (queue nearly full)
static void setRTS(void)
{
	uint8_t used = hostCount();
	if (used < 32)
	{
		PORTC &= ~(1 << RTS_BIT);
	}
	if (used > HOSTBUFSIZE - 32)
	{
		PORTC |= (1 << RTS_BIT);
	}
}

// Called with interrupts disabled. Caller checks for space.
static void hostPutLocked(uint8_t c)
{
	hostBuf[hostIn] = c;
	hostIn = (hostIn + 1) & (HOSTBUFSIZE - 1);
}

// A key from the main loop (keyboard). Keys are never $FF.
static void sendKeyToHost(uint8_t c)
{
	cli();
	if (hostFree() >= 1) hostPutLocked(c);
	sei();
	setRTS();
}

// If the 6502 has taken the previous byte, latch the next one into the '573
static void presentKeyToHost(void)
{
	if (PORTC & (1 << KBAVAIL_BIT)) return;     // previous byte not read yet
	if (hostIn == hostOut) return;              // nothing to send

	uint8_t idx = hostOut;
	uint8_t c = hostBuf[idx];
	busDrive(c);
	PORTD |= (1 << LE_BIT);                     // '573 transparent
	__asm__ __volatile__ ("nop\n\tnop\n\tnop");
	PORTD &= ~(1 << LE_BIT);                    // latched
	busRelease();

	cli();
	hostOut = (hostOut + 1) & (HOSTBUFSIZE - 1);
	sei();
	if (msPending && idx == msEndIdx) msPending = 0;
	setRTS();

	PORTC |= (1 << KBAVAIL_BIT);                // tell the 6502 (and raise IRQ5)
}

// 6502 has read $7F1E: rising edge of /KBRD = end of the read cycle
ISR(INT0_vect)
{
	PORTC &= ~(1 << KBAVAIL_BIT);
}

// ---------------------------------------------------------------- serial TX
static uint8_t txFree(void)
{
	return (uint8_t)(txOut - txIn - 1);
}

static void txPut(uint8_t c)
{
	txBuf[txIn] = c;
	txIn++;
	cli();
	UCSR0B |= (1 << UDRIE0);
	sei();
}

ISR(USART_UDRE_vect)
{
	if (txIn == txOut)
	{
		UCSR0B &= ~(1 << UDRIE0);
		return;
	}
	UDR0 = txBuf[txOut];
	txOut++;
}

// ---------------------------------------------------------------- 6502 -> TX
// A byte the 6502 wrote to $7F1E: serial data, or an escaped command
static void hostByte(uint8_t c)
{
	static uint8_t esc = 0;
	if (esc)
	{
		esc = 0;
		if (c == ESC_BYTE)
		{
			txPut(ESC_BYTE);                // $FF $FF = literal $FF
		}
		else if (c == 0x01)
		{
			mouseOn = 1;                    // start fresh: no stale motion
			msDX = msDY = 0;
			msDirty = 0;
			msLastButtons = msButtons;
		}
		else if (c == 0x00)
		{
			mouseOn = 0;
			msDX = msDY = 0;
			msDirty = 0;
		}
		// other values: reserved, ignored
		return;
	}
	if (c == ESC_BYTE)
	{
		esc = 1;
		return;
	}
	txPut(c);
}

// Take a byte the 6502 wrote to $7F1E out of the '574.
static void serviceHostWrite(void)
{
	static uint8_t waitIdle = 0;

	uint8_t busy = PIND & (1 << DBUSY_BIT);

	if (waitIdle)
	{
		// A previous read timed out (CPU stopped?). Don't read the same byte
		// again until DBUSY has gone away.
		if (!busy) waitIdle = 0;
		return;
	}
	if (!busy) return;
	if (txFree() == 0) return;          // TX full: leave DBUSY set, 6502 waits

	PORTD &= ~(1 << DOE_BIT);           // '574 drives the AVR bus
	_delay_us(1);
	uint8_t c = busRead();

	// Hold /DOE low until the GAL clears DBUSY on a clock rising edge.
	uint16_t t = 0;
	while ((PIND & (1 << DBUSY_BIT)) && t < 5000)
	{
		_delay_us(1);
		t++;
	}
	PORTD |= (1 << DOE_BIT);

	if (t >= 5000) waitIdle = 1;
	hostByte(c);
}

// ---------------------------------------------------------------- serial RX
// Serial input is treated as keypresses for the 6502; $FF is escaped.
ISR(USART_RX_vect)
{
	unsigned char tempSts = UCSR0A & 0x1C;
	unsigned char inByte = UDR0;
	if (tempSts > 0)
	{
		inByte = '?';
	}
	if (inByte == ESC_BYTE)
	{
		if (hostFree() >= 2)
		{
			hostPutLocked(ESC_BYTE);
			hostPutLocked(ESC_BYTE);
		}
	}
	else if (hostFree() >= 1)
	{
		hostPutLocked(inByte);
	}
	setRTS();
}

void initUSART(void)
{
	UBRR0H = (unsigned char)(USART_UBBR_VALUE >> 8);
	UBRR0L = (unsigned char)USART_UBBR_VALUE;
	UCSR0C = (0 << USBS0) | (1 << UCSZ01) | (1 << UCSZ00);   // 8N1
	UCSR0B = (1 << RXCIE0) | (1 << RXEN0) | (1 << TXEN0);
}

// ---------------------------------------------------------------- PS/2 low level
// Lines are driven open-drain: PORTC bit stays 0, DDRC 1 = pull low,
// DDRC 0 = released (external pull-up).

// Start a host -> device byte. Main loop only; blocks ~1 ms.
static void ps2StartWrite(ps2dev_t *d, uint8_t val)
{
	portcSet(&PORTC, d->clkMask | d->dataMask, 0);
	portcSet(&DDRC, d->clkMask, 1);             // clock low (inhibit)
	_delay_us(150);
	portcSet(&DDRC, d->dataMask, 1);            // data low (start bit)
	_delay_us(20);
	cli();
	d->shift = val;
	d->writeParity = 1;
	d->bitCount = 0;
	d->writeActive = 1;
	d->lastTick = tick;
	DDRC &= ~d->clkMask;                        // release clock: device clocks
	sei();
}

// One clock edge of one device. Called from the pin-change ISR.
static void ps2Edge(ps2dev_t *d, uint8_t pinc)
{
	d->lastTick = tick;

	if (d->writeActive)
	{
		// Host -> device: change data on the rising (low-to-high) edges
		if ((pinc & d->clkMask) == 0) return;
		d->bitCount++;
		if (d->bitCount <= 8)
		{
			if (d->shift & 1)
			{
				DDRC &= ~d->dataMask;           // 1 = release
				d->writeParity ^= 1;
			}
			else
			{
				DDRC |= d->dataMask;            // 0 = pull low
			}
			d->shift >>= 1;
		}
		else if (d->bitCount == 9)
		{
			if (d->writeParity) DDRC &= ~d->dataMask; else DDRC |= d->dataMask;
		}
		else if (d->bitCount == 10)
		{
			DDRC &= ~d->dataMask;               // stop bit: release
		}
		else
		{
			d->writeActive = 0;                 // 11: device ack bit
			d->bitCount = 0;
			d->shift = 0;
		}
		return;
	}

	// Device -> host: sample data on the falling edges
	if (pinc & d->clkMask) return;
	d->bitCount++;
	if (d->bitCount == 1 || d->bitCount == 10)
	{
		// start and parity bits ignored
	}
	else if (d->bitCount == 11)
	{
		d->bitCount = 0;
	}
	else
	{
		d->shift >>= 1;
		if (pinc & d->dataMask) d->shift |= 0x80;
		if (d->bitCount == 9)
		{
			uint8_t next = (d->in + 1) & (PS2BUFSIZE - 1);
			if (next != d->out)
			{
				d->buf[d->in] = d->shift;
				d->in = next;
			}
			d->shift = 0;
		}
	}
}

// Keyboard clock (PC1) and mouse clock (PC4) both raise PCINT1
ISR(PCINT1_vect)
{
	uint8_t pinc = PINC;
	uint8_t changed = pinc ^ lastPinC;
	lastPinC = pinc;
	if (changed & kb.clkMask) ps2Edge(&kb, pinc);
	if (changed & ms.clkMask) ps2Edge(&ms, pinc);
}

// ~2 ms tick. Resets a device whose frame stalled for >20 ms.
static void ps2Timeout(ps2dev_t *d)
{
	if ((d->bitCount || d->writeActive) && (uint16_t)(tick - d->lastTick) > 10)
	{
		if (d->writeActive)
		{
			DDRC &= ~(d->clkMask | d->dataMask);    // release both lines
			d->writeActive = 0;
		}
		d->bitCount = 0;
		d->shift = 0;
	}
}

ISR(TIMER2_COMPA_vect)
{
	tick++;
	ps2Timeout(&kb);
	ps2Timeout(&ms);
}

// Next received byte, or -1 if none
static int16_t ps2Get(ps2dev_t *d)
{
	if (d->in == d->out) return -1;
	uint8_t c = d->buf[d->out];
	d->out = (d->out + 1) & (PS2BUFSIZE - 1);
	return c;
}

// Queue up to three command bytes for a device
static void ps2Command(ps2dev_t *d, uint8_t n, uint8_t a, uint8_t b, uint8_t c)
{
	d->cmd[0] = a; d->cmd[1] = b; d->cmd[2] = c;
	d->cmdLen = n;
	d->cmdIdx = 0;
	d->awaitAck = 0;
}

// Send the next queued command byte when the previous one was acknowledged
static void ps2ServiceCommands(ps2dev_t *d)
{
	if (d->writeActive) return;
	if (d->awaitAck)
	{
		if ((uint16_t)(getTick() - d->ackTick) > 50)    // ~100 ms, no ack
		{
			d->awaitAck = 0;
			d->cmdLen = 0;                              // give up
		}
		return;
	}
	if (d->cmdIdx < d->cmdLen)
	{
		ps2StartWrite(d, d->cmd[d->cmdIdx++]);
		d->awaitAck = 1;
		d->ackTick = getTick();
	}
}

// Returns 1 if the byte was a command acknowledge (consumed)
static uint8_t ps2TakeAck(ps2dev_t *d, uint8_t c)
{
	if (c == 0xFA && d->awaitAck)
	{
		d->awaitAck = 0;
		return 1;
	}
	if (c == 0xFE && d->awaitAck)                       // resend request
	{
		d->awaitAck = 0;
		if (d->cmdIdx) d->cmdIdx--;
		return 1;
	}
	return 0;
}

static void updateKeyboardLEDs(void)
{
	uint8_t ledVals = 0;
	if (kbScrollLock == 1) ledVals += 1;
	if (kbNumLock == 1)    ledVals += 2;
	if (kbCaps == 1)       ledVals += 4;
	ps2Command(&kb, 2, 0xED, ledVals, 0);
}

// Translate one scan code from the keyboard (0xFA acks are handled before
// this is called, by ps2TakeAck)
static void processATKeyboard(unsigned char kbCode)
{
	unsigned char keyValue = 0;
	if (kbCode > 0)
	{
		//Ignore E0 prefixes if part of the key up as they are not significant
		//prev code will remain as F0 to ensure the following is processed properly
		if (prevKbCode == 0xF0 && kbCode == 0xE0)
		{
			return;
		}
		if (prevKbCode == 0xF0)
		{
			prevKbCode = kbCode;
			if (kbCode == 0x12 || kbCode == 0x59)
			{
				kbShift = 0;
			}
			if (kbCode == 0x14)
			{
				kbCrtl = 0;
			}
			if (kbCode == 0x11)
			{
				kbAlt = 0;
			}
			return;
		}
		if (prevKbCode == 0xE0 || kbNumLock == 0)
		{
			prevKbCode = kbCode;
			// Cursor keys - no ascii equiv, so sending "Wordstar" equivalents - CTRL E,S,D,X
			if (kbCode == 0x75) { sendKeyToHost(5);  return; } // up
			if (kbCode == 0x72) { sendKeyToHost(24); return; } // down
			if (kbCode == 0x6B) { sendKeyToHost(16); return; } // left
			if (kbCode == 0x74) { sendKeyToHost(4);  return; } // right
			if (kbCode == 0x70) { sendKeyToHost(1);  return; } // ins
			if (kbCode == 0x71) { sendKeyToHost(1);  return; } // del
			if (kbCode == 0x6C) { sendKeyToHost(1);  return; } // home
			if (kbCode == 0x69) { sendKeyToHost(1);  return; } // end
			if (kbCode == 0x7D) { sendKeyToHost(1);  return; } // page up
			if (kbCode == 0x7A) { sendKeyToHost(1);  return; } // page down
		}

		if (kbCode == 0x12 || kbCode == 0x59)
		{
			kbShift = 1;
		}
		else if (kbCode == 0x14)
		{
			kbCrtl = 1;
		}
		else if (kbCode == 0x11)
		{
			kbAlt = 1;
		}
		else if (kbCode == 0x58)
		{
			kbCaps = (kbCaps == 1) ? 0 : 1;
			updateKeyboardLEDs();
		}
		else if (kbCode == 0x77)
		{
			kbNumLock = (kbNumLock == 1) ? 0 : 1;
			updateKeyboardLEDs();
		}
		else if (kbCode == 0x7E)
		{
			kbScrollLock = (kbScrollLock == 1) ? 0 : 1;
			updateKeyboardLEDs();
		}
		else if (kbCode < 132)
		{
			if (kbShift == 0)
			{
				keyValue = pgm_read_byte(&kbNormal[kbCode]);
			}
			else
			{
				keyValue = pgm_read_byte(&kbShifted[kbCode]);
			}

			if (keyValue > 0)
			{
				if ((keyValue >= 'a') && (keyValue <= 'z') && (kbCaps == 1))
				{
					keyValue = keyValue - 32;
				}
				else if ((keyValue >= 'A') && (keyValue <= 'Z') && (kbCaps == 1))
				{
					keyValue = keyValue + 32;
				}

				if (kbCrtl == 1)
				{
					keyValue = keyValue & 0x1F;
				}

				sendKeyToHost(keyValue);
			}
		}
		prevKbCode = kbCode;
	}
}


// ---------------------------------------------------------------- mouse
// States: reset sent -> wait for self-test (AA 00) -> enable sent -> streaming
enum { MS_START, MS_WAIT_BAT, MS_WAIT_ID, MS_WAIT_EN, MS_STREAM };
static uint8_t msState = MS_START;
static uint16_t msStateTick;
static uint8_t msPkt[3];
static uint8_t msPktIdx;
static uint16_t msPktTick;

static void msSetState(uint8_t s)
{
	msState = s;
	msStateTick = getTick();
}

static void processMouseByte(uint8_t c)
{
	switch (msState)
	{
	case MS_WAIT_BAT:
		if (c == 0xAA) msSetState(MS_WAIT_ID);          // self-test passed
		break;
	case MS_WAIT_ID:
		if (c == 0x00)                                  // device ID: mouse
		{
			ps2Command(&ms, 1, 0xF4, 0, 0);             // enable data reporting
			msSetState(MS_WAIT_EN);
		}
		else msSetState(MS_WAIT_BAT);
		break;
	case MS_STREAM:
	{
		msPktTick = getTick();
		if (msPktIdx == 0 && !(c & 0x08)) return;       // not a first byte: resync
		msPkt[msPktIdx++] = c;
		if (msPktIdx < 3) return;
		msPktIdx = 0;

		uint8_t b0 = msPkt[0];
		msButtons = b0 & 0x07;
		if (!mouseOn) break;                            // reports off: discard
		if (!(b0 & 0xC0))                               // ignore overflowed moves
		{
			int16_t x = msPkt[1] | ((b0 & 0x10) ? 0xFF00 : 0);
			int16_t y = msPkt[2] | ((b0 & 0x20) ? 0xFF00 : 0);
			msDX += x;
			msDY -= y;                                  // PS/2 up = +, screen down = +
			if (msDX > 4000) msDX = 4000; else if (msDX < -4000) msDX = -4000;
			if (msDY > 4000) msDY = 4000; else if (msDY < -4000) msDY = -4000;
		}
		if (msDX || msDY || msButtons != msLastButtons) msDirty = 1;
		break;
	}
	default:
		break;
	}
}

// A packet that stops part-way for >20 ms is dropped. A hot-plugged mouse
// sends AA 00 and then waits for the host, which looks like a stalled
// packet: re-enable reporting when that happens.
static void mouseStallCheck(void)
{
	if (msState != MS_STREAM || msPktIdx == 0) return;
	if ((uint16_t)(getTick() - msPktTick) <= 10) return;
	if (msPktIdx == 2 && msPkt[0] == 0xAA && msPkt[1] == 0x00)
	{
		ps2Command(&ms, 1, 0xF4, 0, 0);
		msSetState(MS_WAIT_EN);
	}
	msPktIdx = 0;
}

static void serviceMouse(void)
{
	int16_t c;
	mouseStallCheck();
	while ((c = ps2Get(&ms)) >= 0)
	{
		if (ps2TakeAck(&ms, c))
		{
			if (msState == MS_WAIT_EN && ms.cmdIdx >= ms.cmdLen)
			{
				msSetState(MS_STREAM);
				msPktIdx = 0;
			}
			continue;
		}
		processMouseByte(c);
	}

	// (re)initialise: at start-up, and every ~2 s until a mouse answers
	if (msState == MS_START ||
	    (msState != MS_STREAM && (uint16_t)(getTick() - msStateTick) > 1000))
	{
		ps2Command(&ms, 1, 0xFF, 0, 0);                 // reset
		msSetState(MS_WAIT_BAT);
	}
	ps2ServiceCommands(&ms);

	// One report in the host queue at a time; motion keeps accumulating
	if (mouseOn && msDirty && !msPending)
	{
		int8_t x = msDX > 127 ? 127 : (msDX < -128 ? -128 : msDX);
		int8_t y = msDY > 127 ? 127 : (msDY < -128 ? -128 : msDY);
		cli();
		if (hostFree() >= 5)
		{
			hostPutLocked(ESC_BYTE);
			hostPutLocked(ESC_MOUSE);
			hostPutLocked(msButtons);
			hostPutLocked((uint8_t)x);
			msEndIdx = hostIn;
			hostPutLocked((uint8_t)y);
			msPending = 1;
			msDX -= x;
			msDY -= y;
			msLastButtons = msButtons;
			msDirty = (msDX || msDY);
		}
		sei();
		setRTS();
	}
	if (!mouseOn) msLastButtons = msButtons;
}

// ---------------------------------------------------------------- keyboard
static void serviceKeyboard(void)
{
	int16_t c;
	while ((c = ps2Get(&kb)) >= 0)
	{
		if (ps2TakeAck(&kb, c)) continue;
		processATKeyboard(c);
	}
	ps2ServiceCommands(&kb);
}

// ---------------------------------------------------------------- main
int main(void)
{
	hostIn = hostOut = 0;
	txIn = txOut = 0;

	// AVR bus: inputs, no pull-ups (PB6/PB7 are the crystal)
	DDRB = 0x00;
	PORTB = 0x00;

	// Port C: /RTS and KBAVAIL outputs low; PS/2 lines released (inputs,
	// external pull-ups, PORTC bits 0 so DDRC=1 means "pull low")
	PORTC = 0x00;
	DDRC = (1 << RTS_BIT) | (1 << KBAVAIL_BIT);

	// Port D: /DOE high (set before enabling the output), LE low,
	// pull-up on the /KBRD input
	PORTD = (1 << DOE_BIT) | (1 << PD2);
	DDRD = (1 << PD1) | (1 << DOE_BIT) | (1 << LE_BIT);

	// Clear any DBUSY left set at power-up: hold /DOE low for a few clocks
	PORTD &= ~(1 << DOE_BIT);
	_delay_us(20);
	PORTD |= (1 << DOE_BIT);

	// PS/2 clocks: PC1 (keyboard) and PC4 (mouse) pin-change interrupts
	lastPinC = PINC;
	PCICR = 1 << PCIE1;
	PCMSK1 = (1 << PCINT9) | (1 << PCINT12);

	// INT0 (PD2, /KBRD) on rising edge = end of the 6502's read
	EICRA = (1 << ISC01) | (1 << ISC00);
	EIFR = 1 << INTF0;
	EIMSK = 1 << INT0;

	initUSART();

	// Timer2: ~2 ms tick (11.0592 MHz / 1024 / 22)
	TCCR2A = 1 << WGM21;                                // CTC
	TCCR2B = (1 << CS22) | (1 << CS21) | (1 << CS20);   // clk/1024
	OCR2A = 21;
	TIMSK2 = 1 << OCIE2A;

	sei();

	while (1)
	{
		serviceHostWrite();     // 6502 -> serial TX / commands
		serviceKeyboard();      // PS/2 keyboard -> queue
		serviceMouse();         // PS/2 mouse -> queue (when enabled)
		presentKeyToHost();     // queue -> 6502
	}

	return 0;
}
