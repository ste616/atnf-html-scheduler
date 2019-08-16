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
	    if (($proj->{'excluded_dates'} ne "") &&
		($proj->{'excluded_dates'} ne "N/A")) {
		my @ed = @{$proj->{'excluded_dates'}};
		for (my $k = 0; $k <= $#ed; $k++) {
		    my $es = &epoch2timeString($ed[$k], 0);
		    push @edStrings, $es."-".$es;
		}
	    }
	    print O "ExcludedDates=".join(", ", @edStrings)."\n";
	    print O "</Slot>\n";
	}
	print O "</Project>\n";
    }
    
    print O "</Program>\n";
    close(O);
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
    }
    return $dt->strftime($fmt);
}
