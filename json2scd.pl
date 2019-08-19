#!/usr/bin/perl

# Conversion script between JSON and SCD formats.

use Data::Dumper;
use JSON;
use DateTime;
use strict;

my $json = JSON->new->allow_nonref;

my $infile = $ARGV[0];

# Do something based on the file extension.
if ($infile =~ /\.json$/) {
    # We've been given a JSON, we change to SCD.
    open(J, $infile) || die "Unable to open $infile\n";
    my $jstring = do { local $/; <J> };
    close(J);
    my $jref = $json->decode($jstring);
    my $prog = $jref->{'program'};
    my $outfile = $infile;
    $outfile =~ s/\.json$/\.scd/;
    open(O, ">".$outfile) || die "Unable to open $outfile for writing\n";
    print O "<Program>\n";
    print O "<Observatory>\nObservatory=".
	uc($prog->{'observatory'}->{'observatory'})."\n".
	"</Observatory>\n";
    print O "<Term>\n";
    print O "Term=".$prog->{'term'}->{'term'}.
	$prog->{'term'}->{'version'}."\n";
    my $startString = $prog->{'term'}->{'start'};
    $startString =~ s/\-/\//g;
    $startString .= " 00:00:00";
    print O "Start=".$startString."\n";
    my $endString = $prog->{'term'}->{'end'};
    $endString =~ s/\-/\//g;
    $endString .= " 00:00:00";
    print O "End=".$endString."\n";
    print O "Version=".$prog->{'term'}->{'version'}."\n";
    print O "Configs= ".join(" ", @{$prog->{'term'}->{'configs'}})."\n";
    print O "</Term>\n";
    for (my $i = 0; $i <= $#{$prog->{'project'}}; $i++) {
	my $proj = $prog->{'project'}->[$i];
	print O "<Project>\n";
	print O "Ident=".$proj->{'ident'}."\n";
	print O "Title=".$proj->{'title'}."\n";
	print O "PI=".$proj->{'PI'}."\n";
	print O "Type=".$proj->{'type'}."\n";
	print O "Polarimetry=false\nMosaic=false\nPulsarBinning=false\n";
	print O "Comments=0\n";
	for (my $j = 0; $j <= $#{$proj->{'slot'}}; $j++) {
	    my $slot = $proj->{'slot'}->[$j];
	    print O "<Slot>\n";
	    print O "Array=".uc($slot->{'array'})."\n";
	    print O "AltArray1=none\nAltArray2=none\n";
	    print O "Bands=".join(" ", @{$slot->{'bands'}})."\n";
	    print O "Bandwidths=".$slot->{'bandwidth'}."\n";
	    print O "Support=\n";
	    print O "Ant6=true\n";
	    print O "Source=".$slot->{'source'}."\n";
	    print O "RA=".$slot->{'position'}->{'ra'}."\n";
	    print O "Dec=".$slot->{'position'}->{'dec'}."\n";
	    my $lstLimitsUsed = ($slot->{'lst_limits_used'}) ? "true" : "false";
	    print O "LSTLimitsUsed=".$lstLimitsUsed."\n";
	    print O "SidTimRestricted=false\n";
	    my $lstStart = &lstConverter($slot->{'lst_start'});
	    my $lstEnd = &lstConverter($slot->{'lst_end'});
	    print O "SidTimStart=".$lstStart."\n";
	    print O "SidTimEnd=".$lstEnd."\n";
	    my @edStrings;
	    if (ref($proj->{'excluded_dates'}) eq "ARRAY") {
		my @ed = @{$proj->{'excluded_dates'}};
		for (my $k = 0; $k <= $#ed; $k++) {
		    my $es = &epoch2timeString($ed[$k], 1);
		    push @edStrings, $es."-".$es;
		}
	    }
	    print O "ExcludedDates=".join(", ", @edStrings)."\n";
	    my @pdStrings;
	    if (ref($proj->{'preferred_dates'}) eq "ARRAY") {
		my @pd = @{$proj->{'preferred_dates'}};
		for (my $k = 0; $k <= $#pd; $k++) {
		    my $ps = &epoch2timeString($pd[$k], 1);
		    push @pdStrings, $ps."-".$ps;
		}
	    }
	    print O "PreferredDates=".join(", ", @pdStrings)."\n";
	    print O "RequiredDates=\n";
	    print O "ReqDuration=".($slot->{'requested_duration'} *
				    3600000)."\n";
	    print O "AllDuration=0\n";
	    print O "SchDuration1=".($slot->{'scheduled_duration'} *
				     3600000)."\n";
	    print O "SchDuration2=0\n";
	    print O "Rating=".$slot->{'rating'}."\n";
	    print O "EarlyStart=2000/01/02 00:00:00\n";
	    my $isscheduled = ($slot->{'scheduled'} == 1) ? "true" : "false";
	    my $ss = "2000/01/02 00:00:00";
	    if ($isscheduled eq "true") {
		$ss = &epoch2timeString($slot->{'scheduled_start'}, 0);
	    }
	    print O "Start1=".$ss."\n";
	    print O "Start2=2000/01/02 00:00:00\n";
	    print O "Scheduled=".$isscheduled."\n";
	    print O "Locked=false\n";
	    my $c = &commentWriter($proj->{'comments'});
	    print O "NumComments=".$c->{'nlines'}."\n";
	    if ($c->{'nlines'} > 0) {
		print O $c->{'string'}."\n";
	    }
	    print O "TACNote=\n";
	    print O "ScheduleNote=\n";
	    print O "</Slot>\n";
	}
	print O "</Project>\n";
    }
    
    print O "</Program>\n";
    close(O);
}

sub commentWriter($) {
    my $istring = shift;
    # Take a comment string, format it to have only a certain number of
    # characters per line, then return the string and the number of
    # lines.
    my $rval = { 'string' => "", 'nlines' => 0 };
    $istring =~ s/^\s+//g;
    if ($istring eq "") {
	return $rval;
    }
    
    my $max = 70;

    while ($istring) {
	if (length $istring <= $max) {
	    $rval->{'string'} .= $istring;
	    $rval->{'nlines'} += 1;
	    last;
	}
	my $prefix = substr $istring, 0, $max;
	my $loc = rindex $prefix, " ";

	if ($loc == -1) {
	    $rval->{'string'} .= $prefix."-\n";
	    $rval->{'nlines'} += 1;
	} else {
	    my $str = substr $istring, 0, $loc, "";
	    $rval->{'string'} .= $str."\n";
	    $rval->{'nlines'} += 1;
	    substr $istring, 0, 1, "";
	}
    }

    return $rval;
}

sub lstConverter($) {
    my $lststring = shift;

    my @els = split(/\:/, $lststring);
    my $lstsec = $els[0] * 3600;
    if ($#els > 0) {
	$lstsec += $els[1] * 60;
	if ($#els > 1) {
	    $lstsec += $els[2];
	}
    }
    $lstsec *= 1000;

    return $lstsec;
}

sub epoch2timeString($$) {
    my $epoch = shift;
    my $dateonly = shift;

    my $dt = DateTime->from_epoch(epoch => $epoch);
    my $fmt = "%Y/%m/%d";
    if ($dateonly == 0) {
	$fmt .= " %H:%M:%S";
    } else {
	$dt->set_time_zone("Australia/Sydney");
    }
    return $dt->strftime($fmt);
}
