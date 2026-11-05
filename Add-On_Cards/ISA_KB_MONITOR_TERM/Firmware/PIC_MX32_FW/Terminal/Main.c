/*****************************************************************************************************************************

Main.c

	Copyright (C) 2014 Geoff Graham (projects@geoffg.net)
	All rights reserved.

	This file and the program created from it are FREE FOR COMMERCIAL AND
	NON-COMMERCIAL USE as long as the following conditions are aheared to.

	Copyright remains Geoff Graham's, and as such any Copyright notices in the
	code are not to be removed.  If this code is used in a product, Geoff Graham
	should be given attribution as the author of the parts used.  This can be in
	the form of a textual message at program startup or in documentation (online
	or textual) provided with the program or product.

	Redistribution and use in source and binary forms, with or without modification,
	are permitted provided that the following conditions  are met:
	1. Redistributions of source code must retain the copyright notice, this list
	   of conditions and the following disclaimer.
	2. Redistributions in binary form must reproduce the above copyright notice, this
	   list of conditions and the following disclaimer in the documentation and/or
	   other materials provided with the distribution.
	3. All advertising materials mentioning features or use of this software must
	   display the following acknowledgement:
	   This product includes software developed by Geoff Graham (projects@geoffg.net)

	THIS SOFTWARE IS PROVIDED BY GEOFF GRAHAM ``AS IS'' AND  ANY EXPRESS OR IMPLIED
	WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
	MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT
	SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
	SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
	PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
	BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
	CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
	IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
	SUCH DAMAGE.

	The licence and distribution terms for any publically available version or
	derivative of this code cannot be changed.  i.e. this code cannot simply be copied
	and put under another distribution licence (including the GNU Public Licence).

*********************************************************************************************************************************
    
This source will compile correctly with Microchip MPLAB X IDE V5.25 and XC32 V1.33.  
Old versions of Microchip software can be downloaded from:
   https://www.microchip.com/development-tools/pic-and-dspic-downloads-archive

To compile an updated version of the firmware make the project "Terminal" the main project.  
Then recompile it.  The resultant hex file is called:
  Source\Terminal\Terminal\dist\default\production\Terminal.production.hex

Updates must be loaded with the standard Microchip bootloader.  This and instructions are in the PC App folder.


********************************************************************************************************************************/

#define _SUPPRESS_PLIB_WARNING

#include <plib.h>									// peripheral libraries
#include <string.h>
#include <ctype.h>
#include "Configuration Bits.h"                     // config pragmas
#include "Terminal.h"
#include "video.h"
#include "vt100.h"

//** USB INCLUDES ***********************************************************
#include "./USB/Microchip/Include/USB/usb.h"
#include "./USB/Microchip/Include/USB/usb_function_cdc.h"
#include "./USB/HardwareProfile.h"

#include "./USB/Microchip/Include/GenericTypeDefs.h"
#include "./USB/Microchip/Include/Compiler.h"
#include "./USB/usb_config.h"
#include "./USB/Microchip/Include/USB/usb_device.h"


// declare the serial I/O functions
void initSerial(void);
int getSerial(void);
void putSerial(int c);

// declare the USB I/O functions
void CheckUSB(void);

void initTimer(void);

void BlinkLED(void);


char *SerialRxBuf;
int RxBufferSize;
volatile int SerialRxBufHead = 0;
volatile unsigned int RxDropped = 0;                           // bytes lost (Rx ring full or UART error), read by the sprite STATUS command 1C 0D
volatile unsigned int RxPeak = 0;                              // most bytes ever waiting in the Rx ring
volatile int SerialRxBufTail = 0;

#define SERIAL_TX_BUF_SIZE 128
char SerialTxBuf[SERIAL_TX_BUF_SIZE];
int SerialTxBufHead = 0;
int SerialTxBufTail = 0;

// declare the USB buffers
// these buffers are used by the USB I/O hardware
#define USB_DEVICE_RX_BUFFER_SIZE	64
#define USB_DEVICE_TX_BUFFER_SIZE	64
char UsbDeviceRxBuf[USB_DEVICE_RX_BUFFER_SIZE];
char UsbDeviceTxBuf[USB_DEVICE_TX_BUFFER_SIZE];

