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


my %operdefs = (
    '<' => 'TOKEN lt-op := $0200 . -- <',
    '<=' => 'TOKEN le-op := $0201 . -- <=',
    '<>' => 'TOKEN ne-op := $0202 . -- <> ><',
    '><' => 'TOKEN ne-op := $0202 . -- <> ><',
    '>' => 'TOKEN gt-op := $0203 . -- >',
    '>=' => 'TOKEN ge-op := $0204 . -- >=',
    '=' => 'TOKEN eq-op := $0205 . -- =',
    '(' => 'TOKEN lparen := $0206 . -- (',
    ')' => 'TOKEN rparen := $0207 . -- )',
    ',' => 'TOKEN comma := $0208 . -- ,',
    ';' => 'TOKEN semic := $0209 . -- ;',
    ':' => 'TOKEN colon := $020a . -- :',
    '+' => 'TOKEN plus := $020b . -- +',
    '-' => 'TOKEN minus := $020c . -- -',
    '**' => 'TOKEN power := $020f . -- ** ^',
    '*' => 'TOKEN times := $020d . -- *',
    '/' => 'TOKEN slash := $020e . -- /',
    '^' => 'TOKEN power := $020f . -- ** ^',
    '&' => 'TOKEN ampersand := $0210 . -- &',
    '#' => 'TOKEN lattice := $0211 . -- #',
);

my %replacedefs = (
    'hex-number' => 'TOKEN hex-number := $0110 QWORD .',
    'dec-number' => 'TOKEN dec-number := $010a QWORD .',
    'oct-number' => 'TOKEN oct-number := $0108 QWORD .',
    'bin-number' => 'TOKEN bin-number := $0102 QWORD .',
    'num-ident' => 'TOKEN num-ident := $fe00 WORD:len BYTE*len .',
    'str-ident' => 'TOKEN str-ident := $fe01 WORD:len BYTE*len .',
    'num-func-ident' => 'TOKEN num-func-ident := $fe02 WORD:len BYTE*len .',
    'str-func-ident' => 'TOKEN str-func-ident := $fe03 WORD:len BYTE*len .',
    'string-literal' => 'TOKEN string-literal := $ff WORD:len BYTE*len .',
);

