import re
#
def maybeCase(s):
	return s
#
#			Reformat CegMon code
#
for l in open("cegmon.unformatted").readlines():
	l = l.rstrip().replace("\t"," ")
	if l.startswith(";"):
		l = l[1:].strip()
		if l.startswith("*"):
			print("; "+"*"*80)
		else:
			print("; {0}{1}".format(" "*(39-(len(l)>>1)),l))
	elif l == "":
		print(l)
	elif l.find("=") >= 0:
		print(l)
	else:
		m = re.match("^([a-zA-Z0-9\:]*)\s*([\.a-zA-Z]*)\s*(.*)",l)
		if m.group(1) != "":
			label = maybeCase(m.group(1))
			while label.endswith(":"):
				label = label[:-1]
			print(label+":")	
		opcode = m.group(2).lower()
		operand = m.group(3)
		comment = ""
		n = operand.find(";")
		if n >= 0:
			comment = operand[n+1:].strip()
			operand = operand[:n-1]
		s = "\t{0:4} {1}".format(opcode,maybeCase(operand))
		if comment != "":
			s = (s + " "*45)[:45]+"; "+comment.lower()
		print(s)