// Because the USB copies data direct to the serial Tx buf and sends data direct from the serial Rx queue
// it does not need its own I/O buffers (except for the hardware device buffers declared above).
// The only pointer that we need is this one which keep track of where we are while reading the serial Rx buffer
int USBSerialRxBufTail = 0;

volatile int LEDTimer = 0;
int CursorOff = false;
volatile int CursorTimer = 0;
volatile int GeneralTimer;

#define MES_SIGNON  "\rASCII Video Terminal Ver " VERSION "\r\n"\
					"Copyright " YEAR " Geoff Graham\r\n\r\n"

int main(int argc, char* argv[]) {
    int ch;

	// initial setup of the I/O ports
    ANSELA = 0; ANSELB = 0;			                                // Default all pins to digital
    mJTAGPortEnable(0);                                             // turn off jtag

 	// setup the CPU
    SYSTEMConfigPerformance(CLOCKFREQ);    							// System config performance
	mOSCSetPBDIV(OSC_PB_DIV_1);									    // fix the peripheral bus to the main clock speed

    // clear all port I/O (they are not cleared by a software reset)
    LATA = LATB = 0;
    TRISA = TRISB = 0xffffffff;
    CNENA = CNENB = CNCONA = CNCONB = 0;
    CNPUA = CNPUB = CNPDA = CNPDB = 0;

    CNPUBSET = (1 << 4); CNPUBSET = (1 << 3); CNPUASET = (1 << 1);  // set pullups on the baudrate jumpers
    TRISBbits.TRISB5 = 0; LATBCLR = (1<<5);                         // turn on the power LED
    uSec(1000);                                                     // settling time

    INTEnableSystemMultiVectoredInt();                              // allow vectored interrupts
    initTimer();                                                    // initialise the millisecond timer
    initVideo();                                                    // initialise the video and associated interrupt
    initVT100();                                                    // initialise the vt100/vt52 decoding engine
    initFont(1);                                                    // set the default font
    initSerial();                                                   // initialise the UART used for the serial I/O
    USBDeviceInit();												// Initialise USB module SFRs and firmware
    initKeyboard();                                                 // initialise the keyboard and associated interrupt

    INTEnableInterrupts();

    uSec(100000);                                                   // allow everything to settle
	if(Option[O_STARTUPMSG]) VideoPrintString(MES_SIGNON); 			// print signon message

    while(1) {
        CheckUSB();
        ShowCursor(true);

        ch = getSerial();
        if(ch != -1) {
            VT100Putc(ch);
        }

        if(KeyDown != -1) {
            switch(KeyDown) {
                case UP:        putSerialString(mode == VT100 ? (AppCursorKeys ? "\033OA" : "\033[A") : "\033A");      break;
                case DOWN:      putSerialString(mode == VT100 ? (AppCursorKeys ? "\033OB" : "\033[B") : "\033B");      break;
                case LEFT:      putSerialString(mode == VT100 ? (AppCursorKeys ? "\033OD" : "\033[D") : "\033D");      break;
                case RIGHT:     putSerialString(mode == VT100 ? (AppCursorKeys ? "\033OC" : "\033[C") : "\033C");      break;
                case HOME:      putSerialString("\033[1~");     break;
                case INSERT:    putSerialString("\033[2~");     break;
                case DEL:       putSerialString("\033[3~");     break;
                case END:       putSerialString("\033[4~");     break;
                case PUP:       putSerialString("\033[5~");     break;
                case PDOWN:     putSerialString("\033[6~");     break;
                case F1:        putSerialString("\033[11~");    break;
                case F2:        putSerialString("\033[12~");    break;
                case F3:        putSerialString("\033[13~");    break;
                case F4:        putSerialString("\033[14~");    break;
                case F5:        putSerialString("\033[15~");    break;
                case F6:        putSerialString("\033[17~");    break;
                case F7:        putSerialString("\033[18~");    break;
                case F8:        putSerialString("\033[19~");    break;
                case F9:        putSerialString("\033[20~");    break;
                case F10:       putSerialString("\033[21~");    break;
                case F11:       putSerialString("\033[23~");    break;
                case F12:       putSerialString("\033[24~");    break;
                case F3+0x20:   putSerialString("\033[25~");    break;
                case F12+0x20:  break;                          // (this used to open the set-up menu, which has been removed)
                case ENTER:     if(NewLineMode) putSerialString("\r\n"); else putSerial(KeyDown);   break;
                default:        putSerial(KeyDown);             break;
            }
            KeyDown = -1;
            BlinkLED();
        }

    }
}



