#!/usr/bin/perl

# Modify the JSON schedule without having to redo the scheduling of
# already scheduled blocks. This script can alter things like project
# codes and scores.

use JSON;
use Getopt::Long;
use DateTime;
use Data::Dumper;
use Astro::Time;
use Astro::Coord;
use POSIX;
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
my @changecolour;
my @addexperiment;
my $fixbands = 0;
my $coi_reference = 0;
my @codeclears;
my $clearall = 0;
my $copy_affiliations = 0;
my $copy_emails = 0;
my $copy_positions = 0;
my @fillerexperiment;

GetOptions(
    "input=s" => \$json_input,
    "output=s" => \$json_output,
    "grades=s" => \$grades_file,
    "changecode=s{2}" => \@codechanges,
    "legacy=s" => \@legacy,
    "deletecode=s" => \@codedeletions,
    "reference=s" => \$json_reference,
    "refcopy=s" => \@reference_copies,
    "minuteoffset=i" => \$minuteoffset,
    "changecolor=s{2}" => \@changecolour,
    "add=s" => \@addexperiment,
    "filler=s" => \@fillerexperiment,
    "fixband" => \$fixbands,
    "coinvestigators" => \$coi_reference,
    "clear=s" => \@codeclears,
    "clearall" => \$clearall,
    "copyaffiliations" => \$copy_affiliations,
    "copyemails" => \$copy_emails,
    "copypositions" => \$copy_positions
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
	#printf("LOOKING FOR PROJECT %s IN REFERENCE\n", $reference_copies[$i]);
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
	    printf("OVERWRITING PROJECT %s FROM REFERENCE\n",
		   $refjref->{'program'}->{'project'}->[$refidx]->{'ident'});
	    splice(@{$jref->{'program'}->{'project'}}, $jidx, 1,
		   $refjref->{'program'}->{'project'}->[$refidx]);
	    $changemade = 1;
	} elsif ($refidx >= 0) {
	    printf("COPYING PROJECT %s FROM REFERENCE\n", 
		   $refjref->{'program'}->{'project'}->[$refidx]->{'ident'});
	    # Make a new entry.
	    push @{$jref->{'program'}->{'project'}}, $refjref->{'program'}->{'project'}->[$refidx];
	    # Unschedule all the slots in the copy.
	    $changemade = 1;
	    $jidx = $#{$jref->{'program'}->{'project'}};
	}
	if (($refidx >= 0) && ($jidx >= 0)) {
	    # Unschedule all the slots from the reference.
	    for (my $j = 0; $j <= $#{$jref->{'program'}->{'project'}->[$jidx]->{'slot'}}; $j++) {
		$jref->{'program'}->{'project'}->[$jidx]->{'slot'}->[$j]->{'scheduled_start'} = 0;
		$jref->{'program'}->{'project'}->[$jidx]->{'slot'}->[$j]->{'scheduled'} = 0;
		$jref->{'program'}->{'project'}->[$jidx]->{'slot'}->[$j]->{'scheduled_duration'} = 0;
	    }
	}
    }
}

# Check whether we want to clear some codes.
if ($clearall == 1) {
    # We copy all the codes into the clearance list.
    @codeclears = ();
    for (my $j = 0; $j <= $#{$jref->{'program'}->{'project'}}; $j++) {
	push @codeclears, $jref->{'program'}->{'project'}->[$j];
    }
}


# Clear allocations.
if ($#codeclears >= 0) {
    for (my $i = 0; $i <= $#codeclears; $i++) {
	for (my $j = 0; $j <= $#{$jref->{'program'}->{'project'}}; $j++) {
	    if ($jref->{'program'}->{'project'}->[$j] eq $codeclears[$i]) {
		# Unschedule all the slots.
		$changemade = 1;
		printf("CLEARING SCHEDULED SLOTS FOR PROJECT %s\n",
		       $jref->{'program'}->{'project'}->[$j]->{'ident'});
		for (my $k = 0; $k <= $#{$jref->{'program'}->{'project'}->[$j]->{'slot'}}; $k++) {
		    $jref->{'program'}->{'project'}->[$j]->{'slot'}->[$k]->{'scheduled_start'} = 0;
		    $jref->{'program'}->{'project'}->[$j]->{'slot'}->[$k]->{'scheduled'} = 0;
		    $jref->{'program'}->{'project'}->[$j]->{'slot'}->[$k]->{'scheduled_duration'} = 0;
		}
		last;
	    }
	}
    }
}

