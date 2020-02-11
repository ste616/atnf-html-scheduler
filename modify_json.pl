#!/usr/bin/perl

# Modify the JSON schedule without having to redo the scheduling of
# already scheduled blocks. This script can alter things like project
# codes and scores.

use JSON;
use Getopt::Long;
use DateTime;
use Data::Dumper;
use strict;

# Get the arguments.
my @codechanges;
my @codedeletions;
my $grades_file = "";
my $json_input = "";
my $json_output = "";
my $json_reference = "";
my @reference_copies;
my @legacy;
my $minuteoffset = 0;

GetOptions(
    "input=s" => \$json_input,
    "output=s" => \$json_output,
    "grades=s" => \$grades_file,
    "changecode=s{2}" => \@codechanges,
    "legacy=s" => \@legacy,
    "deletecode=s" => \@codedeletions,
    "reference=s" => \$json_reference,
    "refcopy=s" => \@reference_copies,
    "minuteoffset=i" => \$minuteoffset
    );

my $changemade = 0;

# Read in the JSON.
open(J, $json_input) || die "Unable to open $json_input\n";
my $jstring = do { local $/; <J> };
close(J);
my $json = JSON->new->allow_nonref;
my $jref = $json->decode($jstring);

my $refjref;
if (($json_reference ne "") && (-e $json_reference)) {
    open(J, $json_reference) || die "Unable to open reference $json_reference\n";
    my $rjstring = do { local $/; <J> };
    close(J);
    $refjref = $json->decode($rjstring);
}

# Do the code changes first, starting with deletions.
for (my $i = 0; $i <= $#codedeletions; $i++) {
    my $fdel = 0;
    my $delidx = -1;
    for (my $j = 0; $j <= $#{$jref->{'program'}->{'project'}}; $j++) {
	if ($jref->{'program'}->{'project'}->[$j]->{'ident'} eq
	    $codedeletions[$i]) {
	    printf("DELETING PROJECT WITH CODE %s\n",
		   $jref->{'program'}->{'project'}->[$j]->{'ident'});
	    $delidx = $j;
	    last;
	}
    }
    if ($delidx >= 0) {
	splice @{$jref->{'program'}->{'project'}}, $delidx, 1;
	$fdel = 1;
	$changemade = 1;
    }
    if ($fdel == 0) {
	printf("UNABLE TO FIND PROJECT WITH CODE %s TO DELETE\n",
	       $codedeletions[$i]);
    }
}
for (my $i = 0; $i <= $#codechanges; $i += 2) {
    my $fchange = 0;
    for (my $j = 0; $j <= $#{$jref->{'program'}->{'project'}}; $j++) {
	if ($jref->{'program'}->{'project'}->[$j]->{'ident'} eq
	    $codechanges[$i]) {
	    printf("CHANGED PROJECT WITH CODE %s TO CODE %s\n",
		   $jref->{'program'}->{'project'}->[$j]->{'ident'},
		   $codechanges[$i + 1]);
	    $jref->{'program'}->{'project'}->[$j]->{'ident'} =
		$codechanges[$i + 1];
	    $fchange = 1;
	    $changemade = 1;
	    last;
	}
    }
    if ($fchange == 0) {
	printf("UNABLE TO FIND PROJECT WITH CODE %s TO CHANGE TO %s\n",
	       $codechanges[$i], $codechanges[$i + 1]);
    }
}