/*********************************************************************************************
* Serial I/O functions
**********************************************************************************************/

// initialize the UART2 serial port
void initSerial(void) {
    int cfg1, cfg2, baud = 0;
    PPSInput(2, U2RX, RPB1); PPSOutput(4, RPB0, U2TX);

    TRISAbits.TRISA1 = 1; CNPUASET = (1 << 1); uSec(10000);         // something changes pin A1 (I wish I knew what) and this puts it back

    cfg1 = UART_ENABLE_PINS_TX_RX_ONLY;
    if(baud > 9000) cfg1 |= UART_ENABLE_HIGH_SPEED;
    if(!Option[O_SERIALINV]) cfg1 |= (UART_INVERT_RECEIVE_POLARITY | UART_INVERT_TRANSMIT_POLARITY);

    cfg2 = UART_DATA_SIZE_8_BITS;
    switch(Option[O_PARITY]) {
        case O_PARITY_NONE: cfg2 |= UART_PARITY_NONE;    break;
        case O_PARITY_ODD:  cfg2 |= UART_PARITY_ODD;     break;
        case O_PARITY_EVEN: cfg2 |= UART_PARITY_EVEN;    break;
    }
    cfg2 |= Option[O_1STOPBIT] ? UART_STOP_BITS_1 : UART_STOP_BITS_2;

    switch(PORTBbits.RB4 << 2 | PORTBbits.RB3 << 1 | PORTAbits.RA1) {
        case 7: baud = 115200; break;                               // no jumpers: 115200 (the set-up menu that could change this has been removed)
        case 6: baud = 2400; break;
        case 5: baud = 4800; break;
        case 4: baud = 9600; break;
        case 3: baud = 19200; break;
        case 2: baud = 38400; break;
        case 1: baud = 57600; break;
        case 0: baud = 115200; break;
    }

    UARTConfigure(UART2, cfg1);
    UARTSetFifoMode(UART2, UART_INTERRUPT_ON_TX_NOT_FULL | UART_INTERRUPT_ON_RX_NOT_EMPTY);
    UARTSetLineControl(UART2, cfg2);
    UARTSetDataRate(UART2, BUSFREQ, baud);
    UARTEnable(UART2, UART_ENABLE_FLAGS(UART_PERIPHERAL | UART_RX | UART_TX));

    // Configure UART2 RX Interrupt (the Tx Interrupt is enabled in putSerial())
    INTSetVectorPriority(INT_VECTOR_UART(UART2), INT_PRIORITY_LEVEL_3);
    INTSetVectorSubPriority(INT_VECTOR_UART(UART2), INT_SUB_PRIORITY_LEVEL_0);
    INTEnable(INT_SOURCE_UART_RX(UART2), INT_ENABLED);
}


// UART 2 interrupt handler
void __ISR(_UART2_VECTOR, ipl3) IntUart2Handler(void) {

    if(INTGetFlag(INT_SOURCE_UART_RX(UART2))) {                     // Is this an RX interrupt?
        while(UARTReceivedDataIsAvailable(UART2)) {                 // while there is data to read
            if(UARTGetLineStatus(UART2) & 0b1110) {                 // first check for errors
                UARTGetDataByte(UART2);                             // and if there was an error throw away the char
                RxDropped++;
                U2STACLR = 0b1110;                                  // clear the error on the UART
                continue;                                           // and try the next char
            }
            {   int nh = SerialRxBufHead + 1;                       // where the head will be after this byte
                if(nh >= RxBufferSize) nh = 0;
                if(nh == SerialRxBufTail) {                         // the buffer is full: throw the new byte away.  (Letting the head catch up with the
                    UARTGetDataByte(UART2);                         // tail would make a full buffer look empty and everything in it would be lost)
                    RxDropped++;
                } else {
                    int fill;
                    SerialRxBuf[SerialRxBufHead] = UARTGetDataByte(UART2); // store the byte in the ring buffer
                    SerialRxBufHead = nh;
                    fill = nh - SerialRxBufTail;                    // how full is the ring now
                    if(fill < 0) fill += RxBufferSize;
                    if((unsigned int)fill > RxPeak) RxPeak = fill;
                }
            }
        }
        BlinkLED();
        INTClearFlag(INT_SOURCE_UART_RX(UART2));                      // Clear the RX interrupt Flag
    }

   if(INTGetFlag(INT_SOURCE_UART_TX(UART2))) {                      // Is this an Tx interrupt?
        while(UARTTransmitterIsReady(UART2) && SerialTxBufTail != SerialTxBufHead) { // while Tx is free and there is data to send
            INTDisableInterrupts();                                 // see Errata #10
            UARTSendDataByte(UART2, SerialTxBuf[SerialTxBufTail++]);// send the byte
            INTEnableInterrupts();
            SerialTxBufTail = SerialTxBufTail % SERIAL_TX_BUF_SIZE; // advance the tail of the queue
        }
        if(SerialTxBufTail == SerialTxBufHead)                      // if there is nothing left to send
            INTEnable(INT_SOURCE_UART_TX(UART2), INT_DISABLED);     // disable the interrupt
        INTClearFlag(INT_SOURCE_UART_TX(UART2));                    // Clear the Tx interrupt Flag
    }
}