open FILE,"<tokenlist.txt" || die "couldn't open token list\n";
my $n = 0;
my %tokprods;
my %defs;
my %deford;
my $ord = 1;
for my $oper ( sort keys %operdefs ) {
    my $prod = $operdefs{$oper};
    $tokprods{$oper} = $prod;
    if ( $prod =~ /\s+([a-z0-9-]+)/ ) {
        $name = $1;
        unless ( defined $defs{$name} ) {
            $defs{$name} = $prod;
            $ordn = sprintf( "%04d", $ord++ );
            $deford{$ordn} = $name;
        }
    }
}
while ( <FILE> ) {
    chomp;
    next unless /^([A-Z][A-Z0-9]*[\$]?[(]?)/;
    my $name = $1;
    my $nameOrig = $name;
    $name =~ s/\(/_FN/;
    $name =~ s/\$/_STR/;
    if ( index( $name, '_' ) < 0 ) {
        $name .= '_KW';
    }
    $name = lc($name);
    $name =~ s/_/-/g;
    $prod = "TOKEN $name := \$03".sprintf("%02x",$n)." . -- $nameOrig";
    $tokprods{$nameOrig} = $prod;
    $defs{$name} = $prod;
    $ordn = sprintf( "%04d", $ord++ );
    $deford{$ordn} = $name;
    $n++;
    last if $n >= 256;
}
close FILE;

open FILE,"<defaultsyntax.ebnf" || die "couldn't open default syntax\n";
open OUTP,">main.ebnf" || die "couldn't create main ebnf\n";
my $line = '';
my $redefined = 0;
while (<FILE>) {
    chomp;
    next if /^--/;
    next if /^[ \t]*$/;
    unless ( /\.$/ ) {
        $line .= "$_ ";
        next;
    }
    $line .= $_;
    $line =~ s/[ \t]+/ /g;
    if ( $line =~ /([a-z0-9-]+)/ ) {
        $name = $1;
    } else {
        print STDERR "no name in line $line\n";
        $line = '';
        next;
    }
    # print "$name ::: $line\n";
    if ( defined $defs{$name} ) {
        print STDERR "production $name redefined\n";
        $redefined++;
        next;
    }
    $defs{$name} = $line;
    $ordn = sprintf( "%04d", $ord++ );
    $deford{$ordn} = $name;
    $line = '';
}
if ( $redefined > 0 ) {
    print STDERR "$redefined productions redefined\n";
    exit 1;
}
# replace some definitions with binary definitions
for my $name ( keys %replacedefs ) {
    my $line = $replacedefs{$name};
    $defs{$name} = $line;
}
# find out which definitions are still in use and which aren't
# step 1: which aren't referenced at all?
my @deletelist;
my $undefs = 0;
my %defused;
for my $name ( keys %defs ) {
    my $line = $defs{$name};
    my @idents;
    while ( $line =~ /\s+([a-z0-9-]+)/g ) {
        push @idents, $1;
    }
    for ( @idents ) {
        next if $_ eq '--' or $_ eq '-';
        unless ( defined $defs{$_} ) {
            print STDERR "undefined production $_\n";
            print STDERR "line was: $line\n";
            $undefs++;
            next;
        }
        $defused{$_} = 1;
    }
    my @kwsandops;
    my %replaces;
    while ( $line =~ /\s+'([^']+)'/g ) {
        my $kworop = $1;
        if ( defined $tokprods{$kworop} ) {
            my $prod = $tokprods{$kworop};
            my $prodname = '';
            if ( $prod =~ /\s+([a-z0-9-]+)/ ) {
                $prodname = $1;
            } else {
                print STDERR "bad production $prod\n";
                exit 1;
            }
            $replaces{$kworop} = $prodname;
        } else {
            print STDERR "undefined production for '$kworop'\n";
            print STDERR "line was: $line\n";
            $undefs++;
            next;
        }
    }
    for my $kworop ( keys %replaces ) {
        my $prodname = $replaces{$kworop};
        for (;;) {
            my $pos = index( $line, "'$kworop'" );
            my $len = length( $kworop ) + 2;
            last if $pos < 0;
            $line = substr( $line, 0, $pos ) . $prodname .
                substr( $line, $pos + $len );
        }
    }
    $defs{$name} = $line;
}
if ( $undefs > 0 ) {
    print STDERR "$undefs undefined production(s). stop.\n";
    exit 1;
}
for my $name ( keys %defs ) {
    next if $name eq 'direct-line'; # skip top level prod
    unless ( defined $defused{$name} ) {
        push @deletelist, $name;
    }
}
my $unused = 0;
for ( @deletelist ) {
    print STDERR "unused production $_\n";
    $unused++;
}
if ( $unused > 0 ) {
    print STDERR "$unused unused production(s). stop.\n";
    exit 1;
}
# step 2: recurse from top level production
%defused = ();
@deletelist = ();
sub mark_used {
    my ( $name ) = @_;
    return if defined $defused{$name};
    $defused{$name} = 1;
    my $line = $defs{$name};
    my @idents;
    while ( $line =~ /\s+([a-z0-9-]+)/g ) {
        push @idents, $1;
    }
    for ( @idents ) {
        next if $_ eq '--';
        next unless defined $defs{$_};
        &mark_used( $_ );
    }
}
&mark_used( 'direct-line' );
for my $name ( keys %defs ) {
    unless ( defined $defused{$name} ) {
        push @deletelist, $name;
    }
}
for ( @deletelist ) {
    # print "deleting unused production $_\n";
    delete $defs{$_};
}
print OUTP "-- generated by build_main_ebnf.pl, DO NOT MODIFY\n\n";
for my $ordn ( sort keys %deford ) {
    my $name = $deford{$ordn};
    if ( defined $defs{$name} ) {
        my $line = $defs{$name};
        print OUTP "$line\n";
    }
}
close OUTP;
close FILE;
