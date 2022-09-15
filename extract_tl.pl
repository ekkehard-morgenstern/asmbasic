#!/usr/bin/perl -w

open FILE,"<tokenlist.txt" || die "couldn't open token list\n";
open OUTP,">tokendef.inc"  || die "couldn't create token def\n";
my $n = 0;
while ( <FILE> ) {
    chomp;
    next unless /^([A-Z][A-Z0-9]*[\$]?[(]?)/;
    my $nl = length($1);
    my $el = 2;
    print OUTP "                        db          $nl,$el,\"$1\",0x03,";
    print OUTP sprintf("0x%02x\n",$n);
    $n++;
    last if $n >= 256;
}
close OUTP;
close FILE;