// send a character to the Console serial port
void putSerial(int c) {
    SerialTxBuf[SerialTxBufHead++] = c;								// add the char
    SerialTxBufHead = SerialTxBufHead % SERIAL_TX_BUF_SIZE;         // advance the head of the queue
    INTEnable(INT_SOURCE_UART_TX(UART2), INT_ENABLED);              // enable Tx interrupt in case it was off
}


void putSerialString(char *p) {
    while(*p) putSerial(*p++);
}


// get a char from the UART1 serial port
// will return immediately with -1 if there is no character waiting
int getSerial(void) {
    unsigned char c;                                                // unsigned so that chars 0x80 - 0xFF are not returned as negative numbers
    if(SerialRxBufHead == SerialRxBufTail) return -1;
    c = SerialRxBuf[SerialRxBufTail++];
    if(SerialRxBufTail >= RxBufferSize) SerialRxBufTail = 0;
    return c;
}




/*********************************************************************************************
* USB I/O functions
**********************************************************************************************/



/******************************************************************************************
Check the USB for work to be done.
Used to send and get data to or from the USB interface.
Each call takes typically 6uS but sometimes it can be up to 600uS.
*******************************************************************************************/
void CheckUSB(void) {
	int i, numBytesRead;
	if(U1OTGSTAT & 0b1000) {													  // is there 5V on the USB?
	    USBDeviceTasks();													      // do any USB work

        if(USBGetDeviceState() == CONFIGURED_STATE) {

            // get data from the USB interface
            // figure out how much space is left in the serial TX buf and if it is less that the USB buffer try and get the USB data
            if(((SerialTxBufTail - SerialTxBufHead + SERIAL_TX_BUF_SIZE) % SERIAL_TX_BUF_SIZE) <= USB_DEVICE_RX_BUFFER_SIZE) {
                numBytesRead = getsUSBUSART(UsbDeviceRxBuf,USB_DEVICE_RX_BUFFER_SIZE);// check for data to be read
                if(numBytesRead > 0) {                                             // if we have some data,
                    for(i = 0; i < numBytesRead; i++)
                        putSerial(UsbDeviceRxBuf[i]);	                           // copy it into the serial output queue
                    BlinkLED();
                }
            }

            // send any data waiting to go
			if((SerialRxBufHead != USBSerialRxBufTail) && mUSBUSARTIsTxTrfReady()) {		  // next, check for data to be sent
                for(i = 0; SerialRxBufHead != USBSerialRxBufTail && i < USB_DEVICE_TX_BUFFER_SIZE; i++) {
                    UsbDeviceTxBuf[i] = SerialRxBuf[USBSerialRxBufTail++];                 // copy the char to the device buffer
                    if(USBSerialRxBufTail >= RxBufferSize) USBSerialRxBufTail = 0;
                    //SerialRxBufTail = SerialRxBufTail % RxBufferSize;
                }
				putUSBUSART(UsbDeviceTxBuf,i);	                                  // and send it
			}
		    CDCTxService();													      // do the actual send/receive
		}
	}
}