# Fix array-type bands from the reference.
if ((defined $refjref) && ($fixbands == 1)) {
    for (my $i = 0; $i <= $#{$jref->{'program'}->{'project'}}; $i++) {
	my $refidx = -1;
	my $bref;
	for (my $j = 0; $j <= $#{$jref->{'program'}->{'project'}->[$i]->{'slot'}}; $j++) {
	    if ($jref->{'program'}->{'project'}->[$i]->{'slot'}->[$j]->{'bands'}->[0]
		=~ /ARRAY/) {
		# This is a bug that we can fix.
		if ($refidx == -1) {
		    for (my $k = 0; $k <= $#{$refjref->{'program'}->{'project'}}; $k++) {
			if ($refjref->{'program'}->{'project'}->[$k]->{'ident'} eq
			    $jref->{'program'}->{'project'}->[$i]->{'ident'}) {
			    $refidx = $k;
			    last;
			}
		    }
		}
		if ($refidx >= 0) {
		    if (defined $refjref->{'program'}->{'project'}->[$refidx]->{'slot'}->[$j]->{'bands'}) {
			$bref = $refjref->{'program'}->{'project'}->[$refidx]->{'slot'}->[$j]->{'bands'};
		    }
		    printf("CORRECTING BAND SPECIFICATION FOR SLOT %d OF %s; BAND WAS %s, IS %s\n",
			   $j, $jref->{'program'}->{'project'}->[$i]->{'ident'},
			   $jref->{'program'}->{'project'}->[$i]->{'slot'}->[$j]->{'bands'}->[0],
			   join(" ", $bref));
		    $jref->{'program'}->{'project'}->[$i]->{'slot'}->[$j]->{'bands'} = $bref;
		    $changemade = 1;
		}
	    }
	}
    }
}

# Copy co-investigators from the reference.
if ((defined $refjref) && ($coi_reference == 1)) {
    for (my $i = 0; $i <= $#{$jref->{'program'}->{'project'}}; $i++) {
	my $colist = $jref->{'program'}->{'project'}->[$i]->{'co_investigators'};
	for (my $k = 0; $k <= $#{$refjref->{'program'}->{'project'}}; $k++) {
	    if ($refjref->{'program'}->{'project'}->[$k]->{'ident'} eq
		$jref->{'program'}->{'project'}->[$i]->{'ident'}) {
		$jref->{'program'}->{'project'}->[$i]->{'co_investigators'} =
		    $refjref->{'program'}->{'project'}->[$k]->{'co_investigators'};
		printf("COPYING %d CO-INVESTIGATORS FROM PROJECT %s\n",
		       $#{$jref->{'program'}->{'project'}->[$i]->{'co_investigators'}} + 1,
		       $refjref->{'program'}->{'project'}->[$k]->{'ident'});
		$changemade = 1;
		last;
	    }
	}
    }
}

