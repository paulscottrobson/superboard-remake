;
BasicROM =  $A000   					; basic rom
DiskController = $C000   				; diskcontroller controller (pia = +$00, acia = +$10)
Screen = $D000   						; screen ram
Keyboard = $DF00   						; keyboard port

ClockMhz = 1 							; clock speed in MHz (affects repeat timing)

;                   
;		Acia = $f000 ; for c1/uk101/superboard
;  		Acia = $fc00 ; serial port (mc6850 acia) for c2/c4
;
acia = $f000 

;
;		Basic routines.
;
BASIC_WarmStart = $0000				
BASIC_ColdStart = $BD11
BASIC_ControlC = $A636
BASIC_OldScreenHandler = $BF2D

;
;		Screen information
;
ScreenMemory = $D000 						; screen position
ScreenMemorySize = $0400 					; screen size, total.
ScreenFiller = 96 							; clear screen / eol character. (204 for debugging)
LineWidth = 32  							; screen width
LineShift = 5 								; 2^n = screen width.
FirstVisible = 133 							; screen offset to first visible character.
ColumnsVisible = 24 						; columns displayed
RowsVisible = 24  							; rows displayed

ScreenTop = ScreenMemory+FirstVisible		; first/last visible lines 
ScreenBottom = ScreenTop + (RowsVisible-1)*LineWidth

KeyboardInvert = 1 							; 0 if keyboard active high, 1 if active low.

NMIHandler = $130  							; nmi address
IRQHandler = $1C0  							; irq address

MonBytesPerLine = 4  						; bytes displayed
MonLinesDisplayed = ColumnsVisible-2 		; lines displayed.

CharsSinceCR = $E 							; chars printed since CR

CPURegisters = $F7							; CPU Registers
CPU_A = CPURegisters+0
CPU_X = CPURegisters+1
CPU_Y = CPURegisters+2
CPU_P = CPURegisters+3

MonAddress = $FB 							; monitor current address.
InputFromSerial = $FD 						; if non-zero input from ACIA
IndirectWork = $FE 							; working indirect address.
CursorX = $200    							; cursor offset horizontal.
CursorY = $201 								; cursor offset vertical
NewChar = $202    							; new character for new screen handler.
ACIALoadFlag = $203  						; $00 off, $ff acia load
ACIASaveFlag = $205  						; $00 off, $ff save to acia
ScreenDelay = $206   						; screen delay (400 cycles/count)
CursorCharacter = $207 						; character under the cursor
LastKeyValue = $208 						; key currently pressed, 0 = None.
RepeatCount = $209 							; repeat down counter, even for first, odd for subsequent.
BreakDisabled = $212  						; non-zero if break disabled.
CurrentKeyIndex = $213 						; key index pressed
AddressMode = $214 							; 0 = address mode, $80 = data mode.

VectorArea = $218 
LastCharOnLine = $222  						; index of last character on line.
ScrollCopier = $223 						; RAM based scroll copier.
CharSrcPosition = $224
WriteToCurrent = $226						
CharPosition = $227

 	*= $F800
 	.byte 	$00 							; identifies new monitor.
 	
; ********************************************************************************
;
;									Run the Monitor
;
; ********************************************************************************

MonitorColdStart:
	jsr 	ClearScreen 					; clear + home, set up char position.
	lda 	#0 								; into address mode
	sta 	MonAddress 						; reset address.
	sta 	MonAddress+1
MonSetAddressModeAndPaint:
	lda 	#0	
MonSetModeAndPaint:	
	sta 	AddressMode

; ********************************************************************************
;
;						Main Repaint loop, draws memory
;
; ********************************************************************************

MonRepaintLoop:	
	jsr 	HomeCursor 						; write mode at the top.
	;
	lda 	MonAddress 						; address to start from.
	sec
	sbc 	#16
	and 	#256-MonBytesPerLine
	sta 	IndirectWork
	lda 	MonAddress+1
	sbc 	#0
	sta 	IndirectWork+1
	;
	ldx 	#ColumnsVisible/2-8 			; mode text, either Address/Data mode.
	ldy 	#MonAddressModeText-MonitorColdStart
	lda 	AddressMode
	beq 	MonPrintString
	ldy 	#MonDataModeText-MonitorColdStart
MonPrintString:
	lda 	MonitorColdStart,y
	iny
	jsr 	MonWrite
	lda 	MonitorColdStart,y	
	bne 	MonPrintString
	tay 	 								; memory position, offset.

; ********************************************************************************
;
;								Start of next line.
;
; ********************************************************************************

