def shiftCalc(n):
	if n < 0x40: 		
		n = n - 1 		
		n = n ^ 0x10	
		n = n + 1 		
	else:
		n = n ^ 0x20	
	return n 			

keys = """
1	!
2	"
3	#
4	$
5	%
6	&
7	'
8	(
9 	)
0 	@
:	*
- 	=
; 	+
,	<
. 	>
/	?
""".replace("\t"," ").split("\n")
keys = [x.strip() for x in keys if x.strip() != ""]
for i in range(0,26):
	keys.append("{0} {1}".format(chr(i+97),chr(i+65)))

keymap = []
for k in keys:
	keymap.append([ord(k[0]),ord(k[-1]),k[0],k[-1]])
keymap.sort(key = lambda x:x[0])
for m in keymap:
	if shiftCalc(m[0]) != m[1]:
		print("Unshifted {0} Shifted {1} [${2:02x},${3:02x}] offset {4}".format(m[2],m[3],m[0],m[1],m[1]-m[0]))
		print("${0:02x} ${1:02x} {2}".format(m[0],shiftCalc(m[0]),"ERR" if shiftCalc(m[0]) != m[1] else "ok"))