# Copy affiliations from the reference.
if ((defined $refjref) && ($copy_affiliations == 1)) {
    for (my $i = 0; $i <= $#{$jref->{'program'}->{'project'}}; $i++) {
	for (my $k = 0; $k <= $#{$refjref->{'program'}->{'project'}}; $k++) {
	    if ($refjref->{'program'}->{'project'}->[$k]->{'ident'} eq
		$jref->{'program'}->{'project'}->[$i]->{'ident'}) {
		printf("COPYING AFFILIATIONS FROM PROJECT %s\n",
		       $refjref->{'program'}->{'project'}->[$k]->{'ident'});
		$jref->{'program'}->{'project'}->[$i]->{'PI_affiliation'} =
		    $refjref->{'program'}->{'project'}->[$k]->{'PI_affiliation'};
		$jref->{'program'}->{'project'}->[$i]->{'PI_country'} =
		    $refjref->{'program'}->{'project'}->[$k]->{'PI_country'};
		$jref->{'program'}->{'project'}->[$i]->{'coI_affiliations'} =
		    $refjref->{'program'}->{'project'}->[$k]->{'coI_affiliations'};
		$jref->{'program'}->{'project'}->[$i]->{'coI_countries'} =
		    $refjref->{'program'}->{'project'}->[$k]->{'coI_countries'};
		$changemade = 1;
		last;
	    }
	}
    }
}
# Copy emails from the reference.
if ((defined $refjref) && ($copy_emails == 1)) {
    for (my $i = 0; $i <= $#{$jref->{'program'}->{'project'}}; $i++) {
	for (my $k = 0; $k <= $#{$refjref->{'program'}->{'project'}}; $k++) {
	    if ($refjref->{'program'}->{'project'}->[$k]->{'ident'} eq
		$jref->{'program'}->{'project'}->[$i]->{'ident'}) {
		printf("COPYING EMAILS FROM PROJECT %s\n",
		       $refjref->{'program'}->{'project'}->[$k]->{'ident'});
		$jref->{'program'}->{'project'}->[$i]->{'PI_email'} =
		    $refjref->{'program'}->{'project'}->[$k]->{'PI_email'};
		$jref->{'program'}->{'project'}->[$i]->{'coI_emails'} =
		    $refjref->{'program'}->{'project'}->[$k]->{'coI_emails'};
		$changemade = 1;
		last;
	    }
	}
    }
}
# Copy positions from the reference.
if ((defined $refjref) && ($copy_positions == 1)) {
    for (my $i = 0; $i <= $#{$jref->{'program'}->{'project'}}; $i++) {
	for (my $k = 0; $k <= $#{$refjref->{'program'}->{'project'}}; $k++) {
	    if ($refjref->{'program'}->{'project'}->[$k]->{'ident'} eq
		$jref->{'program'}->{'project'}->[$i]->{'ident'}) {
		# We have to copy positions slot by slot.
		printf("FROM PROJECT %s:\n", $jref->{'program'}->{'project'}->[$i]->{'ident'});
		for (my $j = 0; $j <= $#{$jref->{'program'}->{'project'}->[$i]->{'slot'}}; $j++) {
		    for (my $l = 0; $l <= $#{$refjref->{'program'}->{'project'}->[$k]->{'slot'}}; $l++) {
			if ($jref->{'program'}->{'project'}->[$i]->{'slot'}->[$j]->{'source'} eq
			    $refjref->{'program'}->{'project'}->[$k]->{'slot'}->[$l]->{'source'}) {
			    printf("COPYING POSITION FOR SOURCE %s FROM REFERENCE %s %s\n",
				   $jref->{'program'}->{'project'}->[$i]->{'slot'}->[$j]->{'source'},
				   $refjref->{'program'}->{'project'}->[$k]->{'slot'}->[$l]->{'position'}->{'ra'},
				   $refjref->{'program'}->{'project'}->[$k]->{'slot'}->[$l]->{'position'}->{'dec'});
			    $jref->{'program'}->{'project'}->[$i]->{'slot'}->[$j]->{'position'}->{'ra'} =
				$refjref->{'program'}->{'project'}->[$k]->{'slot'}->[$l]->{'position'}->{'ra'};
			    $jref->{'program'}->{'project'}->[$i]->{'slot'}->[$j]->{'position'}->{'dec'} =
				$refjref->{'program'}->{'project'}->[$k]->{'slot'}->[$l]->{'position'}->{'dec'};
			    $changemade = 1;
			    last;
			}
		    }
		}
		last;
	    }
	}
    }
}


# Add any new projects.
if ($#addexperiment >= 0) {
    # Format should be comma separated string.
    # Elements are:
    # 0    1  2     3     4      5        6     7    8    9      10 11  12   13
    # code,PI,title,score,nslots,hoursper,array,band,mode,source,ra,dec,type,colour
    for (my $i = 0; $i <= $#addexperiment; $i++) {
	my @els = split(/\,/, $addexperiment[$i]);
	# Check for duplicated code.
	my $dcode = 0;
	for (my $j = 0; $j <= $#{$jref->{'program'}->{'project'}}; $j++) {
	    if ($jref->{'program'}->{'project'}->[$j]->{'ident'} eq
		uc($els[0])) {
		printf("UNABLE TO ADD PROJECT %s, DUPLICATE CODE FOUND\n",
		       $jref->{'program'}->{'project'}->[$j]->{'ident'});
		$dcode = 1;
		last;
	    }
	}
	if ($dcode == 0) {
	    $els[0] = uc($els[0]);
	    printf("ADDED PROJECT %s\n", $els[0]);
	    my $np = {
		'ident' => $els[0],
		'title' => $els[2],
		'preferred_dates' => "", 'excluded_dates' => [],
		'comments' => "",
		'type' => uc($els[12]),
		'PI' => $els[1], 'pi_email' => "",
		'colour' => $els[13], 'prefers_night' => 0,
		'slot' => []
	    };
	    for (my $j = 0; $j < $els[4]; $j++) {
		my $ns = {
		    'scheduled_duration' => 0,
		    'array' => $els[6],
		    'lst_end' => "23:59",
		    'lst_start' => "00:00",
		    'source' => $els[9],
		    'bandwidth' => $els[8],
		    'requested_duration' => $els[5] * 1.0,
		    'scheduled_start' => 0,
		    'position' => { 'ra' => $els[10], 'dec' => $els[11] },
		    'scheduled' => 0,
		    'rating' => $els[3] * 1.0,
		    'bands' => [ $els[7] ],
		    'lst_limits_used' => 0
		};
		push @{$np->{'slot'}}, $ns;
	    }
	    push @{$jref->{'program'}->{'project'}}, $np;
	    $changemade = 1;
	}
    }
}

