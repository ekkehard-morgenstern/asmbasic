#!/usr/bin/perl -w

my $byteix = 0;
my @bytes = (0) x 3072;
my $ln = 0;

open FILE,"<8x12font1.txt" || die "can't open input file: $!\n";
while (<FILE>) {
    chomp; $ln++;
    if ( /^!!/ ) {
        die "bad input file\n" unless /^!!8x12/;
        next;
    }
    if ( /^#([0-9a-fA-F]{2})/ ) {
        $byteix = ( $1 + 0 ) * 12;
        next;
    }
    if ( /^([.o]{8})/ ) {
        my $tmp = $1;
        $tmp =~ tr/.o/01/;
        $bytes[$byteix++] = eval "0b$tmp";
        last if $byteix >= 3072;
        next;
    }
    next if /^\s*$/;
    print "line $ln unaccounted for: $_\n";
}
close FILE;

open FILE,'>8x12font1.inc' || die "couldn't create output file: $!\n";
for ( my $i=0; $i < $byteix; $i += 12 ) {
    my $hexes = '';
    for ( my $j=0; $j < 12; $j++ ) {
        $hexes .= ',' if $j > 0;
        $hexes .= sprintf( "0x%02x", $bytes[$i+$j] );
    }
    print FILE "  db $hexes\n";
}
close FILE;