/******************************************************************************************
BOOL USER_USB_CALLBACK_EVENT_HANDLER
This function is called from the USB stack to notify a user application that a USB event
occured.  This callback is in interrupt context when the USB_INTERRUPT option is selected.

Args:  event - the type of event
       *pdata - pointer to the event data
       size - size of the event data

This function was derived from the demo CDC program provided by Microchip
*******************************************************************************************/
BOOL USER_USB_CALLBACK_EVENT_HANDLER(USB_EVENT event, void *pdata, WORD size)
{
    switch(event)
    {
        case EVENT_CONFIGURED:
            CDCInitEP();
             break;
//        case EVENT_SET_DESCRIPTOR:
//            break;
        case GRG_EVENT_EP0_REQUEST:
            break;
        case EVENT_SOF:
            break;
        case EVENT_SUSPEND:
            break;
        case EVENT_RESUME:
            break;
        case EVENT_BUS_ERROR:
            break;
        case EVENT_TRANSFER:
            Nop();
            break;
        default:
            break;
    }
    return TRUE;
}





/*********************************************************************************************
* Timer functions
**********************************************************************************************/




/***************************************************************************************************
InitTimer - Initialise the 1 mSec timer used for internal timekeeping.
****************************************************************************************************/
void initTimer(void) {
 	// setup timer 4
    PR4 = 1000 * (BUSFREQ/2/1000000) - 1;                           // 1 mSec
    T4CON = 0x8010;         										// T4 on, prescaler 1:2
    mT4SetIntPriority(1);  											// lower priority
    mT4ClearIntFlag();      										// clear interrupt flag
    mT4IntEnable(1);       											// enable interrupt
}



/****************************************************************************************************************
Timer 4 interrupt processor
This fires every mSec and is responsible for tracking the time and the counts of various timing variables
*****************************************************************************************************************/
void __ISR( _TIMER_4_VECTOR, ipl1) T4Interrupt(void) {

    if(LEDTimer)
        if(--LEDTimer < 25) LATBCLR = (1<<5);

    if(GeneralTimer) GeneralTimer--;

    if(++CursorTimer > CURSOR_OFF + CURSOR_ON) CursorTimer = 0;		// used to control cursor blink rate

    // Clear the interrupt flag
    mT4ClearIntFlag();
}


void BlinkLED(void) {
    if(LEDTimer  == 0) {
        LEDTimer = 75;
        LATBSET = (1<<5);
    }
}





/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Macro to reserve flash memory for saving/loading options and initialise to 0xFF's
// creates an array of integers 'name' with 'nbr' elements
// Note that 'nbr' need to be a multiple of 256 to fit the PIC32MX150/250 erase page size which is 1024 bytes
#define NVM_ALLOCATE(name, nbr) int name[(nbr)] \
	     __attribute__ ((aligned(1024),space(prog),section(".nvm"))) = \
	     { [0 ...(nbr)-1] = 0xFFFFFFFF }

// allocate space in flash for the options.  The start of the memory is aligned on erasable page boundary
NVM_ALLOCATE(Option, 256);



// The on screen set-up menu (SetUp(), F12 with Shift) has been removed to save flash.  The options are never written so Option[] stays erased
// (every item is -1) which means the defaults: 24 lines, PAL for composite, US keyboard, 8 bits no parity, 1 stop bit, normal serial polarity, 115200 baud with
// no jumpers, start up message shown, CP437 extended characters, control codes 01-1F on.



int GetFlashOption(const unsigned int *w) {
    return O_KEYBOARD_US;
}



#ifdef __DEBUG

void dump(char *p, int nbr) {
	char inpbuf[100], buf1[60], buf2[30], *b1, *b2;
	b1 = buf1; b2 = buf2;
	b1 += sprintf(b1, "%8x: ", (unsigned int)p);
	while(nbr > 0) {
		b1 += sprintf(b1, "%02x ", *p);
		b2 += sprintf(b2, "%c", (*p >= ' ' && *p < 0x7f) ? *p : ' ');
		p++;
		nbr--;
		if((unsigned int)p % 16 == 0) {
			sprintf(inpbuf, "%s   %s", buf1, buf2);
//			MMPrintString(inpbuf);
			b1 = buf1; b2 = buf2;
			b1 += sprintf(b1, "\r\n%8x: ", (unsigned int)p);
		}
	}
	if(b2 != buf2) {
		sprintf(inpbuf, "%s   %s", buf1, buf2);
//		MMPrintString(inpbuf);
	}
//	MMPrintString("\r\n");
}

#endif