MonitorNewLine:								
	jsr 	MonSpace
	txa
	and 	#LineWidth-1
	bne 	MonitorNewLine
	;
	jsr 	MonWriteDataLine
	;
	cpy 	#(MonBytesPerLine * MonLinesDisplayed)
	bne 	MonitorNewLine
	;
	jsr 	HomeCursor 						; out of the way
MonGetCommand:	
	jsr 	InputCharacter
	cmp 	#"."							; . switch mode address
	beq 	MonSetAddressModeAndPaint
	cmp 	#"/"							; / switch mode data
	beq 	MonSetModeAndPaint
	cmp 	#","							; , backwards
	beq 	MonBackBump
	cmp 	#33 							; Space/CR bump address.
	bcc 	MonBump
	cmp 	#$60 							; case change, quick.
	bcc 	_MGCNotLower
	and 	#$DF 							; lazy caps.
_MGCNotLower:	
	cmp 	#"0" 							; check range 0-G for hex digit.
	bcc 	MonGetCommand 
	cmp 	#"G"
	beq 	MonRunProgram
	bcs 	MonGetCommand
	;
	sbc 	#"0"-1 							; actually "0", because CC
	cmp 	#10 							; if was 0-9
	bcc 	MonHexDigit 					; you have the digit.
	sbc 	#7 								; try A-F
	bcc 	MonGetCommand 					; too low.

; ********************************************************************************
;
;									Hex Digit
;
; ********************************************************************************

MonHexDigit:		
	ldx 	AddressMode 					; data mode ?
	bne 	_MHDData
	ldx 	MonAddress 						; rotate nibble through address.
	jsr 	MonRotateNibble 
	stx 	MonAddress
	ldx 	MonAddress+1
	jsr 	MonRotateNibble 
	stx 	MonAddress+1
	jmp 	MonRepaintLoop					
	;
_MHDData: 									; rotate nibble through (indirectwork)
	pha 									; byte only.
	ldy 	#0
	lda 	(MonAddress),y	
	tax
	pla
	jsr 	MonRotateNibble
	txa
	sta 	(MonAddress),y
	jmp 	MonRepaintLoop					
	;
MonAddressModeText:
	.text 	"Address Mode",0
MonDataModeText:
	.text 	"Data Mode",0

; ********************************************************************************
;
;									Forward
;
; ********************************************************************************

MonBump:	
	inc 	MonAddress
	bne 	_MAANoBump
	inc 	MonAddress+1
_MAANoBump:	
	jmp 	MonRepaintLoop

; ********************************************************************************
;
;									Backward
;
; ********************************************************************************

MonBackBump:
	lda 	MonAddress
	bne 	_MBBNoBorrow
	dec 	MonAddress+1
_MBBNoBorrow:	
	dec 	MonAddress
	jmp 	MonRepaintLoop

; ********************************************************************************
;
;								 Run Program
;
; ********************************************************************************

MonRunProgram:
	lda 	CPU_P 							; load PAXY and go to current routine.
	pha
	lda 	CPU_A
	ldx 	CPU_X
	ldy 	CPU_Y
	plp
	jsr 	MonExecute
	php
	sta 	CPU_A 	 						; reload AXYP
	stx 	CPU_X
	sty 	CPU_Y
	pla
	sta 	CPU_P
	jmp 	MONRepaintLoop
;
MonExecute:
	jmp		(MonAddress)

; ********************************************************************************
;
;			Seperate out because of long branches - this draws the
;			address, marker, bytes and characters for the line.
;
; ********************************************************************************

MonWriteDataLine:
	tya 									; add offset to indirect work and print it.
	clc 									; where this line starts.
	adc 	IndirectWork 		
	pha
	lda 	IndirectWork+1
	adc 	#0
	jsr 	MonByte 						; output byte in A
	pla
	jsr 	MonByte 						; output byte in A.
	;
	tya 									; push Y on the stack
	pha
_MDBytesOut: 								; row of bytes.	
	tya 									; offset
	clc
	adc 	IndirectWork 					; add the LSB of indirect work.
	eor 	MonAddress 						; offset ?
	beq		_MDNotWritePoint
	lda 	#32^235
_MDNotWritePoint:	
	eor 	#235
	jsr 	MonWrite
	lda 	(IndirectWork),y
	iny 
	jsr 	MonByte
	tya
	and 	#(MonBytesPerLine-1)
	bne 	_MDBytesOut
	;
	pla 									; restore Y
	tay
	jsr 	MonSpace
