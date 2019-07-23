// *******************************************************************************************************************************
// *******************************************************************************************************************************
//
//		Name:		sys_processor.c
//		Purpose:	Processor Emulation.
//		Created:	12th July 2019
//		Author:		Paul Robson (paul@robsons.org.uk)
//
// *******************************************************************************************************************************
// *******************************************************************************************************************************

#include <stdio.h>
#include "sys_processor.h"
#include "sys_debug_system.h"
#include "hardware.h"

// *******************************************************************************************************************************
//														   Timing
// *******************************************************************************************************************************

#define CYCLE_RATE 		(1*1000*1000)												// Cycles per second (0.96Mhz)
#define FRAME_RATE		(60)														// Frames per second (50 arbitrary)
#define CYCLES_PER_FRAME (CYCLE_RATE / FRAME_RATE)									// Cycles per frame (20,000)

// *******************************************************************************************************************************
//														CPU / Memory
// *******************************************************************************************************************************

static BYTE8 a,x,y,s;																// 6502 A,X,Y and Stack registers
static BYTE8 carryFlag,interruptDisableFlag,breakFlag,								// Values representing status reg
			 decimalFlag,overflowFlag,sValue,zValue;
static WORD16 pc;																	// Program Counter.
static BYTE8 ramMemory[RAMSIZE];													// Memory at $0000 upwards
static LONG32 cycles;																// Cycle Count.

// *******************************************************************************************************************************
//											 Memory and I/O read and write macros.
// *******************************************************************************************************************************

#define Read(a) 	_Read(a)														// Basic Read
#define Write(a,d)	_Write(a,d)														// Basic Write

#define ReadWord(a) (Read(a) | ((Read((a)+1) << 8)))								// Read 16 bit, Basic

#define ReadWord01(a) (ramMemory[a]+(ramMemory[(a+1)] << 8))						// Read 16 bit, page 0/1 
#define Read01(a) 	(ramMemory[a])													// Read 8 bit, page 0/1
#define Write01(a,d) { ramMemory[a] = (d); }										// Write 8 bit, page 0/1

#define Cycles(n) 	cycles += (n)													// Bump Cycles

#define Fetch() 	_Read(pc++)														// Fetch byte
#define FetchWord()	{ temp16 = Fetch();temp16 |= (Fetch() << 8); }					// Fetch word

static inline BYTE8 _Read(WORD16 address);											// Need to be forward defined as 
static inline void _Write(WORD16 address,BYTE8 data);								// used in support functions.

#include "6502/__6502support.h"

// *******************************************************************************************************************************
//											   Read and Write Inline Functions
// *******************************************************************************************************************************

static inline BYTE8 _Read(WORD16 address) {
	return ramMemory[address];							
}

static inline void _Write(WORD16 address,BYTE8 data) {
	if (address < 0xA000) {															// RAM 0000-A000
		ramMemory[address] = data;
		return; 
	}
	if (address >= 0xD000 && address <= 0xD800) { 									// Write to vram
		if (ramMemory[address] != data) { 											// color ram
			ramMemory[address] = data; 												// control register
			HWWriteDisplay(address,data);
		}	
		return;
	}
	if (address == 0xDF00) { 														// Write to keyboard
		ramMemory[0xDF00] = HWWriteKeyboard(data);
	}
}

// *******************************************************************************************************************************
//														Reset the CPU
// *******************************************************************************************************************************

#include "basic_rom.inc"
#include "monitor_rom.inc"

#ifdef INCLUDE_DEBUGGING_SUPPORT
static void CPULoadChunk(FILE *f,BYTE8* memory,int count);
#endif

void CPUReset(void) {

	HWReset();																		// Reset Hardware
	for (int i = 0;i < 2048;i++) ramMemory[0xF800+i] = monitor_rom[i];				// Copy ROM images in
	for (int i = 0;i < 8192;i++) ramMemory[0xA000+i] = basic_rom[i];


	#ifdef INCLUDE_DEBUGGING_SUPPORT 												// In Debug versions can
	FILE *f = fopen("monitor.rom","rb"); 											// read in new ROMs if in
	if (f != NULL) {																// current directory.
		CPULoadChunk(f,ramMemory+0xF800,0x800);
		fclose(f);
	}
	f = fopen("basic.rom","rb");
	if (f != NULL) {
		CPULoadChunk(f,ramMemory+0xA000,0x2000);
		fclose(f);
	}
	#endif

	if (ramMemory[0xA000] == 0x39 && ramMemory[0xA001] == 0xA6 && 					// If standard BASIC.
		ramMemory[0xA002] == 0x55 && ramMemory[0xA003] == 0xA5)

	{
		if (ramMemory[0xF800] == 0) {												// New monitor ?
			ramMemory[0xA27E] = ramMemory[0xFFE3];
			ramMemory[0xA27F] = ramMemory[0xFFE4];
		}
	}
	resetProcessor();																// Reset CPU
}

