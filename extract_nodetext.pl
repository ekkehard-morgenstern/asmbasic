#!/usr/bin/perl -w

print "; auto-generated by extract_nodetext.pl -- DO NOT MODIFY!\n\n";
print "                        cpu         x64\n";
print "                        bits        64\n\n";
print "                        section     .rodata\n\n";
print "                        global      nc_texts,tt_texts,tb_texts\n";
print "                        global      nt_texts\n\n";
#      0000000001111111112222222223333333334444444445
#      0123456890123456890123456890123456890123456890
open FILE,'<mainsyntax.inc' || die "can't open mainsyntax.inc: $!\n";
my @ncs;
my @tts;
my @tbs;
my @nts;
while (<FILE>) {
    chomp;
    next unless /equ/;
    if ( /^NC_/ && /^([A-Z_]+)/ ) {
        my $sym = lc($1);
        printf "%-23s %-11s '%s',0\n",$sym,'db',$1;
        push @ncs, $sym;
    } elsif ( /^TT_/ && /^([A-Z_]+)/ ) {
        my $sym = lc($1);
        printf "%-23s %-11s '%s',0\n",$sym,'db',$1;
        push @tts, $sym;
    } elsif ( /^TB_/ && /^([A-Z_]+)/ ) {
        my $sym = lc($1);
        printf "%-23s %-11s '%s',0\n",$sym,'db',$1;
        push @tbs, $sym;
    } elsif ( /^_?NT_/ && /^([A-Z0-9_]+)/ ) {
        my $sym = lc($1);
        printf "%-23s %-11s '%s',0\n",$sym,'db',$1;
        push @nts, $sym;
    }
}
close FILE;

print "                        align       8,db 0\n\n";
print "\nnc_texts:\n";
for ( @ncs ) {
    print "                        dq          $_\n";
}
print "\ntt_texts:\n";
for ( @tts ) {
    print "                        dq          $_\n";
}
print "\ntb_texts:\n";
for ( @tbs ) {
    print "                        dq          $_\n";
}
print "\nnt_texts:\n";
for ( @nts ) {
    print "                        dq          $_\n";
}