_MDCharsOut: 								; row of characters
	lda 	(IndirectWork),y
	iny 
	jsr 	MonWrite
	tya
	and 	#(MonBytesPerLine-1)
	bne 	_MDCharsOut
	rts

; ********************************************************************************
;
;		Rotate Nibble A through X shifting old X back into A.
;
; ********************************************************************************

MonRotateNibble:
	asl		a 								; shift nibble into upper bits.
	asl 	a
	asl 	a
	asl 	a	
	stx 	NewChar 						; use this for X.
	;
	asl 	a 								; shift first bit into A
	rol 	NewChar 						; rotate first into new, 
	rol 	a 								; shift old bit into A, new bit from C.
	rol 	NewChar 						; rotate it into the new character
	rol 	a 								; shift old bit into A, new bit from C.
	rol 	NewChar 						; rotate it into the new character
	rol 	a 								; shift old bit into A, new bit from C.
	rol 	NewChar 						; rotate it into the new character
	rol 	a
	;
	ldx 	NewChar
	rts	

; ********************************************************************************
;
;								Output a byte at screen,X
;
; ********************************************************************************

MonByte:
	pha 								
	lsr 	a
	lsr 	a
	lsr 	a
	lsr 	a
	jsr 	_MONNibble
	pla
_MONNibble:	
	and 	#$0F
	cmp 	#10
	bcc 	_MBNotAlpha
	adc 	#7-1
_MBNotAlpha:
	adc 	#48
	bne 	MonWrite
MONSpace:
	lda 	#" "
MONWrite:		
	jsr 	WriteToCurrent
	inx
	bne 	MonWriteExit
	inc 	CharPosition+1
MONWriteExit:	 	
	rts

; ********************************************************************************
;
;                                     rubout handler
;
; ********************************************************************************

RuboutCode:
	lda  	CharsSinceCR 						; adjust chars since CR
	beq  	DoRubout
	dec  	CharsSinceCR
	beq  	DoRubout
	dec  	CharsSinceCR
DoRubout:
	lda  	#' ' 								; overwrite character at this point. X already 0.
	jsr 	WriteToCurrent
	jsr 	CursorLeft 							; move the cursor to the left.
	lda  	#' ' 								; overwrite character at this point. X already 0.
	jsr 	WriteToCurrent
	;
NewScreenHandlerExit:
	pla 										; restore AXY and exit. 
	tay
	pla
	tax
	pla
	rts

; ********************************************************************************
;                                        
;                               new screen handler
;                                        
; ********************************************************************************

NewScreenHandler:
	sta  	NewChar 							; save character
	pha   										; save AXY
	txa   										
	pha  
	tya  
	pha  
	lda  	NewChar 							; get character
	beq 	NewScreenHandlerExit 				; do not print NULL.
	;
	ldy  	ScreenDelay                      	; screen delay ?
	beq  	NoDelay 
	jsr  	Delay2 								; if so, call the delay routine.
NoDelay:
	ldx 	#0 									; X = 0 for the in memory code.
	cmp  	#$5F 								; _ is the rubout character
	beq  	RuboutCode
	cmp  	#$C 								; check for Ctrl-L (home cursor)
	beq  	CtrlLHandler
	cmp  	#$A 								; line feed
	beq  	LineFeedHandler
	cmp  	#$B 								; move right ?
	beq  	MoveRightHandler
	cmp  	#$1A								; Ctrl-Z
	beq  	ControlZHandler
	cmp  	#$D 								; carriage return ?
	beq 	CarriageReturnHandler
;
;								Standard screen print.
;
	jsr 	WriteToCurrent 						; write it out, then fall through into cursor-right.
;
;								 Handle Cursor Right
;
MoveRightHandler:
	jsr 	CursorRight 						; right cursor, Z flag clear on Return.
	bne 	NewScreenHandlerExit
;
;								Ctrl-Z clear screen
;
ControlZHandler:
	jsr 	ClearScreen 						; clear screen.
	bne 	NewScreenHandlerExit
;
;                                     ctrl-l
;
CtrlLHandler:
	jsr  	HomeCursor 							; home cursor, Z flag clear on Return.
	bne 	NewScreenHandlerExit
;
;									Handle Line Feed
;
LineFeedHandler:
	jsr 	CursorDown 							; down cursor, Z flag clear on Return.	
	bne 	NewScreenHandlerExit
;
;                                 	Carriage Return.
;
CarriageReturnHandler:
	lda 	#0
	sta 	CursorX
	jsr	 	RecalculateCursorAddress
	bne 	NewScreenHandlerExit