# Add any filler projects.
if ($#fillerexperiment >= 0) {
    # Format should be comma separated string.
    # Elements are:
    # 0  1
    # PI,obstable.json
    for (my $i = 0; $i <= $#fillerexperiment; $i++) {
	my @els = split(/\,/, $fillerexperiment[$i]);
	# Start with the filler experiment code CS001 ($i + 1)
	my $codeaccept = 0;
	my $extracode = 0;
	my $cfcode;
	while ($codeaccept == 0) {
	    $cfcode = sprintf "CS%03d", ($i + 1 + $extracode);
	    my $matchfound = 0;
	    for (my $j = 0; $j <= $#{$jref->{'program'}->{'project'}}; $j++) {
		if ($jref->{'program'}->{'project'}->[$j]->{'ident'} eq
		    uc($cfcode)) {
		    $matchfound = 1;
		    last;
		}
	    }
	    if ($matchfound == 1) {
		$extracode += 1;
	    } else {
		$codeaccept = 1;
	    }
	}
	my $np = {
	    'ident' => $cfcode, 'title' => "Filler project $cfcode",
		'preferred_dates' => "", 'excluded_dates' => [],
		'comments' => "", 'type' => "NORMAL",
		'PI' => $els[0], 'pi_email' => "",
		'colour' => "cdcdcd", 'prefers_night' => 0, 'slot' => []
	};
	my $observations = &getObsOnly("atca", $els[1]);
	my $total_time = 0;
	for (my $j = 0; $j <= $#{$observations->{'requested_times'}}; $j++) {
	    for (my $k = 0; $k < $observations->{'nrepeats'}->[$j]; $k++) {
		push @{$np->{'slot'}}, &createSlot(
		    $observations->{'requested_arrays'}->[$j],
		    $observations->{'requested_bands'}->[$j],
		    $observations->{'requested_bandwidths'}->[$j],
		    $observations->{'requested_sources'}->[$j],
		    $observations->{'requested_positions'}->[$j],
		    $observations->{'requested_times'}->[$j],
		    3.0, 0,
		    $observations->{'requested_lsts'}->[$j]->[0],
		    $observations->{'requested_lsts'}->[$j]->[1]
		    );
		$total_time += $observations->{'requested_times'}->[$j];
	    }
	}
	push @{$jref->{'program'}->{'project'}}, $np;
	$changemade = 1;
	printf("ADDED PROJECT %s with %.2f hours\n", $np->{'ident'}, $total_time);
    }
}

# Change colours.
if ($#changecolour >= 1) {
    for (my $i = 0; $i <= $#changecolour; $i += 2) {
	my $fchange = 0;
	for (my $j = 0; $j <= $#{$jref->{'program'}->{'project'}}; $j++) {
	    if ($jref->{'program'}->{'project'}->[$j]->{'ident'} eq
		$changecolour[$i]) {
		printf("CHANGED PROJECT %s FROM COLOUR %s to %s\n",
		       $jref->{'program'}->{'project'}->[$j]->{'ident'},
		       $jref->{'program'}->{'project'}->[$j]->{'colour'},
		       $changecolour[$i + 1]);
		$jref->{'program'}->{'project'}->[$j]->{'colour'} =
		    $changecolour[$i + 1];
		$fchange = 1;
		$changemade = 1;
		last;
	    }
	}
	if ($fchange == 0) {
	    printf("UNABLE TO FIND PROJECT %s TO CHANGE COLOUR\n",
		   $changecolour[$i]);
	}
    }
}

