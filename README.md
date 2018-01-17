# jrMIPS 

This is a logisim implementation of a single-cycle processor that resembles MIPS.

## Running

1. Logisim is required, you can download it [here](http://www.cburch.com/logisim/download.html)
2. Write an assembly program using the instructions and assembly language syntax in jrMIPS-manual.pdf
3. Load jrmips.circ into Logisim
4. Assemble your program with `perl jrmipsasm.pl progname.asm > progname.txt` then load progname.txt into logisim's ROM 
5. Generate the data segment with `perl jrmipsasm.pl progname.asm > progname.dat` then load progname.dat into logisim's RAM
6. Run the program