; ********************************************************************************
;
;									Cursor movement code
;
; ********************************************************************************

CursorRight:
	inc 	CursorX 							; move right
	lda 	CursorX 							; check RHS
	eor 	#ColumnsVisible 					; will be zero if matches
	bne  	CursorMoveExit
	sta 	CursorX 							; reset cursor position to 0 and fall through.
;
CursorDown:
	inc 	CursorY 							; move down.
	lda 	CursorY
	eor 	#RowsVisible 						; will be zero if matches.
	bne 	CursorMoveExit
	dec 	CursorY 							; back up again, to last line.
	;
	;		Scroll screen up code.
	;
	sta 	CharPosition 						; point CharPosition to the first block.
	lda 	#LineWidth 
	sta 	CharSrcPosition 					; and the source address. to the first block second line.
	lda 	#ScreenMemory/256 
	sta 	CharPosition+1
	sta 	CharSrcPosition+1

ScrollScreen:
	ldx 	#0
CopyScreenPage:	
	jsr 	ScrollCopier 						; copy one line.
	inx 
	bne 	CopyScreenPage 						; page copied ?
	inc 	CharSrcPosition+1 					; bump to next page.
	inc 	CharPosition+1
	lda 	CharPosition+1 						; reached the screen bottom.
	cmp 	#(ScreenMemory+ScreenMemorySize)>>8
	bne 	ScrollScreen
	;
	dec 	CharPosition+1 						; now points to the start of the last page.
	; 											; start of last line, in that page.
	ldx 	#(FirstVisible+(RowsVisible-1)*LineWidth) & $FF
ClearBottomLine: 								; clear it with filler.
	lda 	#ScreenFiller
	jsr 	WriteToCurrent
	inx
	cpx 	#(FirstVisible+(RowsVisible-1)*LineWidth+ColumnsVisible) & $FF
	bne 	ClearBottomLine
	beq 	CursorMoveExit
;
CursorLeft:
	dec 	CursorX 							; back one.
	bpl 	CursorMoveExit						; if >= 0 then exit.
	lda 	#ColumnsVisible-1 					; end of the previous line.
	sta 	CursorX
;
CursorUp:
	dec 	CursorY 							; up one
	bpl 	CursorMoveExit 						; if >= 0 then exit.
	lda 	#RowsVisible-1 						; bottom of the screen
	sta 	CursorY
CursorMoveExit:
	jmp 	RecalculateCursorAddress 			; update cursor address.

; ********************************************************************************
;
;							Fixed Basic Read Screen Line
;
; ********************************************************************************

FixedBasicReadScreenLine:
	ldx 	#$13 								; this is the input buffer in OSI Basic.
	ldy 	#0
	jsr 	ReadScreenLine
	dex 										; return the byte before. 
	rts

; ********************************************************************************
;
;							Read line from screen Editor
;
; ********************************************************************************

ReadScreenLine:
	stx 	IndirectWork						; save  X & Y
	sty 	IndirectWork+1
_RSLEdit:
	jsr 	InputCharacter 						; read a character.
	tax 										; check $01-$7F
	beq 	_RSLEdit
	bmi 	_RSLEdit
	cmp 	#"C"-64 							; ignore Ctrl+C
	beq 	_RSLEdit
	cmp 	#"A"-64								; Ctrl+A
	beq 	_RSLLeft
	cmp 	#"S"-64								; Ctrl+S
	beq 	_RSLDown
	cmp 	#"D"-64								; Ctrl+D
	beq 	_RSLRight
	cmp 	#"W"-64								; Ctrl+W
	beq 	_RSLUp
_RSLEchoLoop:
	jsr 	OutputCharacter 					; output character
	cmp 	#13 								; if not CR, go round again.
	bne 	_RSLEdit

_RSLExit:
	ldy 	#0 									; index into indirectwork, cursor now at start.
_RSLFetch:
	ldx 	#0 									; read character there.
	jsr 	ScrollCopier 						; (and write it)
	cmp 	#ScreenFiller 						; found something that's not LISTed or whatever ?
	beq 	_RSLDone 							; if so then exit.
	sta 	(IndirectWork),y 					; write it out.
	tya 										; save Y
	pha
	jsr 	CursorRight 						; move cursor right
	pla 										; restore Y
	tay 	
	iny 										; next slot.
	lda 	CursorY 							; reached the bottom-right ?
	cmp 	#RowsVisible-1
	bne 	_RSLFetch
	lda 	CursorX
	cmp 	#ColumnsVisible-1
	bne 	_RSLFetch	
