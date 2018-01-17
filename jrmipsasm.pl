#!/usr/bin/perl -W
use Getopt::Std;

$version = "v0.9.1 03/21/17";

if (($#ARGV+1)==0) {
    print "usage: asm.pl [-vbpdm] filename\n";
    print "JrMIPS assembler $version\n";
    print "  -d output data section for loading into RAM\n";
    print "  -v display verbose information\n";
    print "  -p don't use pseudo-instructions\n";
    print "  -x print debug information\n";
    print "  -l dump labels and their addresses\n";
    print "  warning: the v2 assembly language is incompatible with past versions (v0, v1)\n";
    exit;
}
getopts("vpdlx",\%options);  # set allowed options in Getopt package

# mappings of register syntatic entities to their actual codes
%regs = (R0 => 0x0, R1 => 0x1, R2 => 0x2, R3 => 0x3, 
         R4 => 0x4, R5 => 0x5, R6 => 0x6, R7 => 0x7);
# synonym table for registers; this lets the assembly use $t0-$t3, which is compatible with MARS.
%rsyn =  (R0 => R0, R1 => R1, R2 => R2, R3 => R3, R4 => R4, R5 => R5, R6 => R6, R7 => R7,
          T0 => R0, T1 => R1, T2 => R2, T3 => R3, T4 => R4, T5 => R5, T6 => R6, T7 => R7);

# mapping of opcode mnemonics to their actual codes
%mnemonic = (AND => 0x0000,                 
	     NOR => 0x0001,
	     ADDI => 0x1000,                
	     ADDUI => 0x1001,
	     ADD => 0x2000,                 
	     SUB => 0x2001,                 
	     DIV => 0x3000,                 
	     MUL => 0x3001,
     	     SLLV => 0x4000,                
	     SRLV => 0x4001,
	     BX => 0x5000,                  
	     BZ => 0x5001,
	     BP => 0x6000,                  
	     BN => 0x6001,                  
	     LW => 0x7000,                  
	     SW => 0x7001,
             LI => 0x8000,
	     JAL => 0x9000,                 	     
	     JR => 0x9001,                  
	     J => 0xA000,
     	     PUT => 0xB000,
	     HALT => 0xB001);
emitheader();

# pass 1: process input, get labels, set label addresses
$addr = 0;
$daddr = 0;
$sect = 0; # 0 is text section (default), 1 is data section

while (<>) {
    $_=uc($_);         # convert to all uppercase

    # convert hex numbers (starting with 0X) to decimal
    # this is done by evaluating the perl replacement as code
    # the code converts the matching number to decimal and prepends a space
    # note: this is intended to only work with numbers as the last operand or
    #   following a label, which is true in the current assembly language
    $_ =~ s/([:,])\s*0X([0-9A-F]+)\s*/$1 . " ".hex($2)/eg;

    if (defined $options{x}) {
	print "DEBUG: $_";
    }
    # check for .data directive, switch to data segment processing
    if (/(\.DATA)/) {
	$sect = 1;
    }
    # check for .text directive, switch to text segment processing
    elsif (/(\.TEXT)/) {
	$sect = 0;
    }
    # process data section - get label, assign it next data address, get its value
    elsif ($sect == 1) {
	# data declarations are of the form:
	#    label: value
	# all values are word (16-bit) values!
	if (/(\w+):\s+(-?\d+)\s*/) {
	    $dlabel{$1}=$daddr;   # assign the label an address
	    $dvalue{$daddr}=($2&0xffff);  # the value for the label
	    $daddr++;             # increment to next address
	}
    }
    # processing text section - get labels, source line, etc.
    elsif ($sect == 0) {
	push(@source,$_);
	if (/(\w+):/) {
	    $label{$1}=$addr;
	    s/\w+://;
	}
	# be careful: this matches any input string for an opcode, but it should cause an error below
	if (/^\s*[A-Z]+/) {
	    # FIXME!  these pseudos should really be put into a table, with the address increment amount
	    #    if I add more pseudos, I'll fix this.
	    if (/^\s*OR/ && (!defined $options{p})) {
		# pseudo-instruction -- takes 2 actual instructions
		$addr++;
	    }
#	    elsif (/^\s*(LA|MOV)/ && (!defined $options{p})) {
#		# pseudo-instruction -- takes 2 actual instructions
#		$addr++;
#	    }
	    elsif (/^\s*(MOV)/ && (!defined $options{p})) {
		# pseudo-instruction -- takes 2 actual instructions
		$addr++;
	    }
	    $addr++;
	}
    }
}

# output the data section (for loading into RAM), if requested
if (defined $options{d}) {
    # print the value for each label; the labels are located at sequential addresses, 
    # starting at address 0
#    foreach $lab (sort keys %dlabel) {
#	printf "%04X\n", $dvalue{$dlabel{$lab}};	
    #}
    # BRC fixed 4/11 - print ordered by address
    my @lvalue= ();
    my $idx = 0;
    foreach $lab (sort keys %dlabel) {
	$lvalue[$dlabel{$lab}] = $dvalue{$dlabel{$lab}};  # put value at address of label
	$idx++;
    }

    # emit in order of addresses
    for ($i = 0; $i < $idx; $i++) {
	printf "%04X\n", $lvalue[$i];
    }
    
    # just print the data section and exit when -d is used
    exit;
}

# print the labels and their addresses for -l option
if (defined $options{l}) {
    # dump the symbol table (of labels)
    print "** Code labels:\n";
    foreach $lab (sort keys %label) {
	printf "%-8s: %04X\n", $lab, $label{$lab};
    }

    print "** Data labels:\n";
    foreach $lab (sort keys %dlabel) {
	printf "%-8s: %04X %04X\n", $lab, $dlabel{$lab}, $dvalue{$dlabel{$lab}};	
    }

    # just print the labels and exit when -l is used
    exit;
}

# pass 2: emit encoded instructions and resolved labels
#   a bunch of ugly regexps are used to match individual instructions - they can match stuff that isn't
#   actually legal assembly, so be careful.
$addr=0;
foreach (@source) {
    $line = $_;
    if (defined $options{x}) {
	print "DEBUG2: $line\n";
    }
    chomp $line;

    # strip labels
    s/\w+://;

    if (/^\s*PUT\s+\$([RT][0-7])\s*,\s*(-?\d+)/) {
	emit($addr++,$mnemonic{PUT}+($regs{$rsyn{$1}}<<9)+(($2 & 0xff)<<1), $line);
    }
    elsif (/^\s*PUT\s+\$([RT][0-7])\s*/) {
	emit($addr++,$mnemonic{PUT}+($regs{$rsyn{$1}}<<9)+((0 & 0xff)<<1), $line);
    }
    elsif (/^\s*(ADD|SUB|AND|NOR|SLLV|SRLV|DIV|MUL)\s+\$([RT][0-7])\s*,\s*\$([RT][0-7])\s*/) {
	emit($addr++,$mnemonic{$1}+($regs{$rsyn{$2}}<<9)+($regs{$rsyn{$3}}<<6), $line);
    }
    elsif (/^\s*(SLL|SRL)\s+\$([RT][0-7])\s*,\s*(-?\d+)/) {
	emit($addr++,$mnemonic{$1}+($regs{$rsyn{$2}}<<9)+(($3 & 0xf)<<1), $line);
    }
    elsif (/^\s*HALT/) {
	emit($addr++,$mnemonic{HALT}, $line);
    }
    elsif (/^\s*(ADDI|ADDUI|SET|SETR|LI)\s+\$([RT][0-7])\s*,\s*(-?\d+)/) {
	emit($addr++,$mnemonic{$1}+($regs{$rsyn{$2}}<<9)+(($3 & 0xff)<<1), $line);
    }
    # immediate instructions with a label operand is loading an address specified by a data label
    elsif (/^\s*(ADDI|ADDUI|SET|SETR)\s+\$([RT][0-7])\s*,\s*(\w+)/) {
	if (!defined $dlabel{$3}) {
	    print "Undefined data address label $3\n";
	    exit;
	}
	emit($addr++,$mnemonic{$1}+($regs{$rsyn{$2}}<<9)+(($dlabel{$3} & 0xff)<<1), $line);
    }
    # branch instructions: bn $reg,imm
    elsif (/^\s*(BN|BP|BZ|BX)\s+\$([RT][0-7])\s*,\s*(\w+)/) {
	if (!defined $label{$3}) {
	    print "Undefined label $2\n";
	    exit;
	}
	emit($addr++,$mnemonic{$1}+($regs{$rsyn{$2}}<<9)+(($label{$3} & 0xff)<<1), $line);
    }
    # NOT pseudo operation: not $reg
    elsif (/^\s*NOT\s+\$([RT][0-7])\s*/) {
	if (!defined $options{p}) {
	    emit($addr++,$mnemonic{NOR}+($regs{$rsyn{$1}}<<9)+($regs{$rsyn{$1}}<<6), $line);
	}
	else {
	    print "WARNING: Ooops! No pseudos are allowed but I found NOT.\n";
	}
    }
    # OR pseudo operation: or $reg,$reg
    elsif (/^\s*OR\s+\$([RT][0-7])\s*,\s*\$([RT][0-7])\s*/) {
	if (!defined $options{p}) {
	    emit($addr++,$mnemonic{NOR}+($regs{$rsyn{$1}}<<9)+($regs{$rsyn{$2}}<<6), $line);
	    emit($addr++,$mnemonic{NOR}+($regs{$rsyn{$1}}<<9)+($regs{$rsyn{$1}}<<6), "");
	}
	else {
	    print "WARNING: Ooops! No pseudos are allowed but I found OR.\n";
	}
    }
    # clear register pseudo (set to 0): clr $reg
    elsif (/^\s*CLR\s+\$([RT][0-7])\s*/) {
	if (!defined $options{p}) {
	    emit($addr++,$mnemonic{SUB}+($regs{$rsyn{$1}}<<9)+($regs{$rsyn{$1}}<<6), $line);
	}
	else {
	    print "WARNING: Ooops! No pseudos are allowed but I found CLR.\n";
	}
    }
    # load address pseudo operation: la $reg,dlabel
    elsif (/^\s*LA\s+\$([RT][0-7])\s*,\s*(\w+)\s*/) {
	if (!defined $options{p}) {
	    # clear the register
#	    emit($addr++,$mnemonic{SUB}+($regs{$rsyn{$1}}<<9)+($regs{$rsyn{$1}}<<6), $line);
	    # load address from data labels into the register
#	    emit($addr++,$mnemonic{ADDUI}+($regs{$rsyn{$1}}<<9)+(($dlabel{$2} & 0xff)<<1), "");	    
	    emit($addr++,$mnemonic{LI}+($regs{$rsyn{$1}}<<9)+(($dlabel{$2} & 0xff)<<1),$line);
	}
	else {
	    print "WARNING: Ooops! No pseudos are allowed but I found LA.\n";
	}
    }
#    elsif (/^\s*LI\s+\$([RT][0-7])\s*,\s*(-?\d+)/) {
#	if (!defined $options{p}) {
#	    # clear the register
#	    emit($addr++,$mnemonic{SUB}+($regs{$rsyn{$1}}<<9)+($regs{$rsyn{$1}}<<6), $line);
#	    # load the immediate
#	    emit($addr++,$mnemonic{ADDUI}+($regs{$rsyn{$1}}<<9)+(($2 & 0xff)<<1), "");	    
#	}
#	else {
#	    print "WARNING: Ooops! No pseudos are allowed but I found LI.\n";
#	}
#    }
    # MOV pseudo operation: mov $reg0,$reg1 - reg1 is copied to reg2
    elsif (/^\s*MOV\s+\$([RT][0-7])\s*,\s*\$([RT][0-7])\s*/) {
	if (!defined $options{p}) {
	    # clear the register
	    emit($addr++,$mnemonic{SUB}+($regs{$rsyn{$1}}<<9)+($regs{$rsyn{$1}}<<6), $line);
	    # move over the register by adding it
	    emit($addr++,$mnemonic{ADD}+($regs{$rsyn{$1}}<<9)+($regs{$rsyn{$2}}<<6), "");	    
	}
	else {
	    print "WARNING: Ooops! No pseudos are allowed but I found MOV.\n";
	}
    }
    elsif (/^\s*(SW|LW)\s+\$([RT][0-7])\s*,\s*\$([RT][0-7])\s*/) {
	emit($addr++,$mnemonic{$1}+($regs{$rsyn{$2}}<<9)+($regs{$rsyn{$3}}<<6), $line);
    }
    elsif (/^\s*JAL\s+\$([RT][0-7])\s*,\s*(\w+)/) {
	emit($addr++,$mnemonic{JAL}+($regs{$rsyn{$1}}<<9)+(($label{$2} & 0xff)<<1), $line);
    }
    elsif (/^\s*JR\s+\$([RT][0-7])/) {
	emit($addr++,$mnemonic{JR}+($regs{$rsyn{$1}}<<9), $line);
    }
    elsif (/^\s*(MLO|MHI)\s+\$([RT][0-7])/) {
	emit($addr++,$mnemonic{$1}+($regs{$rsyn{$2}}<<9), $line);
    }
    elsif (/^\s*J\s+(\w+)/) {
	emit($addr++,$mnemonic{J}+(($label{$1} & 0xff)<<1), $line);
    }
    elsif (/^\s*[\#;]?\s+/) {
	# yummy: a comment or blank line has been eaten!
    }
    else {
	print "ERROR: $line\n";
	exit;
    }
}

emittrailer();

exit;

# subroutine to output the instruction
sub emit {
    if (defined $options{v}) {
	# verbose mode shows address, encoded instruction, and instruction string
	printf "%04X:%04X\t$_[2]\n", $_[0], $_[1];
    }
    else {
	# normal mode just shows the encoded instruction for Logisim's ROM file
	printf "%04X\n", $_[1];
    }
}

# output the header
sub emitheader {
    if (defined $options{v} || defined $options{l}) {
	print "JrMIPS assembler $version\n";
    }
    else {
	# header in memory data file required by Logisim
	print "v2.0 raw\n";
	print "\# JrMIPS ISA version $version\n";
	print "\# to load this file into Logisim:\n";
	print "\# 1) save the output from the assembler to a file\n";
	print "\# 2) use the poke tool in Logisim and control-click the ROM/RAM component\n";
	print "\# 3) select Load Image menu option\n";
	print "\# 4) load the saved file\n";
    }
}

# output trailer at end of file
sub emittrailer {
}


