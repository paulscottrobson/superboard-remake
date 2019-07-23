;               this compiles under the portable 64tass assembler.

;        note: the original text indicated that the fcxx segment should be
;      relocated to $f700 for c2/4.  to simplify the address circuitry, the
;      rom is wired to $f000-$ffff, with a11 ignored, and the chip disabled
;      when $fc00 (acia) is enabled.  this scheme maps the $fcxx segment to
;       $f400 in hardware, so the offset is calculated as $fcxx-$f4xx.  if
;        you follow the original cegmon wiring instructions (i don't have
;               these), then change the offest back to $fc00-$f700.

;     editor commands: (modified from original to be slightly more emacs-like
;                                        
;                               ctl-e editor on/off
;                                   ctl-b back
;                                  ctl-f forward
;                              ctl-p prev. line (up)
;                             ctl-n next line (down)
;                   ctl-y yank (copy character to input buffer)

;       this file is merged for c1/c2/600.  scan for the strings c1/c2, and
;        uncomment the appropriate line.  todo: once i find a decent linux
;            assembler supporting conditionals, convert to conditional


BasicROM =  $A000   ; basic rom
DiskController = $C000   ; diskcontroller controller (pia = +$00, acia = +$10)
Screen =   $D000   ; screen ram
Keyboard =   $DF00   ; keyboard port

;                                     ; c1/c2
;               Acia = $fc00 ; serial port (mc6850 acia) for c2/c4
;
acia = $f000 ; serial port (mc6850 acia) for c1/superboard/uk101

;                                      c1/c2
;          offset = $fc00-$f400 ; $fc00-fcff rom mapped to $f400 (c2/c4)
;
Offset = $0  ; no offset needed for c1/sb

;                      nmi  irq  width size start cols rows
;                       c2/4  $130 $1c0 64  1  128  64  28
;                      c1p/sbii $130 $1c0 32  0  69  24  26
;                       uk101  $130 $1c0 64  0  140  48  14

BASIC_WarmStart = $0000						; BASIC routines.
BASIC_ColdStart = $BD11
BASIC_ControlC = $A636
BASIC_OldScreenHandler = $BF2D

UK101_RubOut1 = $A374
UK101_RubOut2 = $A34B


NMIHandler = $130  							; nmi address
IRQHandler = $1C0  							; irq address

CharsSinceCR = $E 							; chars printed since CR

BrkA = $E0 									; register storage in breaj.
BrkX = $E1
BrkY = $E2
BrkP = $E3
BrkS = $E4
BrkPCL = $E5
BrkPCH = $E6

CopyTarget = $E4 							; copy target address
OldOpcode = $E7   							; opcode replaced when BrK set
ToAddress = $F9   							; "To" address
InputFromSerial = $FB 						; if non-zero input from ACIA
CurrentData = $FC   						; Store for current data
FDDBootstrap = $FD 							; word used to run bootstrapped FDD
FromAddress = $FE   						; "From" address

CursorX = $200    							; cursor displacement current char.
OldCharacter = $201  						; current character during SCREEN
NewChar = $202    							; new character
ACIALoadFlag = $203  						; $00 off, $ff acia load
EditFlag = $204   							; $00 no edit cursor, $ff edit cursor
ACIASaveFlag = $205  						; $00 off, $ff save to acia
ScreenDelay = $206   						; screen delay (400 cycles/count)
BreakDisabled = $212  						; non-zero if break disabled.
CurrentKeyIndex = $213 						; key index pressed
AutoRepeatCount = $214  					; auto repeat count.
FinalKey = $215   							; final value of key (ascii)
LastChar = $216   							; pre shift lst char for repeat.

LastCharOnLine = $222  						; index of last character on line.
FirstScreenChar = $223 						; first character visible
LastScreenChar = $225 						; last character visible
ScrollCopier = $227 						; RAM based scroll copier.
CharSrcPos = $228	
ProcessFromTopAndDexEdit = $22A 			; do something abs,x ; dex ; rts
CharPosition = $22B
EditCursorDisp = $22F  						; edit cursor displacement
EditCursorChar = $230  						; character under edit cursor
EditCursorLine = $231  						; Edit cursors line on screen
UserRoutine = $233   						; Users machine code routine.

;                        screen parameters for superboard

LineWidth = 32  							; screen width
ScreenSize = 0  							; screen size 0=1k 1=2k

FirstVisible = 133 							; set screen offset
ColumnsVisible = 24 						; set columns to display
RowsVisible = 24  							; set rows to display

LineLengthMinus1 = ColumnsVisible-1 		; index of last character

ScreenVisibleTop = Screen+FirstVisible 		; positions within screen.
ScreenVisibleBottom = (RowsVisible-1)*LineWidth+ScreenVisibleTop
ScreenMemoryEnd =  (ScreenSize+1)*1024+Screen

 	*= $F800

;                                     rubout

RuboutCode:
	lda  CharsSinceCR 							; adjust chars since CR
	beq  DoRubout
	dec  CharsSinceCR
	beq  DoRubout
	dec  CharsSinceCR
DoRubout:
	lda  #' ' 									; overwrite cursor
	sta  OldCharacter
	jsr  PrintCharacterAtCurrent
	bpl  NotPrevLine 							
	sec  										; go up one line
	lda  CharPosition
	sbc  #LineWidth                           
	sta  CharPosition
	lda  CharPosition+1
	sbc  #0
	sta  CharPosition+1
	jsr  CheckScreenBottomXLast 				; check off, home cursor if so.
	bcs  NotPrevLine
	jsr  HomeCursor
NotPrevLine:
	stx  CursorX
	jsr  PrintCursor
	jmp  NewScreenHandlerExit

; ********************************************************************************
;                                        
;                               new screen handler
;                                        
; ********************************************************************************

NewScreenHandler:
	sta  NewChar 								; save character
	pha   										; save AXY
	txa   										
	pha  
	tya  
	pha  
	lda  NewChar 								; get character
	bne  NotNull                                ; exit immediately if NULL
	jmp  NewScreenHandlerExit

NotNull:
	ldy  ScreenDelay                            ; screen delay ?
	beq  NoDelay 
	jsr  Delay2-Offset 							; if so, call the routine.

NoDelay:
	cmp  #$5F 									; _ is the rubout character
	beq  RuboutCode
	cmp  #$C 									; check for Ctrl-L
	bne  NotCtrlL
;
;                                     ctrl-l
;
	jsr  PrintOldCharacterAtCurrent 			; restore char under cursor and home it.
	jsr  HomeCursor
	stx  CursorX
	beq  NSHRawPrint 							; raw print something ? why ?

NotCtrlL:
	cmp  #$A 									; line feed
	beq  NSHLineFeed
	cmp  #$1E 									; Ctrl-Shift-N
	beq  ControlShiftNHandler
	cmp  #$B
	beq  NSHOverwriteCursor
	cmp  #$1A									; Ctrl-Z
	beq  ControlZHandler
	cmp  #$D 									; carriage return.
	bne  NSHNotCarriageReturn
;
;                                       cr
;
	jsr  PrintRawOldCharacter 					; print the old character
	bne  NewScreenHandlerExit 					; and exit.
NSHNotCarriageReturn:
	sta  OldCharacter 							; save character so we write that one out.
;
; 				write old character over cursor and print if no eol
;
NSHOverwriteCursor:
	jsr  PrintOldCharacterAtCurrent 			; remove cursor with old character
	inc  CursorX 								; increment position.
	inx  
	cpx  LastCharOnLine 						; reached the end.
	bmi  NSHRawPrint 							; if not, do normal.
	jsr  PrintRawStartOfLineA 					; otherwise print at start of next line.
;
;                                       lf
;
NSHLineFeed:
	jsr  PrintOldCharacterAtCurrent 			; restore cursor
	ldy  #2 									
	jsr  CheckScreenBottom 						; check off the bottom
	bcs  NSHScrollUp
	ldx  #3 									; go down one line.
	jsr  DownOneLine
	jmp  NSHRawPrint

NSHScrollUp:
	jsr  MoveUp 								; move edit cursor up to start of last line
	jsr  HomeCursor 							; reset all
	jsr  DownOneLine 							; down one line.
	ldx  LastCharOnLine							; start scrolling
ScrollCopyLoop:
	jsr  ScrollCopier 							; copy one line.
	bpl  ScrollCopyLoop
	inx   										; advance pointers
	jsr  DownOneLine
	ldx  #3
	jsr  DownOneLine
	jsr  CheckScreenBottomXLast 				; reached the bottom.
	bcc  ScrollCopyLoop
	lda  #' '									; blank the bottom line.
ScrollEraseLastLine:
	jsr  ProcessFromTopAndDexEdit
	bpl  ScrollEraseLastLine
	ldx  #1 									; clear first character.
ClearStart:
	lda  FirstScreenChar,X
	sta  CharSrcPos,X
	dex  
	bpl  ClearStart
NSHRawPrint:
	jsr  PrintRawCurrentA 						; print it whatever.
NewScreenHandlerExit:
	pla  
	tay  
	pla  
	tax  
	pla  
	rts  
;
;                                     ctrl-z
;
ControlZHandler:
	jsr  ClearScreen
	sta  OldCharacter
	beq  HomeAndExit
;
;                                  ctrl-shift-n
;
ControlShiftNHandler:
	lda  #' '									; erase and home cursor
	jsr  PrintCharacterAtCurrent
	jsr  HomeCursor
ClearEOS:
	ldx  LastCharOnLine 						; clear to start of line.
	lda  #' '
ClearStartOfLine:
	jsr  ProcessFromTopAndDexEdit
	bpl  ClearStartOfLine
	sta  OldCharacter
	ldy  #2 									; go down one line if you can.
	jsr  CheckScreenBottom
	bcs  HomeAndExit
	ldx  #3 	
	jsr  DownOneLine
	jmp  ClearEOS 								; and clear that too.

HomeAndExit:
	jsr  HomeCursor
	stx  CursorX
	beq  NewScreenHandlerExit
;
;							code for monitor tab display
;
MONTabDisplay:
	jsr  Collect2Addr 							; collect start/end
MONTabMain:
	jsr  PrintCRLF 								; print out addr etc.
	jsr  PrintAddr
	jsr  PrintSpace
	jsr  PrintGreater
	ldx  #$10                                   ; # bytes displayed
	stx  CurrentData+1
MONTabByte:
	jsr  PrintSpace							 	; display one byte
	jsr  PrintByteAtFE
	jsr  CheckEnd 								; done the whole tab as required
	bcs  MONResetSAndCmd
	jsr  BumpAddress
	dec  CurrentData+1 							; do row of 16
	bne  MONTabByte
	beq  MONTabMain
;
;                                 'm' move memory
;
MONCopyBlock:
	jsr  Collect3Addr
	jsr  CopyBlock
	bcs  MonitorCmdAddrMode
;
;                           'r' restart from breakpoint
;
MONContinueAfterBreak:
	ldx  CopyTarget 							; put stack position in S
	txs  
	lda  BrkPCH 									; PC
	pha  
	lda  BrkPCL 									
	pha  
	lda  BrkP 									; P
	pha  
	lda  BrkA 									; load AXY
	ldx  BrkX
	ldy  BrkY
	rti   										; and do an RTI to load the P PC in.
;
;                               'z' set breakpoint
;
MONSetBreakpoint:
	ldx  #3 									; overwrite the vectors
MONSetVectorLoop:
	lda  MONInterruptBreakVector-1,X
	sta  IRQHandler-1,X
	dex  
	bne  MONSetVectorLoop
	jsr  GetNew 								; get one address
	jsr  Collect1Addr
	lda  (FromAddress),Y 						; get what was there
	sta  OldOpcode 								; and save it.
	tya   
	sta  (FromAddress),Y 						; put a $00 there.
	beq  MonitorCmdAddrMode
;
;                                    's' save
;
MONSaveMachineCode:
	jmp  SaveMachineCode
;
;                                    'l' load
;
MONLoadMachineCode:
	dec  InputFromSerial
	bne  MONEnterDataMode
;
;                               't' tabular display (check)
;
MONCheckTab2:
	beq  MONTabDisplay
Exit3:
	rts  
;
;								Errors come here
;
MONError:
	lda  InputFromSerial
	bne  Exit3
	lda  #'?'
	jsr  OutputCharacter

MONResetSAndCmd: 								; reset stack.
	ldx  #$28
	txs  
MonitorCmdAddrMode:
	jsr  PrintCRLF 								; CR and use keyboard
	ldy  #0
	sty  InputFromSerial

	jsr  PrintGreater 							; prompt

;                            '.' command/address mode

MONGetCommand:
	jsr  GetNew 								; get and dispatch command accordingly.
	cmp  #'M'
	beq  MONCopyBlock
	cmp  #'R'
	beq  MONContinueAfterBreak
	cmp  #'Z'
	beq  MONSetBreakpoint
	cmp  #'S'
	beq  MONSaveMachineCode
	cmp  #'L'
	beq  MONLoadMachineCode
	cmp  #'U'
	bne  MONCheckTab
	jmp  (UserRoutine)

; ********************************************************************************
;                                        
;                          Collect two addresses (FE,F9)
;                                        
; ********************************************************************************

Collect2Addr:
	jsr  GetNew
	jsr  Collect1Addr
	jsr  PrintComma
	ldx  #0
CollectExtraAddress:
	jsr  GetNew
	.byte $2C

; ********************************************************************************
;                                        
;                          Collect address , store in FE
;                                        
; ********************************************************************************

Collect1Addr:
	ldx  #5 									; get offset 5
	jsr  GetOffset
	jsr  GetNew 								; get next
	.byte $2C

; ********************************************************************************
;                                        
;           Collect pair for data byte, store in FC (call GetNew first)
;                                        
; ********************************************************************************

GetPrc:
	ldx  #3 									; get into FC
GetOffset:
	jsr  InputRoll1 							; roll 1 nibble in
	jsr  GetNew 								; get character
InputRoll1:										; roll next in
	cmp  #'.'									; handle / and .
	beq  MONGetCommand
	cmp  #'/'
	beq  MONEnterDataMode
	jsr  ASCIIToBinary							; binary ?
	bmi  MONError 
	jmp  RollNibbleToWord 						; if okay roll it in.
;
;										Check if T
;
MONCheckTab:
	cmp  #'T'
	beq  MONCheckTab2
;
;								Otherwise collect 1 address
;	
	jsr  Collect1Addr
;
;									display current byte
;
MONDataMain:
	lda  #'/'
	jsr  OutputCharacter
	jsr  PrintByteAtFE
	jsr  PrintSpace
;                                  '/' data mode

MONEnterDataMode:
	jsr  GetNew 								; get character
	cmp  #'G' 									; G is run from here.
	bne  MONNotRun
	jmp  (FromAddress)
	;
	;								Not G, check for ,
	;
MONNotRun:
	cmp  #','
	bne  MONNotComma
	jsr  BumpAddress 							; slip over this byte.
	jmp  MONEnterDataMode

MONNotComma:
	cmp  #$A 									; handle CR/LF Bump address
	beq  MONDataAfterLF
	cmp  #$D
	beq  MONDataAfterCR
	cmp  #'^' 									; move backwards.
	beq  MONBackwards 
	cmp  #$27 									; enter text.
	beq  MONEnterText
	jsr  GetPrc 								; get byte
	lda  CurrentData 							; write it out
	sta  (FromAddress),Y
MONGotoDataMode:
	jmp  MONEnterDataMode

MONDataAfterLF: 								; CR/LF new line with bump 
	lda  #$D
	jsr  OutputCharacter
MONDataAfterCR:
	jsr  BumpAddress
	jmp  MONPrintAndDataLoop
;
;                                       '^'
;
MONBackwards:
	sec   										; go backwards !
	lda  FromAddress
	sbc  #1
	sta  FromAddress
	lda  FromAddress+1
	sbc  #0
	sta  FromAddress+1
MonitorDataModeLoop: 							; new line and address
	jsr  PrintCRLF
MONPrintAndDataLoop:
	jsr  PrintAddr
	jmp  MONDataMain

MONNextChar:
	jsr  WriteAndBumpAddress

;                                       "'"

MONEnterText:
	jsr  GetNew 								; get char
	cmp  #$27 									; done ?
	bne  MONOkChar
	jsr  PrintComma 							; if so, print comma and back to data mode
	bne  MONGotoDataMode
MONOkChar:
	cmp  #$D 									; CR exits too.
	beq  MonitorDataModeLoop
	bne  MONNextChar
;
;							branch for interrupt/break vector
;
MONInterruptBreakVector:
	jmp  MONInterruptBreak
;
;							handle interrupts.
;
MONInterruptBreak:
	sta  BrkA 									; save A
	pla   										; restore/save P
	pha  
	and  #$10 									; is it a break
	bne  MONInterruptBreakSave 
	lda  BrkA	 								; if not restore and return.
	rti  

;                             save registers on break

MONInterruptBreakSave:
	stx  BrkX 									; save XY (A alredy done)
	sty  BrkY
	pla  
	sta  BrkP 									; save P
	cld  
	sec  										; save PC
	pla  
	sbc  #2
	sta  CopyTarget+1
	pla  
	sbc  #0
	sta  BrkPCH
	tsx  
	stx  CopyTarget                      		; save S
	ldy  #0 									; put breakpoint opcode back
	lda  OldOpcode
	sta  (CopyTarget+1),Y 						; +1 because of RTS thing.
	lda  #BrkA 									; and go round again.
	sta  FromAddress
	sty  $FF
	bne  MonitorDataModeLoop
;
;										Save machine code
;
SaveMachineCode:
	jsr  Collect3Addr 							; get 3 addresses first, last, restart
	jsr  SetSaveMode 							; save
	jsr  GetCharKbdAcia							; wait for return.
	jsr  OutputCharacter
	jsr  PrintCurrentAddr						; print start
	lda  #'/' 									; data mode.
	jsr  OutputCharacter
	bne  SAVOutput

SAVOutBytes:
	jsr  BumpAddress
SAVOutput:
	jsr  PrintByteAtFE 							; output byte anD CR to advance
	lda  #$D
	jsr  WriteACIA-Offset
	jsr  CheckEnd
	bcc  SAVOutBytes 							; keep going until finished.

	lda  CopyTarget 							; copy exec address
	ldx  CopyTarget+1
	sta  FromAddress
	stx  FromAddress+1
	jsr  PrintCurrentAddr 						; write that out
	lda  #'G' 									; G to execute it
	jsr  OutputCharacter 						; NULLs to ACIA
	jsr  TenNulls 
	sty  ACIASaveFlag 							; keyboard mode.
	jmp  MonitorCmdAddrMode

; ********************************************************************************
;                                        
;                               Screen Editor Entry
;                                        
; ********************************************************************************

ScreenEditorEntry:
	txa  										; save X & Y
	pha  
	tya  
	pha  
	lda  EditFlag								; are we in edit mode.
	bpl  StandardHandler
ScreenEditMode:
	ldy  EditCursorDisp 						; position in line.
	lda  EditCursorLine 						; copy current line to E4/E5
	sta  CopyTarget
	lda  EditCursorLine+1
	sta  CopyTarget+1
	lda  (CopyTarget),Y 						; read character on that line
	sta  EditCursorChar 						; save as the character there.
	lda  #$A1 									; write out solid block cursor character
	sta  (CopyTarget),Y
	jsr  ReadKeyboard 							; read the keyboard
	lda  EditCursorChar 						; put the character back.
	sta  (CopyTarget),Y
	;
	lda  FinalKey 								; get the keystroke.
 	cmp  #$11  									; ctl-q =copy character to buffer
	beq  SECopyCharacter
 	cmp  #2  									; ctl-b = backward
	beq  SEBackward
 	cmp  #$6  									; ctl-f = forward
	beq  SEForward
 	cmp  #$10  									; ctl-p = previous
	beq  SEPreviousLine
	cmp  #$E                                    ; ctl-n (next line)
	bne  StandardProcessor
;
;                               ctrl-n (next line)
;
	jsr  MoveDown
	jmp  ScreenEditMode
;
;                               ctrl-p (prev line)
;
SEPreviousLine:
	jsr  MoveUp
	jmp  ScreenEditMode
;
;                                ctrl-f (forward)
;
SEForward:
	jsr  MoveRight
	jmp  ScreenEditMode
;
;                                ctrl-a (backward)
;
SEBackward:
	jsr  MoveLeft
	jmp  ScreenEditMode

;                             ctrl-q (copy character)

SECopyCharacter:
	lda  EditCursorChar 						; copy character at cursor to key pressed
	sta  FinalKey
	jsr  MoveRight 								; and move right.
	jmp  ExitKeyboardHandler 					; exit as if that is pressed.

StandardHandler:
	jsr  ReadKeyboard 							; read keyboard the usual way.

StandardProcessor:
	cmp  #5 									; Ctrl+E ?
	bne  ExitKeyboardHandler 					; no exit the keyboard handler
	lda  EditFlag								; toggle the edit flag.
	eor  #$FF
	sta  EditFlag
	bpl  StandardHandler 						; if zero, now on standard handler.
	lda  CharPosition 							; restore cursor position back ?
	sta  EditCursorLine
	lda  CharPosition+1
	sta  EditCursorLine+1
	ldx  #0
	stx  EditCursorDisp
	beq  ScreenEditMode
ExitKeyboardHandler:
	jmp  RKExitPopYX

; ********************************************************************************
;                                        
;                       Input Character from ACIA/Keyboard
;                                        
; ********************************************************************************

VectoredInput:
	bit  ACIALoadFlag 							; check coming fom ACIA
	bpl  EnterScreenEditor                      ; no, go to ScreenEditorEntry

CheckExitLoad:
	lda  #2 									; read row 2 
	jsr  WriteKeyboardRowA
	jsr  ReadKeyboardColA
	and  #$10 									; bit 4, if set space is pressed
	bne  ACIASpaceBreak                         ; space key pressed so interrupt

; ********************************************************************************
;                                        
;                                 input from acia
;                                        
; ********************************************************************************

ReadACIA:
	lda  Acia 									; read ACIA control
	lsr  A 										; check recieve data reg full (bit 0)
	bcc  CheckExitLoad 							; nope ; check space and go round again.
	lda  Acia+1 								; get character.
	rts  

ACIASpaceBreak: 								; space interrupts ACIA read
	lda  #0 									; reset two sources
	sta  InputFromSerial
	sta  ACIALoadFlag
EnterScreenEditor:								; and use the screen editor routine.
	jmp  ScreenEditorEntry

; ********************************************************************************
;
;										Move right
;
; ********************************************************************************

MoveRight:
	ldx  LastCharOnLine 						; reached end of line ?
	cpx  EditCursorDisp
	beq  NextLineDown 							; yes, next line down.
	inc  EditCursorDisp 						; no, one right.
	rts  

NextLineDown:
	ldx  #0 									; start of next line.
	stx  EditCursorDisp
MoveDown:
	clc   										; advance current line to next down
	lda  EditCursorLine
	adc  #LineWidth                             
	sta  EditCursorLine
	lda  EditCursorLine+1
	adc  #0
	cmp  #>ScreenMemoryEnd                      ; wrap round
	bne  DontWrap
	lda  #>Screen
DontWrap:
	sta  EditCursorLine+1
Exit2:
	rts  

; ********************************************************************************
;                                        
;                                  ctrl-c check
;                                        
; ********************************************************************************

ControlCCheck:
	lda  BreakDisabled
	bne  Exit2                                  ; disable flag set
	lda  #1
	jsr  WriteKeyboardRowA
	bit  Keyboard
	bvs  Exit2                                  ; bvc for non-invert keyboard
	lda  #4
	jsr  WriteKeyboardRowA
	bit  Keyboard
	bvs  Exit2                                  ; bvc for non-invert keyboard
	lda  #3                                     ; ctrl-c pressed
	jmp  BASIC_ControlC							; this is a BASIC routine.



DefaultSettings:
	.word VectoredInput                         ; 218 input
	.word VectoredOutput                        ; 21a output
	.word ControlCCheck                         ; 21c ctrl-c
	.word VectorSetLoad                         ; 21e load
	.word VectorSetSave                         ; 220 save

	.byte LineLengthMinus1                      ; 222 length of line - 1
	.word ScreenVisibleTop                      ; 223 top of screen
	.word ScreenVisibleBottom                   ; 225 bottom of screen
	lda  ScreenVisibleTop,X                     ; 227 code to copy to from/screen, stops flash?
	sta  ScreenVisibleTop,X                     ; 22a
	dex  ; 22                                   ; 22d
	rts  ; 22                                   ; 22e
	.byte $00                                   ; 22f
	.byte $20                                   ; 230
	.word ScreenVisibleTop                      ; 231
	.word MONGetCommand                                 ; 233

; ********************************************************************************
;                                        
;                           Check off bottom of screen
;                                        
; ********************************************************************************

CheckScreenBottomXLast:
	ldx  LastCharOnLine
CheckScreenBottom:
	sec  
	lda  CharPosition
	sbc  FirstScreenChar,Y
	lda  CharPosition+1
	sbc  FirstScreenChar+1,Y
	rts  

; ********************************************************************************
;                                        
;                            Print various characters
;                                        
; ********************************************************************************

PrintGreater:
	lda  #'>'
	.byte $2C 									; the skip trick, again.
PrintComma:
	lda  #','
	.byte $2C
PrintSpace:
	lda  #' '
	jmp  OutputCharacter

; ********************************************************************************
;                                        
;                                Check Reached End
;                                        
; ********************************************************************************

CheckEnd:
	sec   										; returns CS if from >= to
	lda  FromAddress
	sbc  ToAddress
	lda  FromAddress+1
	sbc  ToAddress+1
	rts  

; ********************************************************************************
;                                        
;                                   Print CRLF
;                                        
; ********************************************************************************


PrintCRLF:
	lda  #13 									; print CR
	jsr  OutputCharacter
	lda  #10 									; print LF
	jmp  OutputCharacter

	.byte $40

; ********************************************************************************
;                                        
;                                  Bootstrap FDC
;                                        
; ********************************************************************************
;
;	$C000	
;		0:Drive0 ready, 1:Track0 2:Fault 4:Drive1 ready 5:Write protect
;		6:Drive Select, 7:Index
;
;	$C002
;		0:No write, 1:No Erase,2:Step to 0/76 3:-ve pulse indicates step
;		4:Fault Reset (0), 5: Side Select, 6:Low current (0 for 43-76,1 otherwise)
;		7:Head Load.


BootstrapDisk:
	jsr  BootstrapFDD-Offset 					; call the bootstrap code
	jmp  (FDDBootstrap) 						; and do whatever.

	jsr  BootstrapFDD-Offset 					; unused code doing it from monitor ?
	jmp  MonitorColdStart

BootstrapFDD:
	ldy  #0										; zero PIA ; think disable pull ups.
	sty  DiskController+1
	sty  DiskController
	ldx  #4
	stx  DiskController+1 						; pull up on fault ?
	sty  DiskController+3 						; make control register all output.
	dey  
	sty  DiskController+2 						; set all bits to 1 on the control register
	stx  DiskController+3						; all outs ?
	sty  DiskController+2 						; all bits to 1 ?
	lda  #$FB 									; Head, bit 2 clear, pushing to track 0.
	bne  FDDProcessCommand

FDDDriveForward:
	lda  #2 									; at track 0 ?
	bit  DiskController
	beq  FDDTrack0
	lda  #$FF
FDDProcessCommand:
	sta  DiskController+2
	jsr  FDDExit-Offset
	and  #$F7 									; Enable write, erase, step to 76
	sta  DiskController+2
	jsr  FDDExit-Offset
	ora  #8 									; 0-1 transition starts stepping ?
	sta  DiskController+2 						; bit inverted.
	ldx  #$18 									; waut for it...
	jsr  FDDDriveDelay-Offset
	beq  FDDDriveForward 						; always called.
;
;	At track 0.
;	
FDDTrack0:
	ldx  #$7F 									; head load.
	stx  DiskController+2
	jsr  FDDDriveDelay-Offset 					; wait for head to load.
FDDWaitIndex:
	lda  DiskController 						; wait until at the index
	bmi  FDDWaitIndex
FDDWaitNotIndex:
	lda  DiskController 						; now wait until off index.
	bpl  FDDWaitNotIndex
	lda  #3										; set ACIA master reset
	sta  DiskController+$10
	lda  #$58									; RTS high, no interrupt, 8E1 and no divider.
	sta  DiskController+$10

	jsr  FDDReadCharacter-Offset				; read bootstrap.
	sta  FDDBootstrap+1							
	tax  
	jsr  FDDReadCharacter-Offset 			
	sta  FDDBootstrap
	jsr  FDDReadCharacter-Offset 				; read count of 1/4k pages
	sta  FDDBootstrap+2

	ldy  #0 									; now read in the index track.
FDDReadBootstrap:
	jsr  FDDReadCharacter-Offset 				; read character
	sta  (FDDBootstrap),Y 						; store at bootstrap
	iny  
	bne  FDDReadBootstrap 						; read in 1/4k page.
	inc  FDDBootstrap+1 						; next page
	dec  FDDBootstrap+2 						; done all of them.
	bne  FDDReadBootstrap
	stx  FromAddress 							; reset page
	lda  #$FF 									; sleep controller.
	sta  DiskController+2
	rts  
;
;							Delay.
;
FDDDriveDelay:
	ldy  #$F8 									; short delay to allow read in 
FDDIMWait:
	dey  
	bne  FDDIMWait
	eor  $FF,X 									; just padding.
	dex  
	bne  FDDDriveDelay 							; do for the lot.
	rts  
;
;                         input char from diskcontroller
;
FDDReadCharacter:
	lda  DiskController+$10 					; ACIA at $10, so wait for data available
	lsr  A
	bcc  FDDReadCharacter
	lda  DiskController+$11 					; then read it.
FDDExit:
	rts  

; ********************************************************************************
;                                        
;                                    init acia
;                                        
; ********************************************************************************

ResetACIA:
	lda  #3                                     ; reset acia
	sta  Acia
;
;   (c1/c2) c2 initializes with $b1, the c1 initializes with $11.
; 	i would think that this is generally of no consequence, since the acia's irq is not
; 	connected to the irq line by default.
;
	lda  #$B1                                   ; /16, 8bits, 2stop, rts low, irq on recv.
;
;   lda #$11 ; /16, 8bits, 2stop, rts low
;
	sta  Acia
	rts  

; ********************************************************************************
;                                        
;                               output char to acia
;                                        
; ********************************************************************************

WriteACIA:
	pha   										; save to write.
WaitTDRE:
	lda  Acia 									; get bit 1, which is transmit data empty
	lsr  A
	lsr  A
	bcc  WaitTDRE
	pla   										; restore and write the byte to send.
	sta  Acia+1
	rts  

; ********************************************************************************
;                                        
;                   set keyboard row (a)  1=r0, 2=r1, 4=r2 etc
;                                        
; ********************************************************************************

WriteKeyboardRowA:
	eor  #$FF 									; C1 upwards are non inverted
	sta  Keyboard
	eor  #$FF
	rts  

; ********************************************************************************
;                                        
;                 read keyboard col (x) 1=c0, 2=c1, 4=c2, 0=none
;                                        
; ********************************************************************************

ReadKeyboardColX:
	pha  										; save A
	jsr  ReadKeyboardColA-Offset 				; read keyboard into A
	tax   										; to X
	pla  										; restore A
	dex   										; set Z flag for new value
	inx  
	rts  

; ********************************************************************************
;                                        
;                 read keyboard col (A) 1=c0, 2=c1, 4=c2, 0=none
;                                        
; ********************************************************************************

ReadKeyboardColA:
	lda  Keyboard
	eor  #$FF 									; C1 upwards are non inverted.
	rts  


; ********************************************************************************
;
;                      uk101 basicrom rom rubout key handler
;
; ********************************************************************************

UK101Rubout:
	cmp  #$5F                                   ; rubout
	beq  GoUK101Rubout
	jmp  UK101_Rubout1

GoUK101Rubout:
	jmp  UK101_Rubout2

; ********************************************************************************
;                                        
;                                delay 6500 Cycles
;                                        
; ********************************************************************************

KDelay:											; specific delay
	ldy  #$10
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
;									Boot Text.
;
; ********************************************************************************

BootText:
	.text 'CEGMON(C)1980 D/C/W/M?'
BootTextEnd:	

; ********************************************************************************
;                                        
;                          polled keyboard input routine
;                                        
; ********************************************************************************

ReadKeyboard:
	txa   										; save X & Y on the stack.
	pha  
	tya  
	pha  
;
;	Start a new scan.
;
RKNewScan:										; start a new scan
	lda  #$80                                   ; on row 7
RKNextRow:
	jsr  WriteKeyboardRowA                      ; set row using the routines provided.
	jsr  ReadKeyboardColX                       ; read column, normalised to bit set on ress
	bne  RKKeyPressed                           ; key pressed, go handle it.

	lsr  a                                      ; next row, goes to zero when done all
	bne  RKNextRow 								; done all scans.
	beq  RKNoKeyPressed 						; nothing pressed this scan

RKKeyPressed:
	lsr  a 										; is it row $01 being tested (RPT/CTL/ESC etc.)
	bcc  RKNotRow1
	txa   										; get the column bits.
	and  #$20 									; this is C5, e.g. the ESC key
	beq  RKNoKeyPressed 				
	lda  #$1B 									; if pressed, return $1B (27) Escape
	bne  RKCheckKey 							; do the repeat checks.

RKNotRow1:
	jsr  BitToNumber 							; convert row >> 1 to number in Y.
	tya   										; save in FinalKey
	sta  FinalKey
	asl  A 										; *8
	asl  A
	asl  A
	sec   										; *7 (there is no entry for C0 in the table)
	sbc  FinalKey
	sta  FinalKey 								; so now (row-1)* 7 here.
	;
	txa  										; this is the read column value.
	lsr  A 										; clear bit 0 (shift lock)
	asl  A
	jsr  BitToNumber 							; convert that to a number, in Y
	beq  RKContinue 							; if shift is zero, only one key pressed.
	lda  #0 									; multiple keys, zero the last character
RKNoKeyPressed:
	sta  LastChar 								; clear the last character.
RKStartRepeat:
	sta  CurrentKeyIndex						; save as current key
	lda  #2 									; reset the repeat count to check debounce
	sta  AutoRepeatCount 	
	bne  RKNewScan 								; and try again

RKContinue:
	clc   										; add column to (row - 1) *7
	tya  
	adc  FinalKey
	tay   										; and use this to get the actual ASCII code.
	lda  KeyboardCharTable-1,Y

RKCheckKey:
	cmp  CurrentKeyIndex 						; same as current 
	bne  RKStartRepeat	 						; start auto repeat
	dec  AutoRepeatCount 						; check done enough repeats
	beq  RKRegisterPress 						; if so, then repeat it.
	jsr  KDelay-Offset 							; otherwise delay and rescan
	beq  RKNewScan

RKRegisterPress:
	ldx  #$64 									; 100 decimal
	cmp  LastChar 								; if same as last character
	bne  RKNotFirst
	ldx  #$F 									; if its a repeat, repeat much quicker next time.
RKNotFirst:
	stx  AutoRepeatCount 						; set the count and character.
	sta  LastChar
	cmp  #$21 									; if <= space 
	bmi  RKExit

	cmp  #$5F 									; or lower case and up exit now.
	beq  RKExit

	lda  #1 									; read row 1, the control keys row.
	jsr  WriteKeyboardRowA
	jsr  ReadKeyboardColA
	sta  FinalKey 								; save it.
	and  #1 									; shift lock bit to X.
	tax   
	lda  FinalKey 								; left shift/right shift 
	and  #6
	bne  RKShift 								; if non zero, then shift.
	bit  CurrentKeyIndex						; if < 64 then no effect ?
	bvc  RKDoModifier
	txa  										; get shift lock
	eor  #1 									; toggle it
	and  #1 									; mask it.
	beq  RKDoModifier					
	lda  #$20 									; to lower case modifier
	bit  FinalKey 								; if bit 5 is set.
	bvc  RKApplyModifier 						; apply that
	lda  #$C0 	 								; otherwise apply -64 modifier.
	bne  RKApplyModifier

RKShift:
	bit  CurrentKeyIndex 						; if < 64
	bvc  RKNormalShift
	txa   										; skip if shift lock not pressed.
	beq  RKDoModifier
RKNormalShift:
	ldy  CurrentKeyIndex  						; get current key
	cpy  #$31 									; outside range $31-$3C
	bcc  RKModifier16 							; apply +$10 modifier
	cpy  #$3C
	bcs  RKModifier16
	lda  #$F0 									; apply -$10
	bne  RKDoModifier

RKModifier16:									; +$10
	lda  #$10
RKDoModifier:
	bit  FinalKey 								; if >$40
	bvc  RKApplyModifier
	clc   										; preapply this/
	adc  #$C0
RKApplyModifier:
	clc   										; add to current key
	adc  CurrentKeyIndex
	and  #$7F 									; make 7 bit
	bit  FinalKey								; set bit 7 from original.
	bpl  RKExit
	ora  #$80
RKExit:
	sta  FinalKey								; save as key.
RKExitPopYX:
	pla  										; restore YX, load final key and exit
	tay  
	pla  
	tax  
	lda  FinalKey
	rts  


; ********************************************************************************
;                                        
;             Copy block of memory (FE) -> (E4), end address in (F9)
;                                        
; ********************************************************************************

CopyLoop:										; the copy loop
	jsr  BumpAddress
	inc  CopyTarget
	bne  CopyBlock
	inc  CopyTarget+1

;
;		enter here.
;

CopyBlock:
	lda  (FromAddress),Y
	sta  (CopyTarget),Y
	jsr  CheckEnd
	bcc  CopyLoop
	rts  
;
;							Go down one screen line on offset X
;
DownOneLine:
	clc  
	lda  #LineWidth                             
	adc  CharSrcPos,X
	sta  CharSrcPos,X
	lda  #0
	adc  CharSrcPos+1,X
	sta  CharSrcPos+1,X
	rts  

; ********************************************************************************
;                                        
;                               Monitor entry point
;                                        
; ********************************************************************************

MonitorColdStart:
	ldx  #$28 									; reset stack and flags
	txs  
	cld  
	jsr  ResetACIA-Offset 						; reset ACIA
	jsr  ResetVectorDataArea 					; reset Vectors
	nop  
	nop  

MonitorWarmStart:	     
	jsr  ClearScreen 							; clear screen
	sta  OldCharacter 							; no old character, from address
	sty  FromAddress 							; zero from address
	sty  FromAddress+1 	
	jmp  MonitorCmdAddrMode 					; go into command mode.

MoveLeft:
	ldx  EditCursorDisp 						; check if we can move left.
	beq  MoveUp2 								; no, end of previous line.
	dec  EditCursorDisp							; yes, left one.
	rts  

MoveUp2:
	ldx  LastCharOnLine 						; set offset in line.
	stx  EditCursorDisp
MoveUp:
	sec   										; go up one line
	lda  EditCursorLine
	sbc  #LineWidth                             
	sta  EditCursorLine
	lda  EditCursorLine+1
	sbc  #0
	cmp  #>Screen-1                             ; wrap around ?
	bne  NoUpWrap
	lda  #>ScreenMemoryEnd-1                    
NoUpWrap:
	sta  EditCursorLine+1
	rts  

; ********************************************************************************
;
;								Reset vectors, data etc.
;
; ********************************************************************************

ResetVectorDataArea:
	ldy  #$1C                                   ; init 218-234
RVDALoop:
	lda  DefaultSettings,Y
	sta  $218,Y
	dey  
	bpl  RVDALoop
	ldy  #7                                     ; zero 200-206, 212
	lda  #0
	sta  BreakDisabled                          ; enable ctrl-c flag
RVDALoop2:
	sta  CursorX-1,Y
	dey  
	bne  RVDALoop2
	rts  

; ********************************************************************************
;                                        
;                                  clear screen
;                                        
; ********************************************************************************

ClearScreen:
	ldy  #0 									; To is screen address
	sty  ToAddress
	lda  #>Screen
	sta  ToAddress+1
	ldx  #(ScreenSize+1)*4                      ; # of 256 byte pages.
	lda  #' '
ClearLoop:
	sta  (ToAddress),Y 							; do one page
	iny  
	bne  ClearLoop
	inc  ToAddress+1 							; bump address
	dex   										; do as often as needed.
	bne  ClearLoop
	rts  

; ********************************************************************************
;                                        
;                              set load / clear save
;                                        
; ********************************************************************************

VectorSetLoad:
	pha  
	dec  ACIALoadFlag                           ; set load flag to $FF
	lda  #0                                     ; clr save flag
WriteACIASaveFlag:
	sta  ACIASaveFlag
	pla  
	rts  

; ********************************************************************************
;                                        
;                                  set save flag
;                                        
; ********************************************************************************

VectorSetSave:
	pha  
	lda  #1                                     ; set save flag
	bne  WriteACIASaveFlag

; ********************************************************************************
;                                        
;                              input char from acia
;                                        
; ********************************************************************************

GetCharAcia:
	jsr  ReadACIA								; read character from ACIA
	and  #$7F                                   ; clear bit 7
	rts  

; ********************************************************************************
;
;		A is a bit, figure out which one, 7=$80 0=$01. Will fail if A = 0
;
; ********************************************************************************

BitToNumber:
	ldy  #8 									; if the first one sets C return 7
FindBitLoop:
	dey  
	asl  a
	bcc  FindBitLoop
	rts  

; ********************************************************************************
;                                        
;                        Get new char and echo to display
;                                        
; ********************************************************************************

GetNew:
	jsr  GetCharKbdAcia 						; get from source and echo.
	jmp  OutputCharacter

; ********************************************************************************
;                                        
;                        convert ascii-hex char to binary
;                                        
; ********************************************************************************

ASCIIToBinary:
	cmp  #'0' 									; < 0 bad
	bmi  InvalidChr
	cmp  #'9'+1 								; <= 9 digit
	bmi  HexDigit
	cmp  #'A' 									; < A or > F bad
	bmi  InvalidChr
	cmp  #'F'+1
	bpl  InvalidChr
	sec  										; adjust for text.
	sbc  #7
HexDigit:
	and  #$F 									; return as bits 0..3
	rts  

InvalidChr:
	lda  #$80 									; convert failed, return bit 7 high.
	rts  

; ********************************************************************************
;                                        
;                     Print address in FE, space, value in FC
;                                        
; ********************************************************************************

PrintAddrData:
    jsr  PrintAddr 								; print current address
	nop  
	nop  
	jsr  PrintSpace 							; seperate space
	bne  PrintByte 								; and data.

; ********************************************************************************
;                                        
;                              Print address in (FE)
;                                        
; ********************************************************************************

PrintAddr:
	ldx  #3 									; print byte at offset 3 (FF)
	jsr  PrintByteOffset
	dex   										; offset 2 (FE)
	.byte $2C 									; the SKIP +2

; ********************************************************************************
;                                        
;                                Print byte in FC
;                                        
; ********************************************************************************

PrintByte:
	ldx  #0 									; byte at FC

PrintByteOffset:
	lda  CurrentData,X 							; read, shift right 4 and print
	lsr  A
	lsr  A
	lsr  A
	lsr  A
	jsr  PrintHexNibble
	lda  CurrentData,X 							; re-read and fall through.

; ********************************************************************************
;                                        
;                              Output Hex value in A
;                                        
; ********************************************************************************

PrintHexNibble:
	and  #$F 									; convert to ASCII
	ora  #'0'
	cmp  #'9'+1
	bmi  IsDigitValue
	clc  
	adc  #7
IsDigitValue:
	jmp  OutputCharacter 						; and output

	nop 										; filler.
	nop

; ********************************************************************************
;                                        
;                      Roll Nibble into FE/FC depending on X
;                                        
; ********************************************************************************

RollNibbleToWord:
	ldy  #4 									; do it 4 times.
	asl  A 										; shift nibble into upper bits
	asl  A
	asl  A
	asl  A
RollBitIntoWord:
	rol  A 										; shift bit in.
	rol  ToAddress,X 							; rotate into address
	rol  ToAddress+1,X
	dey  										; do 4 times
	bne  RollBitIntoWord
	rts  

; ********************************************************************************
;                                        
;                           Get key from keyboard/ACIA
;                                        
; ********************************************************************************

GetCharKbdAcia:
	lda  InputFromSerial 						; check flag
	bne  GetCharAcia 							; non-zero get from ACIA
	jmp  ReadKeyboard 							; else get from keyboard

; ********************************************************************************
;                                        
;                       Print byte at (FE),Y assumes Y = 0
;                                        
; ********************************************************************************

PrintByteAtFE:
	lda  (FromAddress),Y 						; copy into $FC
	sta  CurrentData
	jmp  PrintByte 								; and use that routine.

; ********************************************************************************
;                                        
;                  Write / Bump current address (assumes Y = 0)
;                                        
; ********************************************************************************

WriteAndBumpAddress:
	sta  (FromAddress),Y 						; write in current address
BumpAddress:
	inc  FromAddress 							; advance address
	bne  NoCarryOut
	inc  FromAddress+1
NoCarryOut:
	rts  

; ********************************************************************************
;                                        
;                               System Entry Point
;                                        
; ********************************************************************************

SystemReset:
	cld  										; reset decimal mode snd stacks
	ldx  #$28
	txs  
	jsr  ResetACIA-Offset 						; reset ACIA
	jsr  ResetVectorDataArea 					; reset vectors
	jsr  ClearScreen 							; clear screen
	sty  CursorX

PrintPrompt: 									; print boot message.
	lda  BootText-Offset,Y
	jsr  OutputCharacter
	iny  
	cpy  #BootTextEnd-BootText
	bne  PrintPrompt

	jsr  InputCharacter 						; get a character
	and  #$DF 									; capitalise it.
	cmp  #'D'
	bne  NotDKey
	jmp  BootstrapDisk-Offset 					; D Bootstraps

NotDKey:
	cmp  #'M'									; M monitors
	bne  NotMKey
	jmp  MonitorColdStart

NotMKey:
	cmp  #'W' 									; W Warm starts vectors
	bne  NotWKey
	jmp  BASIC_WarmStart

NotWKey:
	cmp  #'C' 									; if not C, go round again.
	bne  SystemReset
	jmp  BASIC_ColdStart						; cold start BASIC

; ********************************************************************************
;
;                                 keyboard matrix
;
; ********************************************************************************

KeyboardCharTable:
	.byte 'P',59,'/',' ','Z','A','Q'			; row $02, bits $02-$80
	.byte ',','M','N','B','V','C','X'			; row $04
	.byte 'K','J','H','G','F','D','S'			; row $08
	.byte 'I','U','Y','T','R','E','W'			; row $10
	.byte $00,$00,$0D,$0A,'O','L','.' 			; row $20
	.byte $00,$5F,'-',':','0','9','8'			; row $40
	.byte '7','6','5','4','3','2','1'			; row $80

; ********************************************************************************
;
;									Raw printer
;
; ********************************************************************************

PrintRawOldCharacter:
	jsr  PrintOldCharacterAtCurrent 			; old character.

PrintRawStartOfLineA:
	ldx  #0 									; zero cursor posiition.
	stx  CursorX
PrintRawCurrentA:
	ldx  CursorX
	lda  #$BD                                   ; lda ScreenTop,x
	sta  ProcessFromTopAndDexEdit
	jsr  ProcessFromTopAndDexEdit
	sta  OldCharacter 							; save as old character.
	lda  #$9D                                   ; set back to sta abs,x
	sta  ProcessFromTopAndDexEdit
PrintCursor:
	lda  #$5F 									; print underscore cursor character.
	bne  PrintCharacterAtCurrent

;                                        
;                         Print char at cursor location.
;                                        
PrintOldCharacterAtCurrent:
	lda  OldCharacter 							; old character
PrintCharacterAtCurrent: 
	ldx  CursorX 								; write A there.
	jmp  ProcessFromTopAndDexEdit

; ********************************************************************************
;                                        
;                               Old Screen Handler
;                                        
; ********************************************************************************

OldScreenRoutine:
	jsr  BASIC_OldScreenHandler 				; call the ROM routine
	jmp  ContinueOutput 						; continue with the ACIA test.

; ********************************************************************************
;                                        
;                              Output to ACIA/Screen
;                                        
; ********************************************************************************

VectoredOutput:
	jsr  NewScreenHandler
ContinueOutput:
	pha  
	lda  ACIASaveFlag 							; check flag
	beq  RestoreAExit                           ; if zero, pop A and exit
	pla  										; get character back
	jsr  WriteACIA-Offset                       ; write to acia
	cmp  #13
	bne  Exit1                                  ; not cr, exit now.

; ********************************************************************************
;                                        
;                             Output 10 NULLs to ACIA
;                                        
; ********************************************************************************

TenNulls:
	pha  										; save A & X
	txa  
	pha  
	ldx  #10 									; write this many NULLS
	lda  #0
NullLoop:
	jsr  WriteACIA-Offset 						; write loop
	dex  
	bne  NullLoop
	pla   										; restore and exit
	tax  
RestoreAExit:
	pla  
Exit1:
	rts  

; ********************************************************************************
;                                        
;                       Collect three addresses (FE,F9,E4)
;                                        
; ********************************************************************************

Collect3Addr:
	jsr  Collect2Addr
	jsr  PrintGreater
	ldx  #3
	jsr  CollectExtraAddress
	lda  CurrentData
	ldx  CurrentData+1
	sta  CopyTarget
	stx  CopyTarget+1
	rts  

; ********************************************************************************
;                                        
;                                 Home the Cursor
;                                        
; ********************************************************************************

HomeCursor:
	ldx  #2
CopyHomeInfo:
	lda  FirstScreenChar-1,X
	sta  CharSrcPos-1,X
	sta  CharPosition-1,X
	dex  
	bne  CopyHomeInfo
	rts  

	* = $FFE0
	.byte <ScreenVisibleBottom                  ; cursor start
	.byte LineLengthMinus1                      ; line length - 1
	.byte ScreenSize  							; screen size 0=1k 1=2k

; ********************************************************************************
;                                        
;                        Print a full stop and current address
;                                        
; ********************************************************************************

PrintCurrentAddr:
	lda  #'.'
	jsr  OutputCharacter
	jmp  PrintAddr

; ********************************************************************************
;
;								Monitor Vectors
;
; ********************************************************************************

InputCharacter:
	jmp  ($218)                                 ; input routine
OutputCharacter:
	jmp  ($21A)                                 ; output routine
CheckControlC:
	jmp  ($21C)                                 ; ctrl-c routine
SetLoadMode:
	jmp  ($21E)                                 ; load set up routine
SetSaveMode:
	jmp  ($220)                                 ; save set up routine

; ********************************************************************************
;
;									6502 Vectors
;
; ********************************************************************************

	.word NMIHandler                            ; nmi
	.word SystemReset                           ; reset
	.word IRQHandler                            ; irq

	.end 
