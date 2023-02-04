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

my %maps;

sub processfile {
    my ( $fi ) = @_;
    while ( <$fi> ) {
        chomp;
        # print "$_\n";
        next unless /^([A-Z0-9_]+)\s+equ\s+(0x[0-9a-f]{2})/;
        my ($ident,$index) = ( $1, eval($2) );
        next unless $ident =~ /^([A-Z]+)/;
        my $mapgrp = $1;
        # print "$mapgrp $ident $index\n";
        unless ( defined $maps{$mapgrp} ) {
            $maps{$mapgrp} = [];
            for ( $i=0; $i < 256; $i++ ) {
                $maps{$mapgrp}[$i] = '';
            }
        }
        $maps{$mapgrp}[$index] = $ident;
    }
}

sub process2 {
    my @block1;
    my @block2;
    for my $mapgrp ( sort keys %maps ) {
        my $aryref = $maps{$mapgrp};
        push @block2, lc($mapgrp)."_table:\n";
        for my $ident ( @$aryref ) {
            if ( $ident eq '' ) {
                my $lin2 = sprintf( "%-23s %-11s %s\n", '', 'dq', '0' );
                push @block2, $lin2;
            } else {
                my $id = lc($ident).'_text';
                my $line = sprintf( "%-23s %-11s '%s',0\n", $id, 'db', $ident );
                my $lin2 = sprintf( "%-23s %-11s %s\n", '', 'dq', $id );
                push @block1, $line;
                push @block2, $lin2;
            }
        }
    }
    for ( @block1 ) {
        print;
    }
    my $line = sprintf( "%-23s %-11s %s\n", '', 'align', '8,db 0' );
    print "\n$line\n";
    for ( @block2 ) {
        print;
    }
}

open my $fh,'<cookedsyntree.inc' || die "couldn't open cookedsyntree.inc: $!\n";
&processfile( $fh );
close $fh;

open my $fh2,'<keywords.inc' || die "couldn't open keywords.inc: $!\n";
&processfile( $fh2 );
close $fh2;

print "; created by extract_csntext.pl, DO NOT MODIFY!!\n\n";
&process2;
