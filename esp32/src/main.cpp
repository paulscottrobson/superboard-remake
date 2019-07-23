
#include "fabgl.h"
#include "sys_processor.h"
#include "hardware.h"

// select one color configuration
#define USE_8_COLORS  0
#define USE_64_COLORS 1


// indicate VGA GPIOs to use for selected color configuration
#if USE_8_COLORS
	#define VGA_RED    GPIO_NUM_22
	#define VGA_GREEN  GPIO_NUM_21
	#define VGA_BLUE   GPIO_NUM_19
	#define VGA_HSYNC  GPIO_NUM_18
	#define VGA_VSYNC  GPIO_NUM_5
#elif USE_64_COLORS
	#define VGA_RED1   GPIO_NUM_22
	#define VGA_RED0   GPIO_NUM_21
	#define VGA_GREEN1 GPIO_NUM_19
	#define VGA_GREEN0 GPIO_NUM_18
	#define VGA_BLUE1  GPIO_NUM_5
	#define VGA_BLUE0  GPIO_NUM_4
	#define VGA_HSYNC  GPIO_NUM_23
	#define VGA_VSYNC  GPIO_NUM_15
#endif

#define PS2_PORT0_CLK GPIO_NUM_33
#define PS2_PORT0_DAT GPIO_NUM_32

#include "character_rom.inc"

static int colours[8] = { 0xFF0,0xF00,0x0F0,0x080,0x00F,0xF0F,0x0FF,0x000 };

void HWWriteCharacter(BYTE8 x,BYTE8 y,BYTE8 ch,BYTE8 colour) {
	RGB rgb,rgbx;
	BYTE8 rvs = (colour & 1) ? 0xFF:0x00;
	colour = (colour >> 1) & 7;
	rgbx.R = 0;rgbx.G = 0;rgbx.B = 0;
	int rgbc = colours[colour];
	rgb.R = (rgbc >> (8+2)) & 3; 
	rgb.G = (rgbc >> (4+2)) & 3; 
	rgb.B = (rgbc >> (0+2)) & 3; 
	int patternBase = (ch & 0xFF) * 8;
	x = x * 8 + 64;y = y * 8 + 4;
	Canvas.setBrushColor(rgbx);
	Canvas.fillRectangle(x,y,x+7,y+7);
	for (int y1 = 0;y1 < 8;y1++) {
		int pattern = character_rom[patternBase+y1]^rvs;
		int x1 = x;
		while (pattern != 0) {
			if (pattern & 1) Canvas.setPixel(x1,y+y1,rgb);
			x1++;
			pattern = pattern >> 1;
		}
	}
}

int HWGetScanCode(void) {
	return Keyboard.getNextScancode(0);
}

void setup()
{
	#if USE_8_COLORS
	VGAController.begin(VGA_RED, VGA_GREEN, VGA_BLUE, VGA_HSYNC, VGA_VSYNC);
	#elif USE_64_COLORS
	VGAController.begin(VGA_RED1, VGA_RED0, VGA_GREEN1, VGA_GREEN0, VGA_BLUE1, VGA_BLUE0, VGA_HSYNC, VGA_VSYNC);
	#endif

	VGAController.setResolution(VGA_320x200_75Hz, -1, -1);
	VGAController.enableBackgroundPrimitiveExecution(false);
	CPUReset();
	Keyboard.begin(PS2_PORT0_CLK, PS2_PORT0_DAT,false,false);
}


void loop()
{
	while (CPUExecuteInstruction() == 0) {
	}
}
