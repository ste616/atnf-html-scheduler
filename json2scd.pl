#!/usr/bin/perl

# Conversion script between JSON and SCD formats.

use Data::Dumper;
use JSON;
use DateTime;
use POSIX;
use strict;

my $json = JSON->new->allow_nonref;

my $infile = $ARGV[0];

my %obsStrings = ( 'name' => "", 'short' => "",
		   'directory' => "", 'full' => "");


# Do something based on the file extension.
if ($infile =~ /\.json$/) {
    # We've been given a JSON, we change to SCD.
    open(J, $infile) || die "Unable to open $infile\n";
    my $jstring = do { local $/; <J> };
    close(J);
    my $jref = $json->decode($jstring);
    my $prog = $jref->{'program'};

    &fillObsStrings($prog);
    
    # Write the SCD file.
    &writeScd($prog);
    
    # Write the PS file.
    &writePostscriptSchedule($prog);
    
    # Write the schedule summary.
    &writeScheduleSummary($prog);

    # Write out a file for the usage stats and the
    # maintenance text file.
    &writeTextSchedules($prog);

    # Write out the HTML summaries.
    &writeHTMLSchedules($prog);

    # Create the graphical schedule pages.
    &writeGraphicalSchedules($prog);

    # Create the JSON schedule output.
    &writeJSONSchedule($prog);
    
    close(P);
}

sub fillObsStrings($) {
    my $prog = shift;

    if (lc($prog->{'observatory'}->{'observatory'}) eq "atca") {
	$obsStrings{'name'} = "ATCA";
	$obsStrings{'short'} = "CA";
	$obsStrings{'directory'} = "atca-".
	    $prog->{'term'}->{'term'};
	$obsStrings{'full'} = "Australia Telescope Compact Array";
    } elsif (lc($prog->{'observatory'}->{'observatory'}) eq "parkes") {
	$obsStrings{'name'} = "Parkes";
	$obsStrings{'short'} = "PK";
	$obsStrings{'directory'} = "parkes-".
	    $prog->{'term'}->{'term'};
	$obsStrings{'full'} = "Parkes Radiotelescope";
    }
    
}

sub outfilePrefix($) {
    my $prog = shift;

    # Generate the output file name prefix.
    my $outfile = sprintf("%s/%s_%sT%d", $obsStrings{'directory'},
			  $obsStrings{'short'}, $prog->{'term'}->{'term'}, 
			  $prog->{'term'}->{'version'});

    # Check if the directory is present.
    if (!-d $obsStrings{'directory'}) {
	system "mkdir ".$obsStrings{'directory'};
    }
    
    return $outfile;
}