# Update the scores.
if (($grades_file ne "") && (-e $grades_file)) {
    my $projectScores = &parseScoreFile($grades_file, \@legacy);
    print Dumper $projectScores;
    
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
    if ($scorefile =~ /\.html/) {
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
    } elsif ($scorefile =~ /\.csv/) {
	my $scoremode = 0;
	while(<S>) {
	    chomp (my $line = $_);
	    if ($scoremode == 0) {
		if ($line =~ /^Ident\,Semester\,TAC_rating1/) {
		    $scoremode = 2;
		} elsif ($line =~ /^Semester\,Project\,PI\,Grade/) {
		    $scoremode = 3;
		} elsif ($line =~ /^\"Project\,Semester\,PI\,Grade\"/) {
		    $scoremode = 3;
		}
	    }
	    $line =~ s/\"//g;
	    my @scorebits = split(/\,/, $line);
	    my $ts = $scorebits[$scoremode];
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

sub getObsOnly($$$) {
    my $obs = shift;
    my $obsfile = shift;

    # Need some information about the observatory.
    my %ellim = ( 'atca' => 12, 'parkes' => 30 );
    my %lat = ( 'atca' => -30.31288, 'parkes' => -32.99841 );
    
    # Go through the observation XML hash and get useful information.
    my %receiver_mappings = ( 'UWL' => [ "UWL" ],
			      'MB' => [ "20cm multi-beam" ],
			      '10/50' => [ "10/50cm concentric" ],
			      'KU' => [ "12GHz methanol", "Ku-band" ],
			      'MARS' => [ "3cm Mars" ],
			      'K' => [ "13mm" ] );
    my @requested_times;
    my @repeats;
    my @arrays;
    my @bands;
    my @bandwidths;
    my @sources;
    my @radecs;
    my @lsts;

    my $obstablestring = `iconv -f utf-8 -t utf-8 -c $obsfile`;
    $obstablestring =~ s/\&\#x.*?\;//g;
    my $obsref = decode_json $obstablestring;
    
    my $obsarr = $obsref->{'sources'};
    for (my $i = 0; $i <= $#{$obsarr}; $i++) {
	# Get the position of this source.
	my ($ra, $dec) = ("", "");
	if (defined $obsarr->[$i]->{'position'}) {
	    my $p1 = $obsarr->[$i]->{'position'}->{'XAngle'};
	    my $p2 = $obsarr->[$i]->{'position'}->{'YAngle'};
	    my $coordsys = $obsarr->[$i]->{'position'}->{'system'};
	    ($ra, $dec) = &translateCoord($p1, $p2, 0, 0, $coordsys);
	} else {
	    # When we can't find a position.
	    $ra = "00:00:00";
	    $dec = "-90:00:00";
	}
	# Get the LSTs as well.
	my $lst_start = $obsarr->[$i]->{'lstStart'};
	if ($lst_start eq "") {
	    $lst_start = "00:00";
	}
	my $lst_end = $obsarr->[$i]->{'lstEnd'};
	if (($lst_end eq "") || ($lst_end eq "Never")) {
	    $lst_end = "23:59";
	}
	push @lsts, [ $lst_start, $lst_end ];
	my $tdec = str2turn($dec, "D");
	my $b = "";
	if ($obs eq "atca") {
	    $b = lc $obsarr->[$i]->{'band'};
	    if ($b =~ /\s+$/) {
		$b =~ s/\s+$//;
	    }
	}
	my ($xtra_reps, $reptime) = 
	    &roundRequestedTimes($obsarr->[$i]->{'integrationTime'},
				 $tdec, $b, $obs, \%ellim, \%lat);
	push @radecs, &stripSpacing($ra.",".$dec);
	push @requested_times, $reptime;
	push @repeats, $obsarr->[$i]->{'repeats'} * $xtra_reps;
	if ($obs eq "atca") {
	    my $a = lc $obsarr->[$i]->{'arrayConfiguration'};
	    if ($a =~ /km$/) {
		$a =~ s/km$//;
	    } elsif ($a =~ /m$/) {
		$a =~ s/m$//;
	    }
	    push @arrays, &stripSpacing($a);
	    my $b = lc $obsarr->[$i]->{'band'};
	    if ($b =~ /7\/3mm/) {
		$b =~ s/7\/3mm/7mm 3mm/g;
	    }
	    if ($b =~ /\s+$/) {
		$b =~ s/\s+$//;
	    }
	    push @bands, &stripSpacing($b);
	    push @bandwidths, $obsarr->[$i]->{'bandwidths'};
	}
	push @sources, &stripSpacing($obsarr->[$i]->{'name'});
    }

    # Map the names correctly.
    for (my $j = 0; $j <= $#bandwidths; $j++) {
	if ($bandwidths[$j] =~ /CFB 1M \(no zooms\)/) {
	    $bandwidths[$j] = "CFB1M";
	} elsif ($bandwidths[$j] =~ /CFB 1M-0.5k \(with zooms\)/) {
	    $bandwidths[$j] = "CFB1M-0.5k";
	} elsif ($bandwidths[$j] =~ /CFB 64M-32k/) {
	    $bandwidths[$j] = "CFB64M-32k";
	} elsif ($bandwidths[$j] =~ /CFB 1M \(pulsar binning\)/) {
	    $bandwidths[$j] = "CFB1M-pulsar";
	} elsif ($bandwidths[$j] =~ /CFB 1M\/64M/) {
	    $bandwidths[$j] = "CFB1-64M";
	}
    }
	
    # Send back our summary information.
    my $times_string = &concatArray(\@requested_times, \@repeats, 4);
    my $arrays_string = &concatArray(\@arrays, \@repeats, 3);
    my $bands_string = &concatArray(\@bands, \@repeats, 3);
    my $bandwidths_string = &concatArray(\@bandwidths, \@repeats, 3);
    my $sources_string = &concatArray(\@sources, \@repeats, 3);
    my $pos_string = &concatArray(\@radecs, \@repeats, 3);
    return {
	'requested_times' => \@requested_times,
	'summary_requested_times' => $times_string,
	'requested_arrays' => \@arrays,
	'summary_requested_arrays' => $arrays_string,
	'requested_bands' => \@bands,
	'summary_requested_bands' => $bands_string,
	'requested_bandwidths' => \@bandwidths,
	'summary_requested_bandwidths' => $bandwidths_string,
	'requested_sources' => \@sources,
	'summary_requested_sources' => $sources_string,
	'requested_positions' => \@radecs,
	'summary_requested_positions' => $pos_string,
	'nrepeats' => \@repeats,
	'requested_lsts' => \@lsts
    };

}

sub createSlot($$$$$$$$$$) {
    my $array = shift;
    my $bands = shift;
    my $bandwidth = shift;
    my $source = shift;
    my $position = shift;
    my $requested_duration = shift;
    my $rating = shift;
    my $lst_limits_used = shift;
    my $lst_start = shift;
    my $lst_end = shift;

    my @bands = split(/\s+/, $bands);
    my @pos = split(/\,/, $position);

    if ($rating <= 0) {
	$rating = 1.0;
    }
    
    return {
	'array' => $array, 'bands' => \@bands, 'bandwidth' => $bandwidth,
	'source' => $source,
	'position' => { 'ra' => $pos[0], 'dec' => $pos[1] }, 
	'requested_duration' => $requested_duration,
	'scheduled_duration' => 0, 'scheduled_start' => 0, 'scheduled' => 0,
	'rating' => $rating, 'lst_limits_used' => $lst_limits_used,
	'lst_start' => $lst_start, 'lst_end' => $lst_end
    };
}

sub translateCoord($$$$$) {
    my ($p1, $p2, $x1, $x2, $c) = @_;
    # Turn the XML-format coordinates into something more friendly.

    my $coordtype = ($c eq "galactic") ? 3 : 1;

    my ($ra_string, $dec_string);
    my $pi = 3.141592654;
    
    if ($coordtype == 1) {
	# We have p1 = RA, p2 = Dec
	$ra_string = $p1;
	$dec_string = $p2;
    } elsif ($coordtype == 3) {
	# We have p1 = Lon, p2 = Lat
	#$p1 *= 180 / $pi;
	#$p2 *= 180 / $pi;
	my ($ra, $dec) = (`cotra radec=$p1,$p2 type=galactic` =~ m{J2000:\s+(\S+)\s+(\S+)});
	$ra =~ s/\.\d+$//;
	$dec =~ s/\.\d+$//;
	$ra_string = $ra;
	$dec_string = $dec;
    }
    if ($ra_string eq "") {
	$ra_string = "00:00:00";
    }
    if ($ra_string =~ /^.*\s+.*\s+.*$/) {
	$ra_string =~ s/\s+/\:/g;
    }
    if ($dec_string eq "") {
	$dec_string = "00:00:00";
    }
    if ($dec_string =~ /^.*\s+.*\s+.*$/) {
	$dec_string =~ s/\s+/\:/g;
    }
    return ($ra_string, $dec_string);
}

sub roundRequestedTimes($$$$$$) {
    my $rqt = shift;
    my $tdec = shift;
    my $band = shift;
    my $obs = shift;
    my $ellimr = shift;
    my $latr = shift;
    
    # Determine how long the source is up.
    # The frequency determines the elevation limit.
    my $ellim = $ellimr->{$obs};
    if ($band =~ /mm/ && $obs eq "atca") {
	$ellim = 30;
    }
    $ellim /= 360.0; # in turns.

    my $tlat = $latr->{$obs} / 360.0;
    my %elhash = ( 'ELLOW' => $ellim );
    
    my $haset = haset_azel($tdec, $tlat, %elhash) * 24.0;
    my $time_up = 2 * $haset;
    if ($time_up <= 0) {
	$elhash{ 'ELLOW' } = $ellimr->{$obs};
	$haset = haset_azel($tdec, $tlat, %elhash) * 24.0;
	$time_up = 2 * $haset;
    }

    my $nrep = 1;
    #print " rqt = $rqt time up = $time_up\n";
    if ($time_up == 0) {
	# Something is horribly wrong, but we let the scheduler deal with it.
	return ( 1, $rqt );
    }
    if ($rqt > $time_up) {
	# The source isn't up for the entire time.
	while (($rqt / $nrep) > $time_up) {
	    $nrep += 1;
	}
    }
    # Round the requested time to the nearest half hour (always up).
    my $arqt = ceil($rqt / (0.5 * $nrep)) * 0.5;
    
    return ( $nrep, $arqt );
}

sub stripSpacing {
    my $a = shift;

    $a =~ s/^\s*(.*?)\s*$/$1/;
    # Take this opportunity to remove bad characters too.
    $a =~ s/\&/and/g;
    
    return $a;
}

sub concatArray($$;$) {
    # The reference to the array of values.
    my $aref = shift;
    # The reference to the array of counts. Must be the same length as
    # the aref array.
    my $rref = shift;
    # showCount = 0 for "do not ever show the number of repeats"
    # showCount = 1 for "only show repeats if there is more than 1 unique value"
    # showCount = 2 for "always show repeats"
    # showCount = 3 for "only show repeats if there is more than 1 in consecutive rows"
    # showCount = 4 for "same as 3 but if only one output, same as 1 as well"
    my $showCount = shift;
    
    if (!defined $showCount) {
	$showCount = 1;
    }

    # Take an array, and output a string representing repeats.

    my @s = @{$aref};
    my @r = @{$rref};
    my @o;
    my @c;
    my $p = $s[0];
    my $n = $r[0];
    for (my $i = 1; $i <= $#s; $i++) {
	if ($s[$i] eq $p) {
	    $n += $r[$i];
	} else {
	    # Do a check.
	    my $f = -1;
	    if ($showCount != 3 && $showCount != 4) {
		for (my $j = 0; $j <= $#o; $j++) {
		    if ($o[$j] eq $p) {
			$f = $j;
			last;
		    }
		}
	    }
	    if ($f < 0) {
		push @o, $p;
		push @c, $n;
	    } else {
		$c[$f] += $n;
	    }
	    $p = $s[$i];
	    $n = $r[$i];
	}
    }
    my $f = -1;
    if ($showCount != 3 && $showCount != 4) {
	for (my $j = 0; $j <= $#o; $j++) {
	    if ($o[$j] eq $p) {
		$f = $j;
		last;
	    }
	}
    }
    if ($f < 0) {
	push @o, $p;
	push @c, $n;
    } else {
	$c[$f] += $n;
    }

    if ($#o == 0 && $showCount != 2 && $showCount != 4) {
	$showCount = 0;
    }
    my $out = "";
    for (my $i = 0; $i <= $#o; $i++) {
	if ($i > 0) {
	    $out .= "; ";
	}
	if ($c[$i] > 1 && $showCount) {
	    $out .= $c[$i]."x";
	}
	$out .= $o[$i];
    }

    return $out;
}