_RSLDone:	 									; trim trailing spaces.
	dey
	beq 	_RSLLastNonSpace
	lda 	(IndirectWork),y
	cmp 	#" "
	beq 	_RSLDone
_RSLLastNonSpace:
	iny	
	lda 	#0 									; add EOL marker
	sta 	(IndirectWork),y
	sta 	CursorX 							; start of line
	jsr 	CursorDown 							; move down
	ldx 	IndirectWork 						; return indirect work ptr in x,y
	ldy 	IndirectWork+1
	rts
	;
	;		Handle Cursor Movement.
	;
_RSLLeft: 										; handle cursor movement.
	jsr 	CursorLeft
	bne 	_RSLEdit
_RSLRight:
	jsr 	CursorRight
	bne 	_RSLEdit
_RSLUp:
	jsr 	CursorUp
	bne 	_RSLEdit
_RSLDown:
	jsr 	CursorDown
	bne 	_RSLEdit

; ********************************************************************************
;                                        
;                       Input Character from ACIA/Keyboard
;                                        
; ********************************************************************************

VectoredInput:
	bit  	ACIALoadFlag 						; check coming fom ACIA
	bpl  	ReadKeyboard  			

CheckExitLoad:
	.ifeq 	KeyboardInvert
	lda  	#2 									; read row 2 where the space bar is.
	.else
	lda 	#253
	.endif
	sta 	Keyboard

	lda 	Keyboard 							; check key pressed
	and 	#$10	
	.ifeq 	KeyboardInvert
	bne  	ACIASpaceBreak                      ; space key pressed so interrupt
	.else
	beq 	ACIASpaceBreak
	.endif

; ********************************************************************************
;                                        
;                                 input from acia
;                                        
; ********************************************************************************

ReadACIA:
	lda  	Acia 								; read ACIA control
	lsr  	a 									; check recieve data reg full (bit 0)
	bcc  	CheckExitLoad 						; nope ; check space and go round again.
	lda  	Acia+1 								; get character.
	rts  

ACIASpaceBreak: 								; space interrupts ACIA read
	lda  	#0 									; reset two sources
	sta  	InputFromSerial
	sta  	ACIALoadFlag
	jmp 	VectoredInput


; ********************************************************************************
;                                        
;                                  ctrl-c check
;                                        
; ********************************************************************************

ControlCCheck:
	lda  	BreakDisabled
	bne  	Exit2                            	; disable flag set

	.ifeq   KeyboardInvert  					; bit pattern to write, check CTRL
	lda  	#1
	.else
	lda  	#254
	.endif
	sta 	Keyboard 							; write to rows.

	bit  	Keyboard
	.ifeq   KeyboardInvert  					; bit to check.
	bvc  	Exit2                                  
	.else
	bvs  	Exit2                                  
	.endif

	.ifeq   KeyboardInvert  					; bit pattern to write, check C
	lda  	#4
	.else
	lda  	#251
	.endif
	sta 	Keyboard 							; write to rows.

	bit  	Keyboard
	.ifeq   KeyboardInvert  					; bit to check.
	bvc  	Exit2
	.else
	bvs  	Exit2
	.endif

	lda  	#3                                  ; ctrl-c pressed
	jmp  	BASIC_ControlC						; this is a BASIC routine.

; ********************************************************************************
;                                        
;                                    init acia
;                                        
; ********************************************************************************

ResetACIA:
	lda  	#3                                  ; reset acia
	sta  	Acia
;
;   (c1/c2) c2 initializes with $b1, the c1 initializes with $11.
; 	i would think that this is generally of no consequence, since the acia's irq is not
; 	connected to the irq line by default.
;
	lda  	#$B1                               	; /16, 8bits, 2stop, rts low, irq on recv.
;
;   lda #$11 ; /16, 8bits, 2stop, rts low
;
	sta  	Acia
Exit2:	
	rts  

; ********************************************************************************
;                                        
;                               output char to acia
;                                        
; ********************************************************************************

WriteACIA:
	pha   										; save to write.
WaitTDRE:
	lda  	Acia 								; get bit 1, which is transmit data empty
	lsr  	a
	lsr  	a
	bcc  	WaitTDRE
	pla   										; restore and write the byte to send.
	sta  	Acia+1
	rts  


; ********************************************************************************
;                                        
;                                delay 6500 Cycles
;                                        
; ********************************************************************************

KeyboardDelay:									; specific delay, scaled for CPU Speed.
	ldy  #$1F*ClockMhz
Delay2: 										; user specified delay
	ldx  #$40
