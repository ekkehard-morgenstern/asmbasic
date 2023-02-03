#!/usr/bin/perl -w
#   AsmBASIC - a BASIC compile and go system written in assembly language
#   Copyright (C) 2022  Ekkehard Morgenstern
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
#   NOTE: Programs created with AsmBASIC do not fall under this license.
#
#   CONTACT INFO:
#       E-Mail: ekkehard@ekkehardmorgenstern.de
#       Mail: Ekkehard Morgenstern, Mozartstr. 1, D-76744 Woerth am Rhein,
#             Germany, Europe

open FILE,"<tokenlist.txt" || die "couldn't open token list\n";
open OUTP,">tokendef.inc"  || die "couldn't create token def\n";
open OUTK,">keywords.inc"  || die "couldn't create keywords inc\n";
print OUTP "; auto-generated by extract_tl.pl -- DO NOT MODIFY!\n\n";
print OUTK "; auto-generated by extract_tl.pl -- DO NOT MODIFY!\n\n";
my $n = 0;
while ( <FILE> ) {
    chomp;
    next unless /^([A-Z][A-Z0-9]*[\$]?[(]?)/;
    my $kw = $1;
    my $nl = length($kw);
    my $el = 2;
    my $va = sprintf("0x%02x",$n);
    print OUTP "                        db          $nl,$el,\"$kw\",0x03,";
    print OUTP "$va\n";
    $kw =~ s/\(/_FN/;
    $kw =~ s/\$/_STR/;
    my $id = "KW_$kw";
    my $idfld = sprintf("%-23s",$id);
    print OUTK "$idfld equ         $va\n";
    $n++;
    last if $n >= 256;
}
close OUTK;
close OUTP;
close FILE;