# Copy projects from the reference.
if ((defined $refjref) && ($#reference_copies >= 0)) {
    for (my $i = 0; $i <= $#reference_copies; $i++) {
	my $refidx = -1;
	my $jidx = -1;
	for (my $j = 0; $j <= $#{$refjref->{'program'}->{'project'}}; $j++) {
	    if ($refjref->{'program'}->{'project'}->[$j]->{'ident'} eq
		$reference_copies[$i]) {
		$refidx = $j;
		last;
	    }
	}
	for (my $j = 0; $j <= $#{$jref->{'program'}->{'project'}}; $j++) {
	    if ($jref->{'program'}->{'project'}->[$j]->{'ident'} eq
		$reference_copies[$i]) {
		$jidx = $j;
		last;
	    }
	}
	if (($refidx >= 0) && ($jidx >= 0)) {
	    printf("COPYING PROJECT %s FROM REFERENCE\n",
		   $refjref->{'program'}->{'project'}->[$refidx]->{'ident'});
	    splice(@{$jref->{'program'}->{'project'}}, $jidx, 1,
		   $refjref->{'program'}->{'project'}->[$refidx]);
	    $changemade = 1;
	}
    }
}

# Update the scores.
if (($grades_file ne "") && (-e $grades_file)) {
    my $projectScores = &parseScoreFile($grades_file, \@legacy);
    #print Dumper $projectScores;
    
    for (my $i = 0; $i <= $#{$jref->{'program'}->{'project'}}; $i++) {
	my $p = $jref->{'program'}->{'project'}->[$i];
	my $pid = $p->{'ident'};
	my $slots = $p->{'slot'};
	#printf("FOUND PROJECT %s, rating %.2f\n",
	#       $pid, $projectScores->{$pid});
	if ((defined $projectScores->{$pid}) &&
	    ($projectScores->{$pid} > 0) &&
	    ((!defined $slots->[0]->{'rating'}) ||
	     ($slots->[0]->{'rating'} != $projectScores->{$pid}))) {
	    #print "CHANGING PROJECT SCORE\n";
	    #print Dumper $slots;
	    for (my $j = 0; $j <= $#{$slots}; $j++) {
		if ($j == 0) {
		    printf("CHANGED SCORE OF PROJECT %s FROM %.2f TO %.2f\n",
			   $pid, $slots->[$j]->{'rating'}, 
			   $projectScores->{$pid});
		}
		$slots->[$j]->{'rating'} = $projectScores->{$pid};
		$changemade = 1;
	    }
	}
    }
}

# Put an offset into each time if requested.
if ($minuteoffset != 0) {
    for (my $i = 0; $i <= $#{$jref->{'program'}->{'project'}}; $i++) {
	for (my $j = 0; $j <= $#{$jref->{'program'}->{'project'}->[$i]->{'slot'}}; $j++) {
	    if ($jref->{'program'}->{'project'}->[$i]->{'slot'}->[$j]->{'scheduled_start'} > 0) {
		$jref->{'program'}->{'project'}->[$i]->{'slot'}->[$j]->{'scheduled_start'} +=
		    $minuteoffset * 60;
		$changemade = 1;
	    }
	}
    }
}

# Update the modified time if we've made changes.
if ($changemade == 1) {
    my $modtime = DateTime->now();
    $jref->{'modificationTime'} = $modtime->epoch();
}

# Write out the JSON.
if ($json_output eq "") {
    $json_output = $json_input;
    $json_output =~ s/\.json$/_modified.json/;
}
open(O, ">".$json_output) || die "Unable to open $json_output for writing\n";
printf O "%s\n", $json->pretty->encode($jref);
close(O);

sub parseScoreFile($$) {
    my $scorefile = shift;
    my $legacy = shift;

    my $s = {};
    open(S, $scorefile) || die "!! cannot open $scorefile\n";
    while(<S>) {
	chomp (my $line = $_);
	$line =~ s/^\s+//g;
	if ($line =~ /^\<input type\=\"hidden\" id\=.* name\=.* value=\"(.*)\"\>$/) {
	    my @scorebits = split(/\s+/, $1);
	    my $ts = ($scorebits[2] eq "-1.0") ? $scorebits[1] : $scorebits[2];
	    # Over-ride this if it's a Legacy project.
	    for (my $i = 0; $i <= $#{$legacy}; $i++) {
		if ($legacy->[$i] eq $scorebits[0]) {
		    $ts = "5.0";
		    last;
		}
	    }
	    $s->{$scorebits[0]} = $ts * 1.0;
	}
    }
    close(S);

    return $s;
}
