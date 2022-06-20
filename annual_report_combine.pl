#!/usr/bin/perl

# Takes several annual report output files and combines
# them, while keeping only one output line per project.

use strict;

my @projcodes;
my %projs;

for (my $i = 0; $i <= $#ARGV; $i++) {
    open(R, $ARGV[$i]);
    while (<R>) {
	chomp(my $line = $_);
	if ($line =~ /^\"(.*)\",\"(.*)\,(.*)$/) {
	    my $proj = $3;
	    my $pilist = $1;
	    my $title = $2;
	    if (!defined $projs{$proj}) {
		$projs{$proj} = {
		    'pis' => $pilist,
			'title' => $title
		};
		push @projcodes, $proj;
	    } else {
		# Update the information.
		$projs{$proj}->{'title'} = $title;
		my @olist = split(/\,/, $projs{$proj}->{'pis'});
		my @nlist = split(/\,/, $pilist);
		for (my $j = 0; $j <= $#nlist; $j++) {
		    my $f = 0;
		    for (my $k = 0; $k <= $#olist; $k++) {
			if ($olist[$k] eq $nlist[$j]) {
			    $f = 1;
			    last;
			}
		    }
		    if ($f == 0) {
			push @olist, $nlist[$j];
		    }
		}
		$projs{$proj}->{'pis'} = join(",", @olist);
	    }
	}
    }
    
    close(R);
}

for (my $i = 0; $i <= $#projcodes; $i++) {
    printf ("\"%s\",\"%s\",\"%s\"\n",
	    $projs{$projcodes[$i]}->{'pis'},
	    $projs{$projcodes[$i]}->{'title'},
	    $projcodes[$i]);
}