DelayLoop: 										; delay loop.
	dex  
	bne  DelayLoop
	dey  
	bne  Delay2
	rts  

; ********************************************************************************
;                                        
; 	keyboard input routine - handles debounces/repeats, waits for a key.
;									(like GET)
;                                        
; ********************************************************************************

ReadKeyboard:
	txa 										; push XY on the stack
	pha
	tya
	pha
	ldx 	#0 									; load and save the character under the cursor.
	jsr 	ScrollCopier
	sta 	CursorCharacter
	lda 	#187 								; write the cursor there.
	jsr 	WriteToCurrent
	bne 	RKScanLoop 							; and enter the inner loop.
	;
	;		Come back here when no key pressed or key change occurs. Zeroes last key value, resets the repeat count 
	;		(for debouncing). The even repeat count indicates that it's the debouncing one.
	;
RKScanLoopClearRepeat:	
	sta 	LastKeyValue 						; update last key value
	lda 	#2 									; set low even repeat count.
	sta 	RepeatCount
	;
	;		Main check loop
	;
RKScanLoop:
	jsr 	ScanKeyboard 						; get keyboard new value
	cmp 	#0 
	beq 	RKScanLoopClearRepeat 				; if no key pressed keep going round, resetting.
	cmp 	LastKeyValue 						; same as last value ?	
	bne 	RKScanLoopClearRepeat 				; has changed, so keep going till not changed and key pressed.
	;
	;		Key is same, check repeat count.
	;
RKCheckRepeatCount:
	jsr 	KeyboardDelay						; keyboard delay.
	dec 	RepeatCount 						; decrement repeat count by two.
	dec 	RepeatCount	
	bpl 	RKScanLoop 							; if >= 0 go round again.
	;
	ldx 	#0 									; put original character back.
	lda 	CursorCharacter
	jsr 	WriteToCurrent
	;
	lsr 	RepeatCount 						; C = 0 first time, 1 second time.
	lda 	#127								; repeat count if even, delay till next char, then odd
	bcc 	RKNotDelayed
	lda 	#9 									; then fire them out more rapidly, still odd.		
RKNotDelayed:	
	sta 	RepeatCount
	pla 										; restore YX
	tay
	pla	
	tax
	lda 	LastKeyValue 						; return that last key value.
	rts

; ********************************************************************************
;
;	  Scans the keyboard for the current key pressed. No debounce, repeat etc.
;									(like INKEY)
;
; ********************************************************************************

ScanKeyboard:
	txa 										; save XY on the stack.
	pha
	tya
	pha
	ldx 	#$80 								; start scanning with the control row (RPT/CTRL/ESC etc.)
	ldy 	#7 									; offset into table 7 because we scan backwards when bit counting.
ScanCheckLoop:
	txa 										; write to keyboard
	.ifne 	KeyboardInvert 						; inverting if required
	eor 	#$FF
	.endif
	sta 	Keyboard
	;											; Do we need a short delay here ?
	lda 	Keyboard 							; read the columns
	.ifne 	KeyboardInvert 						; inverting if required
	eor 	#$FF
	.endif
	lsr 	a 									; shift everything right chucking the shift-lock bit.
	bne 	SCLKeyPressed 						; if non-zero a key is pressed.
	;
SCLKeyContinue:
	tya 										; zero, advance table offset by 7.
	clc
	adc 	#7
	tay
	txa 										; shift the bit right
	lsr 	a
	tax
	bne 	ScanCheckLoop						; when zero, it's time to give up.
SCLExit:
	sta 	CurrentKeyIndex 					; save return value.
	pla 										; restore YX
	tay
	pla 
	tax
	lda 	CurrentKeyIndex 					; and return A.
	rts
	;
	;		Key is pressed.
	;
SCLKeyPressed:
	cpx 	#$01 								; is X $01, e.g. is it the control row.
	beq 	SCLCheckEscape
SCLFindIndex:
	dey 										; work backwards in the table.
	asl 	a 									; shift A left
	bpl 	SCLFindIndex 						; until bit 7 set, then Y should point to the character.
	lda 	KeyboardCharTable,y  				; get the character we are returning.
	tay 										; save in Y.
	;
	.ifeq 	KeyboardInvert 						; read the first row R0 again.
	lda 	#1 
	.else
	lda 	#$FE
	.endif
	sta 	Keyboard 							; set rows
	lda 	Keyboard 							; read columns
	.ifne 	KeyboardInvert 						; handle inverted keyboard designs.
	eor 	#$FF
	.endif
	asl 	a 									; shift it right
	bmi 	SCLControl 							; is it a control character ?
	cpy 	#$21 								; can't shift control keys.
	bcc 	SCLExitY
	and 	#$0E 								; is shift lock or shift pressed ? (it's shifted left one !)
	bne 	SCLShift
