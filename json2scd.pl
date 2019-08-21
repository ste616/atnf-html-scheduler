#!/usr/bin/perl

# Conversion script between JSON and SCD formats.

use Data::Dumper;
use JSON;
use DateTime;
use POSIX;
use strict;

my $json = JSON->new->allow_nonref;

my $infile = $ARGV[0];

my $obs = "";
my $obsName = {
    'ATCA' => "Australia Telescope Compact Array",
    'PK' => "Parkes Radiotelescope"
};

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
    $obs = uc($prog->{'observatory'}->{'observatory'});
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

    # Make the Postscript output.
    my $t = &stringToDatetime($prog->{'term'}->{'start'});
    my $te = &stringToDatetime($prog->{'term'}->{'end'});
    my $dur = $te->epoch() - $t->epoch();
    my $days = 14;
    my $totalDays = $dur / 86400;
    my $numberOfPages = ($totalDays + 1) / $days;
    
    my $outps = $infile;
    $outps =~ s/\.json$/.ps/;
    open(P, ">".$outps) || die "cannot open $outps for writing";
    open(A, "schedulea.ps");
    while(<A>) {
	print P $_;
    }
    close(A);
    print P "/tel (".$obsName->{$obs}.") def\n";
    open(U, "prepage.ps");
    my $preUrl = do { local $/; <U> };
    close(U);
    open(U, "postpage.ps");
    my $postUrl = do { local $/; <U> };
    close(U);

    for (my $i = 0; $i < $numberOfPages; $i++) {
	print P "%%Page: ". ($i + 1)." ".($i + 1)."\n";
	print P $preUrl."\n";
	print P &printps($prog, $i);
	print P $postUrl."\n";
    }
    
    print P "%%EOF\n";
    
    close(P);
}