sub writeScd($) {
    my $prog = shift;

    my $pfx = &outfilePrefix($prog);
    my $outfile = $pfx.".scd";

    open(O, ">".$outfile) || die "Unable to open $outfile for writing\n";
    print O "<Program>\n";
    print O "<Observatory>\nObservatory=".$obsStrings{'name'}."\n".
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

sub writePostscriptSchedule($) {
    my $prog = shift;

    my $pfx = &outfilePrefix($prog);
    my $outps = $pfx.".ps";

    # Make the Postscript output.
    my $t = &stringToDatetime($prog->{'term'}->{'start'});
    my $te = &stringToDatetime($prog->{'term'}->{'end'});
    my $dur = $te->epoch() - $t->epoch();
    my $days = 14;
    my $totalDays = $dur / 86400;
    my $numberOfPages = ($totalDays + 1) / $days;
    
    open(P, ">".$outps) || die "cannot open $outps for writing";
    open(A, "schedulea.ps");
    while(<A>) {
	print P $_;
    }
    close(A);
    print P "/tel (".$obsStrings{'full'}.") def\n";
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

    # Convert this into PDF.
    my $outpdf = $pfx.".pdf";
    my $mkpdf_cmd = "ps2pdf ".$outps." ".$outpdf;
    system $mkpdf_cmd;
    
}

sub firstMonday($) {
    my $prog = shift;

    my $time1 = &stringToDatetime($prog->{'term'}->{'start'});
    my $d = $time1->day_of_week();
    $time1->subtract( days => (($d + 6) % 7) );

    return $time1;
}

sub printps($$) {
    my $prog = shift;
    my $pageNumber = shift;

    my $days = 14;
    my $pageLength = $days * 86400;
    
    my $time1 = &firstMonday($prog);
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

sub epoch2usage($) {
    my $epoch = shift;
    my $dt = DateTime->from_epoch(epoch => $epoch);
    my $fmt = "%Y-%m-%d %H:%M";
    return $dt->strftime($fmt);
}

sub epoch2maint($) {
    my $epoch = shift;
    my $dt = DateTime->from_epoch(epoch => $epoch);
    my $fmt = "%Y-%m-%d, %H:%M";
    return $dt->strftime($fmt);
}

sub epoch2json($) {
    my $epoch = shift;
    my $dt = DateTime->from_epoch(epoch => $epoch);
    my $fmt = "%Y-%m-%dT%H:%M:%S+00:00";
    return $dt->strftime($fmt);
}

sub epoch2webSplit($) {
    my $epoch = shift;
    my $dt = DateTime->from_epoch(epoch => $epoch);
    my $fmt1 = "%d %b";
    my $fmt2 = "%H:%M";
    return ( $dt->strftime($fmt1), $dt->strftime($fmt2) );
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
	    if ($obsStrings{'short'} eq "PK") {
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

sub alphaSort {

    ($a->{'ident'} cmp $b->{'ident'}) ||
	($a->{'time'} <=> $b->{'time'});
    
}

sub timeSort {

    $a->{'time'} <=> $b->{'time'};

}

sub sortSlots($$) {
    my $prog = shift;
    my $sortAlpha = shift;

    my @dets;
    for (my $i = 0; $i <= $#{$prog->{'project'}}; $i++) {
	my $proj = $prog->{'project'}->[$i];
	for (my $j = 0; $j <= $#{$proj->{'slot'}}; $j++) {
	    my $slot = $proj->{'slot'}->[$j];
	    if ($slot->{'scheduled'} == 1) {
		push @dets, { 'time' => ($slot->{'scheduled_start'} * 1),
			      'ident' => $proj->{'ident'},
			      'proj' => $proj, 'slot' => $slot };
	    }
	}
    }

    my @sdets;
    if ($sortAlpha == 1) {
	@sdets = sort alphaSort @dets;
    } else {
	@sdets = sort timeSort @dets;
    }

    return @sdets;
}

sub format_int($) {
    my $a = shift;
    my $aa = floor($a);
    my $ad = $a - $aa;
    my $b = reverse $aa;
    my @c = unpack("(A3)*", $b);
    my $d = reverse join ',', @c;
    my $df = "";
    if ($ad > 0) {
	$df = sprintf "%.1f", $ad;
	$df =~ s/^0//;
    }
    return $d.$df;
}

sub writeScheduleSummary($) {
    my $prog = shift;

    my $pfx = &outfilePrefix($prog);
    my $outfile = $pfx.".txt";

    my @details_lines;
    my @sorted_slots = &sortSlots($prog, 1);
    my $astroTime = 0;
    my $configTime = 0;
    my $maintTime = 0;
    for (my $i = 0; $i <= $#sorted_slots; $i++) {
	my $proj = $sorted_slots[$i]->{'proj'};
	my $slot = $sorted_slots[$i]->{'slot'};
	my $dt = DateTime->from_epoch(
	    epoch => $slot->{'scheduled_start'}
	    );
	my $dstring = sprintf("%-5.1f", $slot->{'scheduled_duration'});
	$dstring =~ s/\.0//;
	# The output needs to be in AEST.
	my $sline =
	    sprintf("%-9s %19s  -  %19s   %-5s %-91s",
		    $proj->{'ident'},
		    &epoch2timeString($slot->{'scheduled_start'} +
				      (10 * 3600)),
		    &epoch2timeString($slot->{'scheduled_start'} +
				      ($slot->{'scheduled_duration'} *
				       3600) + (10 * 3600)),
		    $dstring, &getConfig($prog, $dt));
	push @details_lines, $sline;
	if ($proj->{'type'} eq "ASTRO") {
	    $astroTime += $slot->{'scheduled_duration'};
	} elsif ($proj->{'ident'} eq "CONFIG") {
	    $configTime += $slot->{'scheduled_duration'};
	} elsif ($proj->{'type'} eq "MAINT") {
	    $maintTime += $slot->{'scheduled_duration'};
	}
    }

    open(O, ">".$outfile) || die "Unable to open $outfile for writing\n";
    print O $obsStrings{'full'}."\n\n";
    printf O ("Summary of %sT%d\n", $prog->{'term'}->{'term'},
	      $prog->{'term'}->{'version'});
    printf O ("%s 00:00:00 to %s 00:00:00\n\n",
	      $prog->{'term'}->{'start'}, $prog->{'term'}->{'end'});

    my $startTime = &stringToDatetime($prog->{'term'}->{'start'});
    my $endTime = &stringToDatetime($prog->{'term'}->{'end'});
    my $semesterDuration = ($endTime->epoch() - $startTime->epoch()) / 3600;
    printf O ("%-13s %s hours\n", "Term length", 
	      &format_int($semesterDuration));
    my $astroFrac = 100 * ($astroTime / $semesterDuration);
    printf O ("%-13s %s   (%.1f%%)\n", "Astronomy",
	      &format_int($astroTime), $astroFrac);
    my $configFrac = 100 * ($configTime / $semesterDuration);
    printf O ("%-13s %s   (%.1f%%)\n", "Reconfigs",
	      &format_int($configTime), $configFrac);
    my $maintFrac = 100 * ($maintTime / $semesterDuration);
    printf O ("%-13s %s   (%.1f%%)\n", "Maintenance",
	      &format_int($maintTime), $maintFrac);
    my $unallocTime = $semesterDuration - ($astroTime + $configTime +
					   $maintTime);
    my $unallocFrac = 100 * ($unallocTime / $semesterDuration);
    printf O ("%-13s %s   (%.1f%%)\n", "Unallocated",
	      &format_int($unallocTime), $unallocFrac);
    
    print O "\n\n\n\nDetails:\n\n";
    for (my $i = 0; $i <= $#details_lines; $i++) {
	print O $details_lines[$i]."\n";
    }
    close(O);
}

sub writeTextSchedules($) {
    my $prog = shift;

    my $usage_file = sprintf "%s/schedule.txt", $obsStrings{'directory'};
    my $maint_file = sprintf("%s/%s_maint.txt", $obsStrings{'directory'},
			     lc($obsStrings{'name'}));
    my @sorted_slots = &sortSlots($prog, 0);
    open(O, ">".$usage_file) || die "Unable to open $usage_file for writing\n";
    open(M, ">".$maint_file) || die "Unable to open $maint_file for writing\n";
    my $ctime = &stringToDatetime($prog->{'term'}->{'start'})->subtract(
	hours => 10 );
    my $config = &getConfig($prog, $ctime);
    for (my $i = 0; $i <= $#sorted_slots; $i++) {
	my $proj = $sorted_slots[$i]->{'proj'};
	my $slot = $sorted_slots[$i]->{'slot'};
	# Output is in UTC.
	if ($ctime->epoch() < $slot->{'scheduled_start'}) {
	    # Directors time.
	    printf O "%16s Directors time\n", &epoch2usage($ctime->epoch());
	    printf M ("%17s, %17s, Directors time, %s\n",
		      &epoch2maint($ctime->epoch()),
		      &epoch2maint($slot->{'scheduled_start'}),
		      $config);
	    $ctime = DateTime->from_epoch( 
		epoch => $slot->{'scheduled_start'});
	}
	if (($proj->{'type'} eq "MAINT") ||
	    ($proj->{'type'} eq "CONFIG") ||
	    ($proj->{'ident'} eq "CABB")) {
	    printf O "%16s Maintenance/test\n",
	    &epoch2usage($slot->{'scheduled_start'});
	    if ($proj->{'ident'} eq "CONFIG") {
		$config = uc($slot->{'array'});
		printf M ("%17s, %17s, Reconfigure #%d/Calibration, %s\n",
			  &epoch2maint($slot->{'scheduled_start'}),
			  &epoch2maint($slot->{'scheduled_start'} +
				       ($slot->{'scheduled_duration'} * 3600)),
			  $slot->{'source'}, $config);
	    } else {
		printf M ("%17s, %17s, Maintenance/test, %s\n",
			  &epoch2maint($slot->{'scheduled_start'}),
			  &epoch2maint($slot->{'scheduled_start'} +
				       ($slot->{'scheduled_duration'} * 3600)),
			  $config);
	    }
	} else {
	    printf O ("%16s %s\n", &epoch2usage($slot->{'scheduled_start'}),
		      $proj->{'ident'});
	    printf M ("%17s, %17s, %s, %s\n",
		      &epoch2maint($slot->{'scheduled_start'}),
		      &epoch2maint($slot->{'scheduled_start'} +
				   ($slot->{'scheduled_duration'} * 3600)),
		      $proj->{'ident'}, $config);
	}
	$ctime = DateTime->from_epoch(
	    epoch => ($slot->{'scheduled_start'} + 
		      ($slot->{'scheduled_duration'} * 3600)));
    }
    my $etime = &stringToDatetime($prog->{'term'}->{'end'})->subtract(
	hours => 10 );
    if ($ctime->epoch() < $etime->epoch()) {
	# Directors time until the end.
	printf O "%16s Directors time\n", &epoch2usage($ctime->epoch());
	printf M ("%17s, %17s, Directors time, %s\n",
		  &epoch2maint($ctime->epoch()),
		  &epoch2maint($etime->epoch()),
		  $config);
    }
    close(O);
    close(M);
}

sub writeHTMLSchedules($) {
    my $prog = shift;

    my @sorted_slots = &sortSlots($prog, 1);
    my $aestSummaryFile = sprintf("%s/%s-summaryAEST.html",
				  $obsStrings{'directory'},
				  lc($obsStrings{'name'}));
    my $utcSummaryFile = sprintf("%s/%s-summaryUT.html",
				 $obsStrings{'directory'},
				 lc($obsStrings{'name'}));
    open(A, ">".$aestSummaryFile) || die "Unable to open $aestSummaryFile ".
	"for writing\n";
    open(U, ">".$utcSummaryFile) || die "Unable to open $utcSummaryFile ".
	"for writing\n";

    # Print out the preamble.
    my $prelines = '<!DOCTYPE html>'.
	'<html><head><meta http-equiv="Content-Type" '.
	'content="text/html; charset=iso-8859-1">';
    print A $prelines;
    print U $prelines;
    my $tformat = "<%s>%s schedule summary for %s (%s)</%s>";
    printf A ($tformat, "title", $obsStrings{'name'}, 
	      $prog->{'term'}->{'term'}, "AEST", "title");
    printf U ($tformat, "title", $obsStrings{'name'}, 
	      $prog->{'term'}->{'term'}, "UT", "title");
    $prelines = '<?php include( $_SERVER[DOCUMENT_ROOT] . "'.
	'/includes/standard_head.inc" ) ?>'.
	'<style>#tt th { border: 2px solid black; padding: 0.4em; }'.
	'#tt td { border: 2px solid black; padding: 0.4em; }'.
	'</style></head><body><!-- content -->'.
	'<?php include( $_SERVER[DOCUMENT_ROOT] . "'.
	'/includes/title_bar_atnf.inc" ) ?><center>';
    print A $prelines;
    print U $prelines;
    printf A ($tformat, "h1", $obsStrings{'name'}, 
	      $prog->{'term'}->{'term'}, "AEST", "h1");
    printf U ($tformat, "h1", $obsStrings{'name'}, 
	      $prog->{'term'}->{'term'}, "UT", "h1");
    $prelines = '</center><br clear="all"><br><br>&nbsp;<br>'.
	'<center><table id="tt" border="1" cellspacing="0"'.
	'cellpadding="2" cols="6" width="98%">'.
	'<tr><th valign="top" width="10%">Project<br>Code</th>'.
	'<th valign="top" width="25%">PI</th>';
    print A $prelines;
    print U $prelines;
    $tformat = '<th valign="top" width="10%">%s Dates</th>'.
	'<th valid="top" width="10%">%s Start time</th>';
    printf A ($tformat, "AEST", "AEST");
    printf U ($tformat, "UT", "UT");
    $prelines = '<th valign="top" width="10%">Duration (hrs)</th>'.
	'<th nowrap valign="top" width="35%">Title</th></tr>';
    print A $prelines;
    print U $prelines;
    
    my $ident = "";
    my $rowStart;
    my $rowEnd;
    my $dateCellAEST;
    my $timeCellAEST;
    my $durationCell;
    my $dateCellUT;
    my $timeCellUT;
    my $totalHours;
    for (my $i = 0; $i <= ($#sorted_slots + 1); $i++) {
	my $slot;
	my $proj;
	if ($i <= $#sorted_slots) {
	    $slot = $sorted_slots[$i]->{'slot'};
	    $proj = $sorted_slots[$i]->{'proj'};
	}
	if (($i > $#sorted_slots) || ($proj->{'ident'} ne $ident)) {
	    # We have to end the previous row and start a new one.
	    if ($ident ne "") {
		$dateCellAEST .= "Total</td>";
		$timeCellAEST .= "</td>";
		$durationCell .= sprintf("%.1f</td>", $totalHours);
		print A $rowStart.$dateCellAEST.$timeCellAEST.
		    $durationCell.$rowEnd;
		$dateCellUT .= "Total</td>";
		$timeCellUT .= "</td>";
		print U $rowStart.$dateCellUT.$timeCellUT.
		    $durationCell.$rowEnd;
	    }
	    if ($i <= $#sorted_slots) {
		$totalHours = 0;
		$rowStart = sprintf('<tr><td valign="top">%s</td>'.
				    '<td valign="top">%s<br></td>',
				    $proj->{'ident'}, $proj->{'PI'});
		$rowEnd = sprintf('<td valign="top">%s</td></tr>',
				  $proj->{'title'});
		$dateCellAEST = '<td nowrap valign="top">';
		$timeCellAEST = '<td nowrap valign="top" align="center">';
		$dateCellUT = '<td nowrap valign="top">';
		$timeCellUT = '<td nowrap valign="top" align="center">';
		$durationCell = '<td nowrap valign="top" align="right">';
		$ident = $proj->{'ident'};
	    } else {
		last;
	    }
	}
	# Add some info to the cells.
	$totalHours += $slot->{'scheduled_duration'} * 1;
	my @dateCompsUT = &epoch2webSplit($slot->{'scheduled_start'});
	my @dateCompsAEST = &epoch2webSplit($slot->{'scheduled_start'} +
					    (10 * 3600));
	$dateCellAEST .= $dateCompsAEST[0]."<br>";
	$timeCellAEST .= $dateCompsAEST[1]."<br>";
	$dateCellUT .= $dateCompsUT[0]."<br>";
	$timeCellUT .= $dateCompsUT[1]."<br>";
	$durationCell .= sprintf("%.1f<br>", 
				 ($slot->{'scheduled_duration'} * 1));
    }

    my $gentime = DateTime->now->strftime("%d-%b-%Y");
    my $postlines = '</table></center><br><p><br>'.
	'<hr noshade><address>Generated: Jamie Stevens ('.
	$gentime.')</address></div></article>'.
	'<!-- footer --><footer><div class="wrap">'.
	'<a href="https://www.atnf.csiro.au/contact/">Contact us</a>'.
	'&nbsp;|&nbsp;'.
	'<a href="https://www.atnf.csiro.au/internal/">Intranet</a>'.
	'&nbsp;|&nbsp;'.
	'<a href="https://www.csiro.au/en/About">About CSIRO</a>'.
	'&nbsp;|&nbsp;'.
	'<a href="https://www.csiro.au/en/About/Footer/Copyright">Copyright</a>'.
	'&nbsp;|&nbsp;'.
	'<a href="https://www.csiro.au/en/About/Footer/Legal-notice">'.
	'Legal Notice and Disclaimer</a>&nbsp;|&nbsp;'.
	'<a href="https://www.csiro.au/en/About/Access-to-information/'.
	'Privacy">Privacy</a></div></footer></div></html>';
    print A $postlines;
    print U $postlines;
    
    close(A);
    close(U);
}

sub writeGraphicalSchedules($) {
    my $prog = shift;

    # Start by converting the PS to the PNGS.
    my $pfx = &outfilePrefix($prog);
    my $psfile = $pfx.".ps";

    my $imwidth = 848;
    my $imheight = 1102;
    my $jdir = "/tmp/junk".$obsStrings{'name'};
    if (-d $jdir) {
	system "rm -rf $jdir";
    }
    system "mkdir $jdir";

    # Make and crop all the PNGs.
    my $pngfile_pfx = $obsStrings{'short'};
    my $convcmd = "/usr/bin/convert -background white -alpha off ".
	"-density 300 -resize ".$imwidth."x".$imheight." -scene 1 ".
	$psfile." ".$jdir."/".$pngfile_pfx."%03d.png";
    system $convcmd;
    my @bigpng = glob "'${jdir}/${pngfile_pfx}*.png'";
    my $ndir = $obsStrings{'directory'};
    for (my $i = 0; $i <= $#bigpng; $i++) {
	my $opng = $bigpng[$i];
	$opng =~ s/$jdir/$ndir/;
	my $cropcmd = "/usr/bin/convert -crop 674x1008+65+25 ".
	    $bigpng[$i]." ".$opng;
	system $cropcmd;
    }

    # Work out the start Monday.
    my $semdate = &firstMonday($prog);

    my @png = glob "'${ndir}/${pngfile_pfx}*.png'";
    #my @monthnames = ( "", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    #		       "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" );
    my @start_dates;
    my @end_dates;
    for (my $i = 0; $i <= $#png; $i++) {
	# Work out the date range of this page.
	push @start_dates, $semdate->strftime("%d %b");
	$semdate->add(days => 13);
	push @end_dates, $semdate->strftime("%d %b");
	$semdate->add(days => 1);
    }
    for (my $i = 0; $i <= $#png; $i++) {
	# Create the web page.
	my $hpage = $png[$i];
	$hpage =~ s/png$/html/;
	open(O, ">".$hpage) || die "Cannot open $hpage for writing\n";
	print O "<!DOCTYPE html>\n<html><head><title>Schedule ".
	    $prog->{'term'}->{'term'}."</title>\n";
	print O "<?php include( \$_SERVER['DOCUMENT_ROOT'] .".
	    "\"/includes/standard_head.inc\" ) ?>\n";
	print O "<style>#scheduletable { ".
	    "border: 0; margin: 0px auto; width: 100%; }\n";
	print O ".currpage { border: 3px solid blue; ".
	    "background: blue; color: white; font-size: 20px; ".
	    "line-height: 26px; font-family: monospace; ".
	    "font-weight: bold;  }\n";
	print O "#fortnighttable { border: 0; border-collapse: collapse; }\n";
	print O "#fortnighttable a, #fortnighttable a:visited { ".
	    "font-weight: bold; text-decoration: none; color: black; ".
	    "font-size: 20px; line-height: 26px; font-family: monospace; }\n";
	print O "#fortnighttable td.nondate a, #fortnighttable ".
	    "td.nondate:visited { font-weight: bold; text-decoration: none; ".
	    "color: green; font-size: 16px; line-height: 20px; ".
	    "font-family: Arial; }\n";
	print O "#scheduletable td { padding: 0; text-align: center; ".
	    "vertical-align: top; }\n";
	print O "#fortnighttable td { padding: 0.2em 0; }\n";
	print O "</style></head>\n";
	print O "<body>\n";
        print O "<?php include( \$_SERVER['DOCUMENT_ROOT'] . ".
	    "\"/includes/title_bar_atnf.inc\" ) ?>\n";
	print O "<table id=\"scheduletable\"><tr><td>";
	print O "<table id=\"fortnighttable\"><tr><td><h1>".
	    $prog->{'term'}->{'term'}." ".
	    $obsStrings{'name'}."</h1></td></tr>";
	for (my $j = 0; $j <= $#start_dates; $j++) {
	    my $lpage = $png[$j];
	    $lpage =~ s/png$/html/;
	    $lpage =~ s/^.*\/(.*)$/$1/;
	    my $cname = "";
	    my $stype = "<a href=\"".$lpage."\">";
	    my $etype = "</a>";
	    if ($j == $i) {
		$cname = " class=\"currpage\"";
		$stype = "";
		$etype = "";
	    }
	    print O "<tr><td$cname>$stype".$start_dates[$j]." - ".
		$end_dates[$j]."$etype</td></tr>\n";
	}
	print O "<tr><td class=\"nondate\"><a href=\"".
	    lc($obsStrings{'name'})."-summaryUT.html\">".
	    "Schedule Summary</a></td></tr>\n";
	print O "<tr><td class=\"nondate\">".
	    "<a href=\"/observing/schedules/\">Back to Schedule Index</a>".
	    "</td></tr>\n";
	print O "</table></td>";
	my $sdpng = $png[$i];
	$sdpng =~ s/^.*\/(.*)$/$1/;
	print O "<td><img src=\"".$sdpng."\"></td></tr>\n";
	print O "</table>\n";
        print O "<p><hr><address>Last Modified: Jamie Stevens ".
	    `date +"(%d-%b-%Y)"`."</address></body></html>\n";
	print O "<?php include( \$_SERVER['DOCUMENT_ROOT'] . \"".
	    "/includes/footer.inc\" ) ?>\n";

	close(O);

	system "chmod u+x $hpage";
    }
    
}

sub writeJSONSchedule($) {
    my $prog = shift;

    my $json_file = sprintf ("%s/%s_maint.json", $obsStrings{'directory'},
			     lc($obsStrings{'name'}));
    my @sorted_slots = &sortSlots($prog, 0);

    my @json_maint;
    my $ctime = &stringToDatetime($prog->{'term'}->{'start'})->subtract(
	hours => 10 );
    my $config = &getConfig($prog, $ctime);
    for (my $i = 0; $i <= $#sorted_slots; $i++) {
	my $proj = $sorted_slots[$i]->{'proj'};
	my $slot = $sorted_slots[$i]->{'slot'};
	# Output is in UTC.
	if ($ctime->epoch() < $slot->{'scheduled_start'}) {
	    # Directors time.
	    push @json_maint, {
		'schedID' => 0, 'title' => "Green Time",
		'start' => &epoch2json($ctime->epoch()),
		'end' => &epoch2json($slot->{'scheduled_start'}),
		'array' => $config, 
		'term' => $prog->{'term'}->{'term'},
		'className' => "Green Time",
		'pi' => "N/A", 'expert' => "N/A",
		'napas' => "N/A", 'source' => "N/A",
		'receivers' => "N/A", 'cabb' => "N/A"
	    };
	    $ctime = DateTime->from_epoch(
		epoch => $slot->{'scheduled_start'});
	}
	my $jobj = { 
	    'schedID' => 0, 'title' => $proj->{'ident'},
	    'start' => &epoch2json($slot->{'scheduled_start'}),
	    'end' => &epoch2json($slot->{'scheduled_start'} +
				 ($slot->{'scheduled_duration'} * 3600)),
	    'array' => $config, 'term' => $prog->{'term'}->{'term'},
	    'className' => "Schedule", 'pi' => $proj->{'PI'},
	    'expert' => "N/A", 'napas' => "None",
	    'source' => "N/A", 'receivers' => "N/A",
	    'cabb' => "N/A"
	};
	if ($proj->{'type'} eq "MAINT") {
	    # Maintenance time.
	    $jobj->{'title'} = "Maintenance";
	    $jobj->{'className'} = "Maintenance";
	} elsif ($proj->{'type'} eq "CONFIG") {
	    $config = uc($slot->{'array'});
	    $jobj->{'title'} = "Reconfig";
	    $jobj->{'className'} = "Reconfig";
	    $jobj->{'array'} = $config;
	} elsif ($proj->{'ident'} eq "CABB") {
	    $jobj->{'title'} = "CABB";
	    $jobj->{'className'} = "Special";
	} else {
	    # Regular project.
	    $jobj->{'source'} = $slot->{'source'};
	    $jobj->{'cabb'} = $slot->{'bandwidth'};
	    my @bands = @{$slot->{'bands'}};
	    $jobj->{'receivers'} = join(",", @bands);
	}
	push @json_maint, $jobj;
	$ctime = DateTime->from_epoch(
	    epoch => ($slot->{'scheduled_start'} +
		      ($slot->{'scheduled_duration'} * 3600)));
    }
    my $etime = &stringToDatetime($prog->{'term'}->{'end'})->subtract(
	hours => 10 );
    if ($ctime->epoch() < $etime->epoch()) {
	# Directors time until the end.
	push @json_maint, {
	    'schedID' => 0, 'title' => "Green Time",
	    'start' => &epoch2json($ctime->epoch()),
	    'end' => &epoch2json($etime->epoch()),
	    'array' => $config,
	    'term' => $prog->{'term'}->{'term'},
	    'className' => "Green Time",
	    'pi' => "N/A", 'expert' => "N/A",
	    'napas' => "N/A", 'source' => "N/A",
	    'receivers' => "N/A", 'cabb' => "N/A"
	};
    }
    # Make the JSON string.
    open(O, ">".$json_file) || die "Unable to open $json_file for writing\n";
    printf O "%s\n", $json->pretty->encode(\@json_maint);
    close(O);
    
}