SCLExitY:	
	tya 
	jmp 	SCLExit 		
	;
	;		Handle SHIFT+key
	;					
SCLShift:	
	cpy 	#$41 								; character >= A, it's alphabetic shift.
	bcs 	SCLAlphaShift
	dey 										; see keyboard-shift.py
	tya
	eor 	#$10
	adc 	#1 									; carry clear for compare
	bne 	SCLExit 
	;
SCLAlphaShift: 									; alphabetic shifts.
	tya
	eor 	#$20
	bne 	SCLExit
	;
	;		Handle CTRL+key
	;
SCLControl:
	tya 										; get character back
	and 	#$1F 								; force into control range.
	jmp 	SCLExit 							; and exit with that.
	;
	;		Check ESC pressed.
	;
SCLCheckEscape:
	and 	#$10								; isolate ESCape bit (already done LSR)
	beq 	SCLExit 							; if zero, return with $00 as no key pressed returning a character	
	lda 	#$1B 								; return the ESC code.
	bne 	SCLExit

; ********************************************************************************
;                                        
;                               System Entry Point
;                                        
; ********************************************************************************

SystemReset:
	cld  										; reset decimal mode snd stacks
	ldx  	#$28
	txs  
	jsr  	ResetACIA 							; reset ACIA
	jsr  	ResetVectorDataArea 				; reset vectors
	jsr  	ClearScreen 						; clear screen

PrintPrompt: 									; print boot message.
	lda  	BootText,Y
	jsr  	OutputCharacter
	iny  
	cpy  	#BootTextEnd-BootText
	bne  	PrintPrompt

	jsr  	InputCharacter 						; get a character
	and  	#$DF 								; capitalise it.
	cmp  	#'M'								; M monitors
	bne  	NotMKey
	jmp  	MonitorColdStart

NotMKey:
	cmp  	#'W' 								; W Warm starts vectors
	bne  	NotWKey
	jmp  	BASIC_WarmStart

NotWKey:
	cmp  	#'C' 								; if not C, go round again.
	bne  	SystemReset
	jmp  	BASIC_ColdStart						; cold start BASIC

; ********************************************************************************
;
;									Boot Text.
;
; ********************************************************************************

BootText:
	.text 'OS/600 (c) PSR 2019',13,10,10,'C,W,M ?'
BootTextEnd:	

; ********************************************************************************
;
;                                 keyboard matrix
;
; ********************************************************************************

KeyboardCharTable:
	.byte '7','6','5','4','3','2','1'			; row $80
	.byte $00,$5f,'-',':','0','9','8'			; row $40
	.byte $00,$00,$0d,$0a,'O','L','.' 			; row $20
	.byte 'I','U','Y','T','R','E','W'			; row $10
	.byte 'K','J','H','G','F','D','S'			; row $08
	.byte ',','M','N','B','V','C','X'			; row $04
	.byte 'P',59,'/',' ','Z','A','Q'			; row $02, bits $02-$80

; ********************************************************************************
;                                        
;                              Output to ACIA/Screen
;                                        
; ********************************************************************************

VectoredOutput:
	jsr  	NewScreenHandler 					; write to screen.
ContinueOutput:
	pha  
	lda  	ACIASaveFlag 						; check flag
	beq  	RestoreAExit                     	; if zero, pop A and exit
	pla  										; get character back
	jsr  	WriteACIA     		               	; write to acia
	cmp  	#13
	bne  	Exit1                               ; not cr, exit now, else do 10 NULLs.

; ********************************************************************************
;                                        
;                             Output 10 NULLs to ACIA
;                                        
; ********************************************************************************

TenNulls:
	pha  										; save A & X
	txa  
	pha  
	ldx  	#10 								; write this many NULLS
	lda  	#0
NullLoop:
	jsr  	WriteACIA 							; write loop
	dex  
	bne  	NullLoop
	pla   										; restore and exit
	tax  
RestoreAExit:
	pla  
Exit1:
	rts  

; ********************************************************************************
;                                        
;                 clear screen (returns X = 0,Y = 0) and home cursor
;                                        
; ********************************************************************************

ClearScreen:
	ldy  	#0 									; Reset the to address.
