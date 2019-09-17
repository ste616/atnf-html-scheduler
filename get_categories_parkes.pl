#!/usr/bin/perl

# A script to return all the categories of science from proposals.
use XML::Simple;
use Data::Dumper;
use strict;

# Get a list of all the coversheet.xml files in this directory.
my $coversheets = `find . -name "coversheet.xml"`;
my @coversheets = split(/\n/, $coversheets);
my %cats;
my %sems;
my $sn = 0;
my $cloudstring = "";
for (my $i = 0; $i <= $#coversheets; $i++) {
    if ($coversheets[$i] !~ /parkes/) {
	next;
    }
    print $coversheets[$i]."\n";

    my $coverstring = `iconv -f utf-8 -t utf-8 -c $coversheets[$i]`;
    $coverstring =~ s/\&\#.*?\;//g;
    my $cover = XMLin($coverstring, ForceContent => 1);
    my $sem = $coversheets[$i];
    $sem =~ s/^\.\/(.*)\/parkes.*$/$1/;
    if (!defined $sems{$sem}) {
	$sems{$sem} = $sn + 1;
	foreach my $k (keys %cats) {
	    push @{$cats{$k}}, 0;
	}
	$sn++;
    }
    my $cstrings = $cover->{'categories'}->{'unserializable-parents'}->{'collection'}->{'string'};
    if (ref $cstrings ne "ARRAY") {
	$cstrings = [ $cstrings ];
    }
    for (my $j = 0; $j <= $#{$cstrings}; $j++) {
	#print $cstrings->[$j]->{'content'}."\n";
	#my @inds = split(/[\,]/, $cstrings->[$j]->{'content'});
	#print Dumper @inds;
	#for (my $k = 0; $k <= $#inds; $k++) {
	#    my $c = $inds[$k];
	#$c =~ s/^\s+//;
	#    $c =~ s/\s+$//;
	#    if (!defined $cats{$c}) {
	my $c = $cstrings->[$j]->{'content'};
	if (!defined $cats{$c}) {
	    $cats{$c} = [];
	    for (my $l = 0; $l <= $sn; $l++) {
		push @{$cats{$c}}, 0;
	    }
	}
	$cats{$c}->[$sn] += 1;
    }
    #print Dumper @categories;
    $cloudstring .= $cover->{'abstractText'}->{'content'};
}

#print Dumper %cats;
#print Dumper %sems;

my @semesterNames = sort keys %sems;
#print Dumper @semesterNames;
my @categoryNames = sort keys %cats;
my $pformat = "";
my $titleRow = "";
my %semesterTotals;
for (my $i = 0; $i <= $#semesterNames; $i++) {
    $titleRow .= sprintf("%-8s ", uc($semesterNames[$i]));
    $pformat .= "%-8.1f ";
    $semesterTotals{$semesterNames[$i]} = 0;
    for (my $j = 0; $j <= $#categoryNames; $j++) {
	$semesterTotals{$semesterNames[$i]} += $cats{$categoryNames[$j]}->[$sems{$semesterNames[$i]}];
    }
}


for (my $i = 0; $i <= $#categoryNames; $i++) {
    print $categoryNames[$i]."\n";
    print $titleRow."\n";
    my @catfrac;
    for (my $j = 0; $j <= $#semesterNames; $j++) {
	my $f = 0;
	if ($semesterTotals{$semesterNames[$j]} > 0) {
	    $f = $cats{$categoryNames[$i]}->[$sems{$semesterNames[$j]}] /
		$semesterTotals{$semesterNames[$j]};
	}
	push @catfrac, $f * 100;
    }
    printf $pformat."\n", @catfrac;
}

open(C, ">abstracts_parkes.txt");
print C $cloudstring."\n";
close(C);