sub printps($$) {
    my $prog = shift;
    my $pageNumber = shift;

    my $days = 14;
    my $pageLength = $days * 86400;

    my $time1 = &stringToDatetime($prog->{'term'}->{'start'});
    my $d = $time1->day_of_week();
    $time1->subtract( days => (($d + 6) % 7) );

    my $rstring = "";
    # This is the time at the top of the page.
    $time1->add( days => ($pageNumber * $days) );
    # This is the time at the bottom of the page.
    my $time2 = $time1->clone();
    $time2->add( days => $days );

    my $version = $prog->{'term'}->{'version'};
    my $today = DateTime->now;
    $rstring .= "(".($pageNumber + 1).") (".$version.") (".
	$today->dmy("/").") page\n";
    $rstring .= "/dd ".$time1->day." def\n";
    $rstring .= "/mon ".$time1->month." def\n";
    $rstring .= "/year ".$time1->year." def\n";

    my $day1 = 0;
    my $day2 = 0;
    my $config = &getConfig($prog, $time1);
    
    # Cycle through the slots.
    for (my $i = 0; $i <= $#{$prog->{'project'}}; $i++) {
	my $proj = $prog->{'project'}->[$i];
	for (my $j = 0; $j <= $#{$proj->{'slot'}}; $j++) {
	    my $slot = $proj->{'slot'}->[$j];
	    if ($slot->{'scheduled'} == 0) {
		next;
	    }
	    my $slotStart = DateTime->from_epoch(
		epoch => $slot->{'scheduled_start'}
		);
	    $slotStart->add( hours => 10 );
	    my $slotEnd = $slotStart->clone();
	    $slotEnd->add( hours => $slot->{'scheduled_duration'} );
	    if ((($slotStart > $time1) && ($slotStart < $time2))  ||
		(($slotEnd > $time1) && ($slotEnd < $time2))) {
		my $t1 = $slotStart->clone();
		my $t0 = $t1->clone();
		$t0->set( hour => 0, minute => 0, second => 0 );
		if ($t1 < $time1) {
		    $t1 = $time1->clone();
		    $t0 = $time1->clone();
		}
		my $t2 = $t0->clone();
		$t2->add( days => 1 );
		if ($proj->{'ident'} eq "CONFIG") {
		    my $day2 = floor(($t1->epoch - $time1->epoch) / 86400) + 1;
		    if ($day1 != $day2) {
			$rstring .= $day1." ".$day2." (".$config.") config\n";
			$rstring .= &getConfigPS($config);
		    }
		    $config = uc($slot->{'array'});
		    $day1 = $day2;
		}
		while (($t1 < $slotEnd) && ($t1 < $time1)) {
		    $t1 = $t2->clone();
		    $t2->add( days => 1 );
		}
		while (($t2 < $slotEnd) && ($t2 <= $time2)) {
		    $rstring .= &ps_sch_box($proj, $slot, $t1, $t2);
		    $t1 = $t2->clone();
		    $t2->add( days => 1);
		}
		$t2 = $slotEnd->clone();
		if ($t2 <= $time2) {
		    $rstring .= &ps_sch_box($proj, $slot, $t1, $t2);
		}
	    }
	}
    }
    $day2 = 14;
    if ($day1 != $day2) {
	$rstring .= $day1." ".$day2." (".$config.") config\n";
	$rstring .= &getConfigPS($config);
    }
    
    return $rstring;
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

sub stringToDatetime($) {
    my $dstring = shift;

    my @dels = split(/\-/, $dstring);
    my $dt = DateTime->new(
	year => $dels[0], month => $dels[1], day => $dels[2],
	hour => 0, minute => 0, second => 0 );
    return $dt;
}

sub getConfig($$) {
    my $prog = shift;
    my $dt = shift;

    # Find the config at the time.
    my $cfg = "";
    my $cfgdiff = 1e9;
    for (my $i = 0; $i <= $#{$prog->{'project'}}; $i++) {
	if ($prog->{'project'}->[$i]->{'ident'} ne "CONFIG") {
	    next;
	}
	
	for (my $j = 0; $j <= $#{$prog->{'project'}->[$i]->{'slot'}}; $j++) {
	    my $slot = $prog->{'project'}->[$i]->{'slot'}->[$j];
	    if ($slot->{'scheduled_start'} == 0) {
		next;
	    }
	    my $d = $dt->epoch - ($slot->{'scheduled_start'} + 36000);
	    if (($d > 0) && ($d < $cfgdiff)) {
		$cfgdiff = $d;
		$cfg = $slot->{'array'};
	    }
	}
    }

    return uc($cfg);
}

sub getConfigPS($) {
    my $config = shift;
    chomp(my $resline = `grep $config Confign.txt`);
    if ($resline ne "") {
	my @rels = split(/\t/, $resline);
	return "(".$rels[0].") (".$rels[1].") (".$rels[2].") array\n";
    }
    return "% no such array\n";
}

sub ps_sch_box($$$) {
    my $proj = shift;
    my $slot = shift;
    my $t1 = shift;
    my $t2 = shift;
    
    my $rstring = "";

    my $dfh1 = 24 * ($t1->mjd() - floor($t1->mjd()));
    my $dfh2 = 24 * ($t2->mjd() - floor($t1->mjd()));
    my $ddh = $dfh2 - $dfh1;
    
    my $h10 = 0.1 * int(10 * $dfh1 + 0.5);
    my $d10 = 0.1 * int(10 * $ddh + 0.5);
    my $numOfChar = 100;
    if ($d10 > 0.1) {
	my $line = ( ' ' x $numOfChar );
	my $tstring = sprintf "%d %d %d dop %.1f", $t1->day(),
	$t1->month(), $t1->year(), $h10;
	substr($line, 0, length($tstring)) = $tstring;

	$tstring = sprintf "%.1f", $d10;
	substr($line, 22, length($tstring)) = $tstring;
	if ($proj->{'ident'} eq "CONFIG") {
	    if ($obs eq "PK") {
		$tstring = sprintf " (%s) rx_box", $slot->{'source'};
	    } else {
		$tstring = sprintf " (%s) cfg_box", $slot->{'source'};
	    }
	} elsif ($proj->{'ident'} eq "MAINT") {
	    $tstring = " () mnt_box";
	} elsif ($proj->{'ident'} eq "CABB") {
	    $tstring = sprintf " (%s) () () () () () nasa_box", $slot->{'source'};
	} elsif ($proj->{'ident'} eq "BL") {
	    if ($slot->{'source'} =~ /^\!/) {
		my $sstring = $slot->{'source'} =~ s/^\!//;
		$tstring = sprintf " (%s) () () () () () bl_box";
	    } else {
		$tstring = sprintf " (BL) () ((%s)) ((%s)) () (%s) bl_box",
		join(" ", @{$slot->{'bands'}}), $slot->{'bandwidth'},
		$slot->{'source'};
	    }
	} elsif ($proj->{'ident'} =~ /^PX/) {
	    $tstring = sprintf " (%s) ((%s)) ((%s)) ((%s)) () (%s) fast_box",
	    $proj->{'ident'}, $proj->{'PI'}, join(" ", @{$slot->{'bands'}}),
	    $slot->{'bandwidth'}, $slot->{'source'};
	} else {
	    # Check for Legacy projects.
	    my $supp = "";
	    if (($proj->{'ident'} eq "C3132") ||
		($proj->{'ident'} eq "C3145") ||
		($proj->{'ident'} eq "C3152") ||
		($proj->{'ident'} eq "C3157")) {
		$supp = "LEGACY";
	    }
	    $tstring = sprintf " (%s) ((%s)) ((%s)) ((%s)) (%s) (%s) sch_box",
	    $proj->{'ident'}, $proj->{'PI'}, join(" ", @{$slot->{'bands'}}),
	    $slot->{'bandwidth'}, $supp, $slot->{'source'};
	}
	substr($line, 30, length($tstring)) = $tstring;
	$rstring .= $line."\n";
    }
    
    return $rstring."\n";
    
}