// *******************************************************************************************************************************
//					Called on exit, does nothing on ESP32 but required for compilation
// *******************************************************************************************************************************

#ifdef INCLUDE_DEBUGGING_SUPPORT
#include "gfx.h"
void CPUExit(void) {	
	GFXExit();
}
#else
void CPUExit(void) {}
#endif

// *******************************************************************************************************************************
//												Execute a single instruction
// *******************************************************************************************************************************

BYTE8 CPUExecuteInstruction(void) {
	BYTE8 opcode = Fetch();															// Fetch opcode.
	switch(opcode) {																// Execute it.
		#include "6502/__6502opcodes.h"
	}
	if (cycles < CYCLES_PER_FRAME) return 0;										// Not completed a frame.
	cycles = cycles - CYCLES_PER_FRAME;												// Adjust this frame rate.
	HWSync();																		// Update any hardware
	return FRAME_RATE;																// Return frame rate.
}

// *******************************************************************************************************************************
//												Read/Write Memory
// *******************************************************************************************************************************

BYTE8 CPUReadMemory(WORD16 address) {
	return Read(address);
}

void CPUWriteMemory(WORD16 address,BYTE8 data) {
	Write(address,data);
}

#ifdef INCLUDE_DEBUGGING_SUPPORT

// *******************************************************************************************************************************
//		Execute chunk of code, to either of two break points or frame-out, return non-zero frame rate on frame, breakpoint 0
// *******************************************************************************************************************************

BYTE8 CPUExecute(WORD16 breakPoint1,WORD16 breakPoint2) { 
	BYTE8 next;
	do {
		BYTE8 r = CPUExecuteInstruction();											// Execute an instruction
		if (r != 0) return r; 														// Frame out.
		next = CPUReadMemory(pc);
	} while (pc != breakPoint1 && pc != breakPoint2 && next != 0x03);				// Stop on breakpoint or $03 break
	return 0; 
}

// *******************************************************************************************************************************
//									Return address of breakpoint for step-over, or 0 if N/A
// *******************************************************************************************************************************

WORD16 CPUGetStepOverBreakpoint(void) {
	BYTE8 opcode = CPUReadMemory(pc);												// Current opcode.
	if (opcode == 0x20) return (pc+3) & 0xFFFF;										// Step over JSR.
	return 0;																		// Do a normal single step
}

void CPUEndRun(void) {
	FILE *f = fopen("memory.dump","wb");
	fwrite(ramMemory,1,RAMSIZE,f);
	fclose(f);
}

static void CPULoadChunk(FILE *f,BYTE8* memory,int count) {
	while (count != 0) {
		int qty = (count > 4096) ? 4096 : count;
		fread(memory,1,qty,f);
		count = count - qty;
		memory = memory + qty;
	}
}
void CPULoadBinary(char *fileName) {
	FILE *f = fopen(fileName,"rb");
	if (f != NULL) {
		CPULoadChunk(f,ramMemory,RAMSIZE);
		fclose(f);
		resetProcessor();
	}
}

// *******************************************************************************************************************************
//											Retrieve a snapshot of the processor
// *******************************************************************************************************************************

static CPUSTATUS st;																	// Status area

CPUSTATUS *CPUGetStatus(void) {
	st.a = a;st.x = x;st.y = y;st.sp = s;st.pc = pc;
	st.carry = carryFlag;st.interruptDisable = interruptDisableFlag;st.zero = (zValue == 0);
	st.decimal = decimalFlag;st.brk = breakFlag;st.overflow = overflowFlag;
	st.sign = (sValue & 0x80) != 0;st.status = constructFlagRegister();
	st.cycles = cycles;
	return &st;
}

#endif