ClearLoop:
	lda  	#ScreenFiller
	sta  	ScreenMemory,Y 						; do one page
	sta 	ScreenMemory+$100,y
	sta 	ScreenMemory+$200,y
	sta 	ScreenMemory+$300,y
	sta 	ScreenMemory+$400,y
	sta 	ScreenMemory+$500,y
	sta 	ScreenMemory+$600,y
	sta 	ScreenMemory+$700,y
	iny  
	bne  	ClearLoop

; ********************************************************************************
;
;								Home the Cursor
;
; ********************************************************************************

HomeCursor:
	ldx 	#0
	stx 	CursorX 							; save cursor position back to 0,0.
	stx 	CursorY 

; ********************************************************************************
;
;			Recalculate to/from cursor address (not-zero set on exit)
;
; ********************************************************************************

RecalculateCursorAddress:
	lda 	CursorY 							; Y => Cursor Position.
	sta 	CharPosition
	lda 	#0
	sta 	CharPosition+1
	ldx 	#LineShift
_RCABaseAddress: 								; calculate the start of the line
	asl 	CharPosition 						; in the cursor position.
	rol 	CharPosition+1 						; - not allowing for the offset.
	dex
	bne 	_RCABaseAddress 					; have cleared the carry with the ROL
	;
	lda 	CursorX 							; Get Cursor position.
	adc 	#FirstVisible 						; add first visible. Requires this to be <256
	adc 	CharPosition 						; add into the character position
	sta 	CharPosition 						; save in both.
	sta 	CharSrcPosition
	lda 	CharPosition+1 						; update the char position + 1 likewise.
	adc 	#ScreenMemory/256
	sta 	CharPosition+1
	sta 	CharSrcPosition+1
	rts

; ********************************************************************************
;
;								Reset vectors, data etc.
;
; ********************************************************************************

ResetVectorDataArea:
	ldy  	#DefaultSettingsEnd-DefaultSettings ; init 218-234
RVDALoop:
	lda  	DefaultSettings,Y
	sta  	VectorArea,Y
	dey  
	bpl  	RVDALoop
	ldy  	#7                                  ; zero 200-206, 212
	lda  	#0
	sta  	BreakDisabled                       ; enable ctrl-c flag
RVDALoop2:
	sta  	CursorX-1,Y
	dey  
	bne  	RVDALoop2
	rts  

DefaultSettings:
	.word 	VectoredInput                    	; 218 input
	.word 	VectoredOutput                      ; 21a output
	.word 	ControlCCheck                       ; 21c ctrl-c
	.word 	VectorSetLoad                       ; 21e load
	.word 	VectorSetSave                       ; 220 save

	.byte 	ColumnsVisible-1                    ; 222 length of line - 1
	lda  	$1111,X                  			; 223 code to copy to from/screen, stops flash?
	sta  	$2222,X      			            ; 226
	rts  		                                ; 229
DefaultSettingsEnd:

; ********************************************************************************
;                                        
;                              set load / clear save
;                                        
; ********************************************************************************

VectorSetLoad:
	pha  
	dec  	ACIALoadFlag   	                    ; set load flag to $FF
	lda  	#0              	                ; clr save flag
WriteACIASaveFlag:
	sta  	ACIASaveFlag
	pla  
	rts  

; ********************************************************************************
;                                        
;                                  set save flag
;                                        
; ********************************************************************************

VectorSetSave:
	pha  
	lda  	#1                                  ; set save flag
	bne 	WriteACIASaveFlag

	* = $FFE0

; ********************************************************************************
;
;								information table
;
; ********************************************************************************

	.byte 	ScreenBottom & 255
	.byte 	ColumnsVisible-1             
	.byte 	ScreenMemorySize  / $400

; ********************************************************************************
;
;								Monitor Vectors
;
; ********************************************************************************

	.word 	FixedBasicReadScreenLine 			; address only, nothing else fits.

InputLine: 										; return address of a line ending in $60
	jmp 	ReadScreenLine
ScanKeyboardRoutine:							
	jmp 	ScanKeyboardRoutine 				; check which key is pressed if any
InputCharacter:
	jmp  	($218)                             	; input routine
OutputCharacter:
	jmp  	($21A)                          	; output routine
CheckControlC:
	jmp  	($21C)                              ; ctrl-c routine
SetLoadMode:
	jmp  	($21E)                              ; load set up routine
SetSaveMode:
	jmp  	($220)                              ; save set up routine

; ********************************************************************************
;
;									6502 Vectors
;
; ********************************************************************************

	.word 	NMIHandler                       	; nmi ($FFFA)
	.word 	SystemReset                         ; reset ($FFFC)
	.word 	IRQHandler                          ; irq ($FFFE)

	.end 
