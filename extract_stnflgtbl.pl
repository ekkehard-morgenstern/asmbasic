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

system "cat mainsyntax.inc | egrep -o '^[A-Z0-9_]+' | egrep 'STMT|EXPR' >stmtsexprs.txt";

my %names;
open FILE,"<stmtsexprs.txt" || die "can't open stmtsexprs.txt: $!\n";
while ( <FILE> ) {
    chomp;
    my $flg = '';
    if ( /STMT/ ) {
        $flg = 'STNF_STMT';
    } elsif ( /EXPR/ ) {
        $flg = 'STNF_EXPR';
    }
    next unless $flg ne '';
    my $name = $_;
    $names{$name} = $flg;
}
close FILE;

my %indices;
open FILE,'mainsyntax.inc' || die "can't open mainsyntax.inc: $!\n";
while (<FILE>) {
    chomp;
    next unless /^([A-Z_0-9]+)\s+equ\s+([0-9]+)/;
    my ( $name, $value ) = ( $1, $2 );
    $indices{$value+0} = $name;
}
close FILE;

my $minIndex = 99999;
my $maxIndex = -1;
for ( keys %indices ) {
    my $index = $_;
    if ( $index < $minIndex ) {
        $minIndex = $index;
    }
    if ( $index > $maxIndex ) {
        $maxIndex = $index;
    }
}

# print "$minIndex, $maxIndex\n";
open FILE,'>stnflgtbl.nasm' || die "failed to create stnflgtbl.nasm: $!\n";
print FILE "; automatically created by extract_stnflgtbl.pl, DO NOT MODIFY!!\n\n";
my $line;
$line = sprintf( "%-24.24s%-12.12s%s", "", "cpu", "x64" );
print FILE "$line\n";
$line = sprintf( "%-24.24s%-12.12s%s", "", "bits", "64" );
print FILE "$line\n\n";
$line = sprintf( "%-24.24s%-12.12s%s", "", "%include", '"syntree.inc"' );
print FILE "$line\n\n";
$line = sprintf( "%-24.24s%-12.12s%s", "", "section", '.rodata' );
print FILE "$line\n\n";
$line = sprintf( "%-24.24s%-12.12s%s", "", "global", 'stnflgtbl' );
print FILE "$line\n\n";
print FILE "stnflgtbl:\n";
for ( $ix=$minIndex; $ix <= $maxIndex; $ix++ ) {
    my $flg = '0';
    if ( defined $indices{$ix} ) {
        my $name = $indices{$ix};
        if ( defined $names{$name} ) {
            $flg = $names{$name};
        }
    }
    $line = sprintf( "%-24.24s%-12.12s%s", "", "db", $flg );
    print FILE "$line\n";
}
$line = sprintf( "%-24.24s%-12.12s%s", "", "align", "8,db 0" );
print FILE "$line\n\n";
close FILE;
