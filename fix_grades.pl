#!/usr/bin/perl

# This script takes two files, being the grades for the
# current scheduling semester, and the grades for the
# semester previous to that. It looks for scores that
# are -1 in the current semester and replaces the score
# with that from the previous semester. This is done to
# cope with pre-graded proposals.

my $current_grades = $ARGV[0];
my $previous_grades = $ARGV[1];

if (!-e $current_grades) {
    die "Unable to find current grade file!\n";
}

if (!-e $previous_grades) {
    die "Unable to find previous grade file!\n";
}

open(OLD, $previous_grades);
my %oldscores;
while(<OLD>) {
    chomp(my $line = $_);
    $line =~ s/\"//g;
    my @els = split(/\,/, $line);
    if ($els[0] eq "Project") {
	next;
    }
    $oldscores{$els[0]} = $els[3];
}
close(OLD);

open(NEW, $current_grades);
my $mfile = $current_grades;
$mfile =~ s/\.csv$/\_mod.csv/;
open(MOD, ">".$mfile);
while(<NEW>) {
    chomp(my $line = $_);
    $line =~ s/\"//g;
    my @els = split(/\,/, $line);
    if ($els[0] ne "Project") {
	if ($els[3] < 0) {
	    print $els[0]." ".$els[3]."\n";
	    print "  replacing score\n";
	    if (defined $oldscores{$els[0]}) {
		$els[3] = $oldscores{$els[0]};
		print "  new score ".$oldscores{$els[0]}."\n";
	    }
	}
    }
    for (my $i = 0; $i <= $#els; $i++) {
	if ($i > 0) {
	    print MOD ",";
	}
	print MOD "\"".$els[$i]."\"";
    }
    print MOD "\n";
}
close(MOD);
close(NEW);
