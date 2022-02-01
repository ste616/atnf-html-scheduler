#!/usr/bin/perl

# Conversion script between JSON and SCD formats.

use Data::Dumper;
use JSON;
use DateTime;
use POSIX;
use Astro::Time;
use strict;

my $json = JSON->new->allow_nonref;

my $infile = $ARGV[0];

my %obsStrings = ( 'name' => "", 'short' => "",
		   'directory' => "", 'full' => "");

# Set some default colours.
my %colours = (
    'default' => "cdcdcd",
    'unscheduled' => "9ae68d",
    'MAINT' => "cdcdff",
    'CONFIG' => "ffff8d",
    'CABB' => "ffcdcd",
    'NASA' => "ffcdcd",
    'BL' => "ffcdff",
    'FAST' => "ffc000",
    'outside' => "ffcdcd"
    );


# Do something based on the file extension.
if ($infile =~ /\.json$/) {
    # We've been given a JSON, we change to SCD.
    open(J, $infile) || die "Unable to open $infile\n";
    my $jstring = do { local $/; <J> };
    close(J);
    my $jref = $json->decode($jstring);
    my $prog = $jref->{'program'};

    &fillObsStrings($prog);

    # Sort the slots.
    &slotSorter($prog);
    
    # Write the SCD file.
    #print " SCD output\n";
    &writeScd($prog);
    
    # Write the PS file.
    #print " postscript output\n";
    &writePostscriptSchedule($prog);
    
    # Write the schedule summary.
    #print " schedule summary\n";
    &writeScheduleSummary($prog);

    # Write out a file for the usage stats and the
    # maintenance text file.
    #print " text schedules\n";
    &writeTextSchedules($prog);

    # Write out the HTML summaries.
    #print " HTML schedules\n";
    &writeHTMLSchedules($prog);

    # Create the graphical schedule pages.
    &writeGraphicalSchedules($prog);

    # Create the JSON schedule output.
    &writeJSONSchedule($prog);

    # Create the file that goes back into OPAL.
    &writeOPALFile($prog);

    # Write out statistics for the Annual Report.
    &writeStatistics($prog);
    
    close(P);
} elsif ($infile =~ /\.scd$/) {
    # We've been given an SCD file, we change to JSON.
    open(S, $infile) || die "Unable to open SCD $infile\n";
    my @slines;
    while(<S>) {
	chomp(my $line = $_);
	push @slines, $line;
    }
    # Get the modification time of the file.
    my @fstats = stat(S);
    close(S);
    
    # Convert this file to the requisite Perl structure.
    my $jref = &parseScd($fstats[9], \@slines);

    # Write out the file.
    my $ofile = $infile;
    $ofile =~ s/\.scd$/.json/;
    open(O, ">".$ofile) || die "Unable to open $ofile for writing\n";
    printf O "%s\n", $json->pretty->encode($jref);
    close(O);
    
}

sub slotSorter($) {
    my $prog = shift;

    for (my $i = 0; $i <= $#{$prog->{'project'}}; $i++) {
	if ($prog->{'project'}->[$i]->{'ident'} eq "CONFIG") {
	    my @slots = @{$prog->{'project'}->[$i]->{'slot'}};
	    my @sslots = sort { $a->{'scheduled_start'} <=> $b->{'scheduled_start'} } @slots;
	    $prog->{'project'}->[$i]->{'slot'} = \@sslots;
	}
    }
}

sub parseScd($$) {
    my $mtime = shift;
    my $slines = shift;

    # The return value.
    my %jobj = (
	'program' => {
	    'observatory' => { 'observatory' => "none" },
	    'colours' => { 'default' => $colours{'default'},
			   'unscheduled' => $colours{'unscheduled'},
			   'outsideSemester' => $colours{'outside'} },
	    'term' => { 'term' => "none", 'version' => 1,
			'configs' => [],
			'start' => "none",
			"end" => "none" },
	    'special' => { 'lastReconfigNumber' => 0 },
	    'project' => []
	}, 'modificationTime' => $mtime
	);
    # Some metadata variables we'll need later.
    # For the project.
    my ($pcode, $ptype, $pi_name, $comments, $other, $title, $impossible,
	$preferred, $clines);
    # For the slot.
    my ($sarrays, $sbands, $sbandwidths, $ssources, $spositions,
	$sscores, $slststart, $slstend, $slstused,
	$sstarttime, $sscheduledduration, $srequestedduration, $sscheduled);
    my @allslots;
    # For config list.
    my @allconfigs;
    my $earlyconfig = "";
    my $earlyconfig_epoch = 0;
    my $isconfig = 0;
    
    # Start going through the SCD.
    for (my $i = 0; $i <= $#{$slines}; $i++) {
	if ($slines->[$i] =~ /^Observatory\=(.*)$/) {
	    # The name of the observatory.
	    $jobj{'program'}->{'observatory'}->{'observatory'} = lc($1);
	} elsif ($slines->[$i] =~ /^Term\=(.*)$/) {
	    my $tname = $1;
	    $tname =~ s/^(.*)T\d+$/$1/;
	    $jobj{'program'}->{'term'}->{'term'} = $tname;
	} elsif ($slines->[$i] =~ /^Start\=(.*?)\s.*$/) {
	    $jobj{'program'}->{'term'}->{'start'} = $1;
	} elsif ($slines->[$i] =~ /^End\=(.*?)\s.*$/) {
	    $jobj{'program'}->{'term'}->{'end'} = $1;
	} elsif ($slines->[$i] =~ /Version\=(\d+)$/) {
	    $jobj{'program'}->{'term'}->{'version'} = $1 * 1;
	} elsif ($slines->[$i] eq "<Project>") {
	    # We have found a new project.
	    $pcode = "";
	    $ptype = "";
	    $pi_name = "";
	    $comments = "";
	    $other = "";
	    $title = "";
	    $impossible = "";
	    $preferred = "";
	    $clines = 0;
	    @allslots = ();
	} elsif ($slines->[$i] eq "</Project>") {
	    $isconfig = 0;
	    # Create the project.
	    my @pslots = @allslots;
	    my $aref =  {
		'ident' => $pcode, 'type' => $ptype,
		'PI' => $pi_name, 'comments' => $comments,
		'title' => $title, 'excluded_dates' => $impossible,
		'preferred_dates' => $preferred,
		'prefers_night' => 0, 'slot' => \@pslots
	    };
	    if (defined $colours{$pcode}) {
		$aref->{'colour'} = $colours{$pcode};
	    } elsif ($pcode =~ /^PX/) {
		$aref->{'colour'} = $colours{'FAST'};
	    } else {
		$aref->{'colour'} = $colours{'default'};
	    }
	    push @{$jobj{'program'}->{'project'}}, $aref;
	} elsif ($slines->[$i] =~ /^Ident\=(.*)$/) {
	    $pcode = $1;
	    if ($pcode eq "CONFIG") {
		$isconfig = 1;
	    }
	} elsif ($slines->[$i] =~ /^PI\=(.*)$/) {
	    $pi_name = $1;
	} elsif ($slines->[$i] =~ /^Type\=(.*)$/) {
	    $ptype = $1;
	} elsif ($slines->[$i] =~ /^NumComments\=(\d+)$/) {
	    $clines = $1 * 1;
	} elsif ($clines > 0) {
	    $comments .= $slines->[$i];
	    $clines--;
	} elsif ($slines->[$i] =~ /^Title\=(.*)$/) {
	    $title = $1;
	} elsif ($slines->[$i] eq "<Slot>") {
	    # We have found a new slot.
	    $sarrays = "";
	    $sbands = [];
	    $sbandwidths = "";
	    $ssources = "";
	    $spositions = { 'ra' => "", 'dec' => "" };
	    $sstarttime = 0;
	    $sscores = 0.0;
	    $slststart = "00:00";
	    $slstend = "23:59";
	    $slstused = 0;
	    $sstarttime = 0;
	    $sscheduledduration = 0;
	    $srequestedduration = 0;
	    $sscheduled = 0;
	} elsif ($slines->[$i] eq "</Slot>") {
	    # Create the slot.
	    push @allslots, {
		'array' => $sarrays, 'bands' => $sbands,
		'bandwidth' => $sbandwidths, 'source' => $ssources,
		'position' => $spositions, 
		'requested_duration' => $srequestedduration,
		'scheduled_duration' => $sscheduledduration,
		'scheduled_start' => $sstarttime,
		'scheduled' => $sscheduled,
		'rating' => $sscores,
		'lst_limits_used' => $slstused,
		'lst_start' => $slststart, 'lst_end' => $slstend
	    };
	    if ($isconfig == 1) {
		push @allconfigs, $sarrays;;
		if (($sscheduled == 1) && (($sstarttime < $earlyconfig_epoch) ||
					   ($earlyconfig_epoch == 0))) {
		    $earlyconfig_epoch = $sstarttime;
		    $earlyconfig = $sarrays;
		}
	    }
	} elsif ($slines->[$i] =~ /^Array\=(.*)$/) {
	    $sarrays = $1;
	} elsif ($slines->[$i] =~ /^Bands\=(.*)$/) {
	    my @bands = split(/[\,\/]/, $1);
	    $sbands = \@bands;
	} elsif ($slines->[$i] =~ /^Bandwidths\=(.*)$/) {
	    $sbandwidths = $1;
	} elsif ($slines->[$i] =~ /^Source\=(.*)$/) {
	    $ssources = $1;
	} elsif ($slines->[$i] =~ /^RA\=(.*)$/) {
	    $spositions->{'ra'} = $1;
	} elsif ($slines->[$i] =~ /^Dec\=(.*)$/) {
	    $spositions->{'dec'} = $1;
	} elsif ($slines->[$i] =~ /^Rating\=(.*)$/) {
	    my $r = $1;
	    if ($r eq "X") {
		$sscores = 5.0;
	    } else {
		$sscores = $r * 1.0;
	    }
	} elsif ($slines->[$i] =~ /^SidTimStart\=(.*)$/) {
	    $slststart = &lst2string($1);
	} elsif ($slines->[$i] =~ /^SidTimEnd\=(.*)$/) {
	    $slstend = &lst2string($1);
	} elsif ($slines->[$i] =~ /^LSTLimitsUsed\=(.*)$/) {
	    $slstused = ($1 eq "true") ? 1 : 0;
	} elsif ($slines->[$i] =~ /^Start1\=(.*)$/) {
	    my $st = &scdStringToDatetime($1);
	    $sstarttime = $st->epoch();
	} elsif ($slines->[$i] =~ /^SchDuration1\=(.*)$/) {
	    $sscheduledduration = $1 / 3600000.0;
	} elsif ($slines->[$i] =~ /^ReqDuration\=(.*)$/) {
	    $srequestedduration = $1 / 3600000.0;
	} elsif ($slines->[$i] =~ /^Scheduled\=(.*)$/) {
	    $sscheduled = ($1 eq "true") ? 1 : 0;
	}
    }

    # Work out the configs.
    push @{$jobj{'program'}->{'term'}->{'configs'}}, $earlyconfig;
    for (my $i = 0; $i <= $#allconfigs; $i++) {
	my $on = 0;
	for (my $j = 0; $j <= $#{$jobj{'program'}->{'term'}->{'configs'}}; $j++) {
	    if ($allconfigs[$i] eq $jobj{'program'}->{'term'}->{'configs'}->[$j]) {
		$on = 1;
		last;
	    }
	}
	if ($on == 0) {
	    push @{$jobj{'program'}->{'term'}->{'configs'}}, $allconfigs[$i];
	}
    }
    
    return \%jobj;
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
	$obsStrings{'full'} = "Murriyang, the CSIRO Parkes Radiotelescope";
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
	#print "  SCD writer: project ".$proj->{'ident'}."\n";
	print O "<Project>\n";
	print O "Ident=".$proj->{'ident'}."\n";
	print O "Title=".$proj->{'title'}."\n";
	print O "PI=".$proj->{'PI'}."\n";
	print O "Type=".$proj->{'type'}."\n";
	print O "Polarimetry=false\nMosaic=false\nPulsarBinning=false\n";
	print O "Comments=0\n";
	for (my $j = 0; $j <= $#{$proj->{'slot'}}; $j++) {
	    my $slot = $proj->{'slot'}->[$j];
	    #print "   SCD writer: slot ".$j."\n";
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
	    #print "   SCD writer: scheduled at ".$ss."\n";
	    print O "Start1=".$ss."\n";
	    print O "Start2=2000/01/02 00:00:00\n";
	    print O "Scheduled=".$isscheduled."\n";
	    print O "Locked=false\n";
	    my $c = &commentWriter($proj->{'comments'});
	    #print "   SCD writer: comment written\n";
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
	#print "page $i\n";
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

sub splitintodays($$) {
    my $slotStart = shift;
    my $slotEnd = shift;
    my $time1 = shift;
    my $time2 = shift;
    my $proj = shift;
    my $slot = shift;
    my $day1 = shift;
    my $day2 = shift;
    my $rstring = shift;
    my $config = shift;
    
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
	$config =~ s/\s+/ /g;
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
    return ($day1, $day2, $rstring, $config);
}

sub printps($$) {
    my $prog = shift;
    my $pageNumber = shift;

    my $days = 14;
    my $pageLength = $days * 86400;
    
    my $time1 = &firstMonday($prog);
    #print $time1."\n";
    my $rstring = "";
    # This is the time at the top of the page.
    $time1->add( days => ($pageNumber * $days) );
    # This is the time at the bottom of the page.
    my $time2 = $time1->clone();
    $time2->add( days => $days );
    #print $time2."\n";

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

    # Check if we make a "Previous" or "Next" semester block.
    my $semstart = &stringToDatetime($prog->{'term'}->{'start'});
    #print $semstart."\n";
    if ($time1 < $semstart) {
	#print " making previous semester block\n";
	($day1, $day2, $rstring, $config) = &splitintodays(
	    $time1, $semstart, $time1, $time2, 
	    { 'ident' => "prevsem", 'type' => "MAINT",
	      'title' => "Previous Semester", 'colour' => "ffcdcd" }, {},
	    $day1, $day2, $rstring, $config);
    }
    
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
		(($slotEnd > $time1) && ($slotEnd < $time2)) ||
		## This next one is when a project goes for a whole
		## fortnight, starting before the page, and ending after.
		(($slotStart < $time1) && ($slotEnd > $time2))) {
		($day1, $day2, $rstring, $config) = &splitintodays(
		    $slotStart, $slotEnd, $time1, $time2, $proj, $slot, 
		    $day1, $day2, $rstring, $config);
	    }
	}
    }
    my $semend = &stringToDatetime($prog->{'term'}->{'end'});
    #print $semend."\n";
    if ($time2 > $semend) {
	#print " making next semester block\n";
	($day1, $day2, $rstring, $config) = &splitintodays(
	    $semend, $time2, $time1, $time2,
	    { 'ident' => "nextsem", 'type' => "MAINT",
	      'title' => "Next Semester", 'colour' => "ffcdcd" }, {},
	    $day1, $day2, $rstring, $config);
    }

    
    $day2 = 14;
    if ($day1 != $day2) {
	#print " getting config $config\n";
	$rstring .= $day1." ".$day2." (".$config.") config\n";
	$rstring .= &getConfigPS($config);
    }

    
    #print $rstring."\n";
    return $rstring;
}

sub commentWriter($) {
    my $istring = shift;
    # Take a comment string, format it to have only a certain number of
    # characters per line, then return the string and the number of
    # lines.
    my $rval = { 'string' => "", 'nlines' => 0 };
    $istring =~ s/^\s+//g;
    $istring =~ s/[^[:ascii:]]//g;
    if ($istring eq "") {
	return $rval;
    }
    
    my $max = 70;

    while ($istring) {
	#print "    Comment writer: ".$istring." length = ".(length $istring)."\n";
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

sub lst2string($) {
    my $lstms = shift;

    my $lstd = $lstms / 86400000.0;
    my $lsth = floor($lstd * 24.0);
    my $lstm = floor(($lstd * 24.0 - $lsth) * 60);
    my $lsts = sprintf("%02d:%02d", $lsth, $lstm);

    return $lsts;
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

sub epoch2lst($) {
    my $epoch = shift;
    my $dt = DateTime->from_epoch(epoch => $epoch);
    my $mjd = $dt->mjd();
    my $long = 0;
    if ($obsStrings{'name'} eq "ATCA") {
	$long = (149.5501388 / 360);
    } elsif ($obsStrings{'name'} eq "Parkes") {
	$long = (148.2635101 / 360);
    }
    my $lst = 24 * mjd2lst($mjd, $long);
    my $lst_h = floor($lst);
    my $lst_m = floor(($lst - $lst_h) * 60);
    my $lstString = sprintf("%02d:%02d", $lst_h, $lst_m);

    return $lstString;
}

sub stringToDatetime($) {
    my $dstring = shift;

    my @dels = split(/\-/, $dstring);
    my $dt = DateTime->new(
	year => $dels[0], month => $dels[1], day => $dels[2],
	hour => 0, minute => 0, second => 0 );
    return $dt;
}

sub scdStringToDatetime($) {
    my $dstring = shift;

    my @dels = split(/[\/\s\:]/, $dstring);
    my $dt = DateTime->new(
	year => $dels[0], month => $dels[1], day => $dels[2],
	hour => $dels[3], minute => $dels[4], second => $dels[5] );
    return $dt;
}

sub getConfig($$) {
    my $prog = shift;
    my $dt = shift;

    # Find the config at the time.
    my $cfg = "";
    my $fcfg = "";
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
	    #print " checking array ".$slot->{'array'}." starting at ";
	    #print $slot->{'scheduled_start'}." (".$dt->epoch.")\n";
	    if ($fcfg eq "") {
		$fcfg = $slot->{'array'};
	    }
	    my $d = $dt->epoch - ($slot->{'scheduled_start'} + 36000);
	    if (($d > 0) && ($d < $cfgdiff)) {
		$cfgdiff = $d;
		$cfg = $slot->{'array'};
	    }
	}
    }

    #print " returning config $cfg\n";
    if ($cfg eq "") {
	$cfg = $fcfg;
    }
    $cfg =~ s/\s+/ /g;
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

sub bracketise_string($) {
    my $s = shift;

    if ($s eq "") {
	return $s;
    }
    return "(".$s.")";
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
	    my $sstring = $slot->{'source'};
	    if ($slot->{'source'} =~ /^\!/) {
		$sstring =~ s/^\!//;
	    }
	    $tstring = sprintf " (%s) () () () () () nasa_box", $sstring;
	} elsif ($proj->{'ident'} eq "BL") {
	    if ($slot->{'source'} =~ /^\!/) {
		my $sstring = $slot->{'source'} =~ s/^\!//;
		$tstring = sprintf " (%s) () () () () () bl_box", $sstring;
	    } else {
		$tstring = sprintf " (BL) () ((%s)) ((%s)) () (%s) bl_box",
		join(" ", @{$slot->{'bands'}}), $slot->{'bandwidth'},
		$slot->{'source'};
	    }
	} elsif ($proj->{'ident'} =~ /^PX/) {
	    # Don't put brackets around empty strings.
	    my $band_string = &bracketise_string(join(" ", @{$slot->{'bands'}}));
	    my $bandwidth_string = &bracketise_string($slot->{'bandwidth'});
	    $tstring = sprintf " (%s) ((%s)) (%s) (%s) () (%s) fast_box",
	    $proj->{'ident'}, $proj->{'PI'}, $band_string, $bandwidth_string,
	    $slot->{'source'};
	} elsif (($proj->{'type'} eq "MAINT") ||
		 (($proj->{'type'} eq "ASTRO") &&
		  (defined $proj->{'colour'}))) {
	    # Use the colour in the schedule.
	    my ($r, $g, $b);
	    $r = (hex "0x".substr($proj->{'colour'}, 0, 2)) / 255.;
	    $g = (hex "0x".substr($proj->{'colour'}, 2, 2)) / 255.;
	    $b = (hex "0x".substr($proj->{'colour'}, 4, 2)) / 255.;
	    # What should the title be.
	    my $stitle = $proj->{'title'};
	    if ($proj->{'type'} eq "ASTRO") {
		$stitle = $proj->{'ident'};
	    }
	    if (defined $slot && defined $slot->{'source'} &&
		$slot->{'source'} =~ /^\!/) {
		$stitle = substr($slot->{'source'}, 1);
	    }
	    if ($proj->{'type'} eq "MAINT") {
		$tstring = sprintf " (%s) (%s) (%s) %.1f %.1f %.1f colnopi_box",
		    $stitle, substr($stitle, 0, 5), substr($stitle, 0, 5),
		    $r, $g, $b;
	    } elsif ($proj->{'type'} eq "ASTRO") {
		my $band_string = &bracketise_string(join(" ", @{$slot->{'bands'}}));
		my $bandwidth_string = &bracketise_string($slot->{'bandwidth'});
		$tstring = sprintf " (%s) ((%s)) (%s) (%s) (%s) (%s) %.1f %.1f %.1f colsch_box",
		    $proj->{'ident'}, $proj->{'PI'}, $band_string, $bandwidth_string,
		    "", $slot->{'source'}, $r, $g, $b;
	    }
	} else {
	    # Check for Legacy projects.
	    my $supp = "";
	    if (($proj->{'ident'} eq "C3132") ||
		($proj->{'ident'} eq "C3145") ||
		($proj->{'ident'} eq "C3152") ||
		($proj->{'ident'} eq "C3157")) {
		$supp = "LEGACY";
	    }
	    my $band_string = &bracketise_string(join(" ", @{$slot->{'bands'}}));
	    my $bandwidth_string = &bracketise_string($slot->{'bandwidth'});
	    $tstring = sprintf " (%s) ((%s)) (%s) (%s) (%s) (%s) sch_box",
	    $proj->{'ident'}, $proj->{'PI'}, $band_string, $bandwidth_string,
	    $supp, $slot->{'source'};
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
    my $includeNAPA = shift;
    if (!defined $includeNAPA) {
	$includeNAPA = 0;
    }

    my @dets;
    for (my $i = 0; $i <= $#{$prog->{'project'}}; $i++) {
	my $proj = $prog->{'project'}->[$i];
	my $isnapa = 0;
	if ($proj->{'title'} =~ /^NAPA/) {
	    $isnapa = 1;
	}
	my $nscheduled = 0;
	for (my $j = 0; $j <= $#{$proj->{'slot'}}; $j++) {
	    my $slot = $proj->{'slot'}->[$j];
	    if ($slot->{'scheduled'} == 1) {
		push @dets, { 'time' => ($slot->{'scheduled_start'} * 1),
			      'ident' => $proj->{'ident'}, 'isNAPA' => $isnapa,
			      'proj' => $proj, 'slot' => $slot };
	    }
	}
	if ($isnapa && ($nscheduled == 0) && $includeNAPA) {
	    push @dets, { 'time' => 0, 'ident' => $proj->{'ident'},
			  'isNAPA' => $isnapa, 'proj' => $proj,
			  'slot' => $proj->{'slot'}->[0] };
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

sub writeStatistics($) {
    my $prog = shift;

    my $statsFile = sprintf("%s/%s-statistics.txt",
			    $obsStrings{'directory'},
			    lc($obsStrings{'name'}));
    open(S, ">".$statsFile) || die "Unable to open $statsFile ".
	"for writing\n";

    my $auditFile = sprintf("%s/%s-statistics-audit.txt",
			    $obsStrings{'directory'},
			    lc($obsStrings{'name'}));
    open(A, ">".$auditFile) || die "Unable to open $auditFile ".
	"for writing\n";
    
    # Assemble the statistics.
    my $pi_allocation_cass = 0;
    my $pi_allocation_aus = 0;
    my $pi_allocation_os = 0;
    my $all_allocation_cass = 0;
    my $all_allocation_aus = 0;
    my $all_allocation_os = 0;

    my @sorted_slots = &sortSlots($prog, 1);
    
    for (my $i = 0; $i <= $#sorted_slots; $i++) {
	my $slot = $sorted_slots[$i]->{'slot'};
	my $proj = $sorted_slots[$i]->{'proj'};
	if (($proj->{"type"} ne "ASTRO") ||
	    ($proj->{"ident"} eq "VLBI") ||
	    ($proj->{"ident"} eq "BL") ||
	    ($proj->{"ident"} =~ /^PX50[01]/)) {
	    next;
	}
	my $num_investigators = ($#{$proj->{'co_investigators'}} + 2);
	printf A (" Project %s, number of investigators = %d, time allocated = %.2f h\n", 
		  $proj->{'ident'}, $num_investigators, $slot->{'scheduled_duration'});
	#print $proj->{'ident'}." ".$proj->{"PI_affiliation"}." ".$proj->{"PI_country"}."\n";
	printf A ("  PI %s ", $proj->{'PI'});
	if (($proj->{"PI_affiliation"} eq "CASS") ||
	    ($proj->{"PI_affiliation"} eq "ATNF")) {
	    #print "  ATNF\n";
	    printf A ("affiliation CASS/ATNF\n");
	    $pi_allocation_cass += $slot->{'scheduled_duration'} * 1;
	    $all_allocation_cass += $slot->{'scheduled_duration'} / $num_investigators;
	} elsif ($proj->{"PI_country"} eq "Australia") {
	    #print "  Aus\n";
	    printf A ("affiliation Australian\n");
	    $pi_allocation_aus += $slot->{'scheduled_duration'} * 1;
	    $all_allocation_aus += $slot->{'scheduled_duration'} / $num_investigators;
	} else {
	    #print "  OS\n";
	    printf A ("affiliation O/S\n");
	    $pi_allocation_os += $slot->{'scheduled_duration'} * 1;
	    $all_allocation_os += $slot->{'scheduled_duration'} / $num_investigators;
	}
	for (my $j = 0; $j<= $#{$proj->{'co_investigators'}}; $j++) {
	    printf A ("     coI %s ", $proj->{'co_investigators'}->[$j]);
	    if (($proj->{"coI_affiliations"}->[$j] eq "CASS") ||
		($proj->{"coI_affiliations"}->[$j] eq "ATNF")) {
		printf A ("affiliation CASS/ATNF\n");
		$all_allocation_cass += $slot->{'scheduled_duration'} / $num_investigators;
	    } elsif ($proj->{"coI_countries"}->[$j] eq "Australia") {
		printf A ("affiliation Australian\n");
		$all_allocation_aus += $slot->{'scheduled_duration'} / $num_investigators;
	    } else {
		printf A ("affiliation O/S\n");
		$all_allocation_os += $slot->{'scheduled_duration'} / $num_investigators;
	    }
	}
	printf A (" PI time now:\n");
	printf A ("    CASS: %.2f  Aus: %.2f  O/S: %.2f\n",
		  $pi_allocation_cass, $pi_allocation_aus, $pi_allocation_os);
	printf A (" All time now:\n");
	printf A ("    CASS: %.2f  Aus: %.2f  O/S: %.2f\n\n\n",
		  $all_allocation_cass, $all_allocation_aus, $all_allocation_os);
    }

    # Write it out.
    print S "Time allocation by PI (%):\n";
    printf A ("Total times PI = %.2f\n", ($pi_allocation_cass + $pi_allocation_aus +
					      $pi_allocation_os));
    printf S ("CASS/ATNF = %.2f\n", (100.0 * ($pi_allocation_cass / 
					      ($pi_allocation_cass + $pi_allocation_aus +
					       $pi_allocation_os))));
    printf S ("Other Aus = %.2f\n", (100.0 * ($pi_allocation_aus / 
					      ($pi_allocation_cass + $pi_allocation_aus +
					       $pi_allocation_os))));
    printf S ("O/S = %.2f\n", (100.0 * ($pi_allocation_os / 
					($pi_allocation_cass + $pi_allocation_aus +
					 $pi_allocation_os))));
    print S "Time allocation by all users (%):\n";
    printf A ("Total times all = %.2f\n", ($all_allocation_cass + $all_allocation_aus +
					   $all_allocation_os));
    printf S ("CASS/ATNF = %.2f\n", (100.0 * ($all_allocation_cass /
					      ($all_allocation_cass + $all_allocation_aus +
					       $all_allocation_os))));
    printf S ("Other Aus = %.2f\n", (100.0 * ($all_allocation_aus /
					      ($all_allocation_cass + $all_allocation_aus +
					       $all_allocation_os))));
    printf S ("O/S = %.2f\n", (100.0 * ($all_allocation_os /
					($all_allocation_cass + $all_allocation_aus +
					 $all_allocation_os))));
    
    close(S);
    close(A);
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
    # We also make a HTML file.
    my $special_html = sprintf("%s/%s_observing_schedule.html", $obsStrings{'directory'},
			       lc($obsStrings{'name'}));
    my @sorted_slots = &sortSlots($prog, 0);
    open(O, ">".$usage_file) || die "Unable to open $usage_file for writing\n";
    open(M, ">".$maint_file) || die "Unable to open $maint_file for writing\n";
    open(H, ">".$special_html) || die "Unable to open $special_html for writing\n";

    # Put the preamble in the HTML.
    printf H ("<html><head><title>%s Observing Schedule</title></head>".
	      "<body bgcolor = \"#FFFFFF\">\n", $obsStrings{'name'});
    print H "<img src=\"/images/obs_schedule_header.gif\">\n";
    print H "<hr><center>\n";
    print H "<p><b><font color=blue size=5>Please Note: </font></b>All times in this schedule\n";
    print H "are in <b>Australian Eastern Standard Time</b>.\n";
    ## TODO: make this automatic.
    print H "<br>Daylight Saving will \n";
    printf H ("<p>This is version %d of the current schedule</p>\n", 
	      $prog->{'term'}->{'version'});
    my $mnth = substr($prog->{'term'}->{'term'}, 3, 3);
    if ($mnth eq "OCT") {
	$mnth = "October";
    } else {
	$mnth = "April";
    }
    printf H ("<table border><caption><font color=red><h2>%s Semester %d</h2>".
	      "</font></caption>\n", $mnth, substr($prog->{'term'}->{'term'}, 0, 4));
    print H "<tr align=center><td><b>Date</b></td><td><b>Day</b></td>\n";
    print H "<td><b>Local Time (AEST) / Proposal</b></td><td><b>LST</b></td><td><b>\n";
    print H "Observers</b></td><td><b>Friend</b></td>\n";
    print H "<td><b>Receiver</b></td></tr>\n";

    my $ctime = &stringToDatetime($prog->{'term'}->{'start'})->subtract(
	hours => 10 );
    my $config = &getConfig($prog, $ctime);
    my @sphtml_lines;
    for (my $i = 0; $i <= $#sorted_slots; $i++) {
	my $proj = $sorted_slots[$i]->{'proj'};
	my $slot = $sorted_slots[$i]->{'slot'};
	# Output is in UTC, except for the HTML in AEST.
	if ($ctime->epoch() < $slot->{'scheduled_start'}) {
	    # Directors time.
	    printf O "%16s Directors time\n", &epoch2usage($ctime->epoch());
	    printf M ("%17s, %17s, Directors time, %s\n",
		      &epoch2maint($ctime->epoch()),
		      &epoch2maint($slot->{'scheduled_start'}),
		      $config);
	    push @sphtml_lines, &slotToDayEntries(
		$ctime->epoch(),
		$slot->{'scheduled_start'},
		"<b>Director's Time                </b>",
		".", ".", ".");
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
		if (lc($obsStrings{'name'}) eq "parkes") {
		    push @sphtml_lines, &slotToDayEntries(
			$slot->{'scheduled_start'},
			$slot->{'scheduled_start'} + ($slot->{'scheduled_duration'} * 3600),
			"<b>Receiver Change (".$slot->{'array'}." in)                    </b>",
			".", ".", ".");
		} else {
		    push @sphtml_lines, &slotToDayEntries(
			$slot->{'scheduled_start'},
			$slot->{'scheduled_start'} + ($slot->{'scheduled_duration'} * 3600),
			"<b>Reconfiguration into ".$slot->{'array'}."</b>",
			".", ".", ".");
		}
	    } else {
		my $smtext = "Maintenance/test";
		if ($slot->{'source'} =~ /^\!/) {
		    $smtext = substr($slot->{'source'}, 1);
		}
		printf M ("%17s, %17s, %s, %s\n",
			  &epoch2maint($slot->{'scheduled_start'}),
			  &epoch2maint($slot->{'scheduled_start'} +
				       ($slot->{'scheduled_duration'} * 3600)),
			  $smtext, $config);
		my @edate = &epoch2webSplit($slot->{'scheduled_start'} + (10 * 3600) +
					    $slot->{'scheduled_duration'} * 3600);
		my $sptext = "Maintenance";
		if ($slot->{'source'} =~ /^\!/) {
		    $sptext = substr($slot->{'source'}, 1);
		}
		push @sphtml_lines, &slotToDayEntries(
		    $slot->{'scheduled_start'},
		    $slot->{'scheduled_start'} + ($slot->{'scheduled_duration'} * 3600),
		    "<b>".$sptext."                   </b>",
		    ".", ".", ".");
	    }
	} else {
	    printf O ("%16s %s\n", &epoch2usage($slot->{'scheduled_start'}),
		      $proj->{'ident'});
	    printf M ("%17s, %17s, %s, %s\n",
		      &epoch2maint($slot->{'scheduled_start'}),
		      &epoch2maint($slot->{'scheduled_start'} +
				   ($slot->{'scheduled_duration'} * 3600)),
		      $proj->{'ident'}, $config);
	    my $pstring = ($proj->{'ident'} eq "BL") ?
		"<b>BL</b>" : "<b>".$proj->{'ident'}." </b>".$proj->{'title'}."(".$proj->{'PI'}.")";
	    my $astring = (ref($slot->{'array'}) eq "ARRAY") ?
		uc(join(" ", @{$slot->{'array'}})) : uc($slot->{'array'});
	    push @sphtml_lines, &slotToDayEntries(
		$slot->{'scheduled_start'},
		$slot->{'scheduled_start'} + ($slot->{'scheduled_duration'} * 3600),
		$pstring,
		$proj->{'PI'}."...",
		"<a href=\"/observing/schedules/friends.html\">ops-team".
		"                                                                        </a>",
		$astring);
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
	push @sphtml_lines, &slotToDayEntries(
	    $ctime->epoch(),
	    $etime->epoch(),
	    "<b>Director's Time                </b>",
	    ".", ".", ".");
    }

    my $cdate = "";
    my $cday = "";
    my $cproj = "";
    my $clst = "";
    my $cobs = "";
    my $cfriend = "";
    my $creceiver = "";
    for (my $i = 0; $i <= $#sphtml_lines; $i++) {
	for (my $j = 0; $j <= $#{$sphtml_lines[$i]->{'dates'}}; $j++) {
	    if ($sphtml_lines[$i]->{'dates'}->[$j] ne $cdate) {
		if ($cdate ne "") {
		    printf H ("<tr valign=middle><td nowrap><font size=2>%s</font></td>".
			      "<td nowrap><font size=2>%s</font></td>\n",
			      $cdate, $cday);
		    printf H ("<td nowrap><font size=2>\n%s</font></td>\n", $cproj);
		    printf H ("<td nowrap><font size=2>\n%s</font></td>\n", $clst);
		    printf H ("<td nowrap><font size=2>\n%s</font></td>\n", $cobs);
		    printf H ("<td nowrap><font size=2>\n%s</font></td>\n", $cfriend);
		    printf H ("<td nowrap><font size=2>\n%s</font></td>\n", $creceiver);
		    print H "</tr>\n";
		}
		$cdate = $sphtml_lines[$i]->{'dates'}->[$j];
		$cday = $sphtml_lines[$i]->{'days'}->[$j];
		$cproj = $sphtml_lines[$i]->{'times'}->[$j];
		$clst = $sphtml_lines[$i]->{'lsts'}->[$j];
		$cobs = $sphtml_lines[$i]->{'observers'}->[$j];
		$cfriend = $sphtml_lines[$i]->{'friends'}->[$j];
		$creceiver = $sphtml_lines[$i]->{'receivers'}->[$j];
	    } else {
		$cproj .= sprintf("<br>\n%s", $sphtml_lines[$i]->{'times'}->[$j]);
		$clst .= sprintf("<br>\n%s", $sphtml_lines[$i]->{'lsts'}->[$j]);
		$cobs .= sprintf("<br>\n%s", $sphtml_lines[$i]->{'observers'}->[$j]);
		$cfriend .= sprintf("<br>\n%s", $sphtml_lines[$i]->{'friends'}->[$j]);
		$creceiver .= sprintf("<br>\n%s", $sphtml_lines[$i]->{'receivers'}->[$j]);
	    }
	}
    }
    
    # Close the HTML file.
    # Close out the row.
    #printf H ("<tr valign=middle><td nowrap><font size=2>%s</font></td>".
    #	      "<td nowrap><font size=2>%s</font></td>\n",
    #	      $cdate, $cday);
    #printf H ("<td nowrap><font size=2>\n%s</font></td>\n", $cproj);
    #printf H ("<td nowrap><font size=2>\n%s</font></td>\n", $clst);
    #printf H ("<td nowrap><font size=2>\n%s</font></td>\n", $cobs);
    #printf H ("<td nowrap><font size=2>\n%s</font></td>\n", $cfriend);
    #printf H ("<td nowrap><font size=2>\n%s</font></td>\n", $creceiver);
    #print H "</tr>\n";
    print H "</table></center><hr><p>\n";
    print H "<p><i>Enquiries to <a href=\"&#109;&#97;&#105;&#108;&#116;&#111;&#58;&#115;p&#0105;".
	"&#100;&#101;&#114;&#064;&#097;&#116;&#110;&#102;&#46;&#099;&#115;&#0105;&#114;&#0111;".
	"&#046;&#097;&#0117;\">WebMaster</a></i><hr></body></html>\n";
    
    close(O);
    close(M);
    close(H);
}

sub slotToDayEntries($$$$$$) {
    my $stime = shift;
    my $etime = shift;
    my $projstring = shift;
    my $obsstring = shift;
    my $friendstring = shift;
    my $receiverstring = shift;

    # Our return value.
    my $rv = { 'dates' => [], 'days' => [], 'lsts' => [],
	       'times' => [], 'observers' => [],
	       'friends' => [], 'receivers' => [] };
    
    # Start and end times.
    my $st = DateTime->from_epoch(epoch => $stime + (10 * 3600));
    my $et = DateTime->from_epoch(epoch => $etime + (10 * 3600));
    my $sjt = DateTime->from_epoch(epoch => $stime);
    my $ejt = DateTime->from_epoch(epoch => $etime);
    my $addt = 0;
    for (my $i = floor($st->mjd()), $addt = 0; $i <= floor($et->mjd()); $i++, $addt += 24) {
	my $ct = DateTime->from_epoch(epoch => $stime + (($addt + 10) * 3600));
	my $cep = $stime + ($addt * 3600);
	my $ststring;
	my $slstring;
	my $etstring;
	my $elstring;
	if ($addt == 0) {
	    # Starting day.
	    $ststring = $st->strftime("%H:%M");
	    $slstring = &epoch2lst($stime);
	} else {
	    # Starting at the day transition.
	    $ststring = "00:00";
	    my $cdf = $ct->hour() * 3600 + $ct->minute() * 60 + $ct->second();
	    $slstring = &epoch2lst($cep - $cdf);
	}
	if ($ct->doy() == $et->doy()) {
	    # We end today.
	    $etstring = $et->strftime("%H:%M");
	    $elstring = &epoch2lst($etime);
	} else {
	    # End at the day transition.
	    $etstring = "24:00";
	    my $cdf = $ct->hour() * 3600 + $ct->minute() * 60 + $ct->second();
	    $elstring = &epoch2lst($cep + (86400 - $cdf));
	}
	if ($ststring ne $etstring) {
	    push @{$rv->{'dates'}}, $ct->strftime("%d %b");
	    push @{$rv->{'days'}}, $ct->strftime("%a");
	    push @{$rv->{'times'}}, sprintf("%s - %s %s",
					    $ststring, $etstring, $projstring);
	    push @{$rv->{'lsts'}}, sprintf("%s - %s", $slstring, $elstring);
	    push @{$rv->{'observers'}}, $obsstring;
	    push @{$rv->{'friends'}}, $friendstring;
	    push @{$rv->{'receivers'}}, $receiverstring;
	}
    }
    return $rv;
}

sub writeHTMLSchedules($) {
    my $prog = shift;

    my @sorted_slots = &sortSlots($prog, 1, 1);
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
	'<th valign="top" width="25%">Investigators</th>';
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
		my $coIlist = $proj->{'co_investigators'};
		if (!defined $coIlist) {
		    $coIlist = [];
		}
		my $napaQual = "";
		if ($sorted_slots[$i]->{'isNAPA'} == 1) {
		    $napaQual = " (NAPA)";
		}
		$rowStart = sprintf('<tr><td valign="top">%s%s</td>'.
				    '<td valign="top">%s<br><em>%s</em><br></td>',
				    $proj->{'ident'}, $napaQual,
				    $proj->{'PI'}, join(", ", @{$coIlist}));
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
	if ($slot->{'scheduled_start'} > 0) {
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
    my $rrs_file = sprintf ("%s/override_grades_%s.json", $obsStrings{'directory'},
			    $prog->{'term'}->{'term'});
    my @sorted_slots = &sortSlots($prog, 0);

    my @json_maint;
    my %json_override;
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
		'startLST' => &epoch2lst($ctime->epoch()),
		'endLST' => &epoch2lst($slot->{'scheduled_start'}),
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
	    'startLST' => &epoch2lst($slot->{'scheduled_start'}),
	    'endLST' => &epoch2lst($slot->{'scheduled_start'} +
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
	    'startLST' => &epoch2lst($ctime->epoch()),
	    'endLST' => &epoch2lst($etime->epoch()),
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

    for (my $i = 0; $i <= $#{$prog->{'project'}}; $i++) {
	my $proj = $prog->{'project'}->[$i];
	my $pr = { "emails" => [ $proj->{'PI_email'} ],
		   "slots" => [], "score" => -1 };
	if (defined $proj->{'coI_emails'}) {
	    push @{$pr->{'emails'}}, @{$proj->{'coI_emails'}};
	}
	for (my $j = 0; $j <= $#{$proj->{'slot'}}; $j++) {
	    my $slot = $proj->{'slot'}->[$j];
	    if ($slot->{'rating'} > $pr->{'score'}) {
		$pr->{'score'} = $slot->{'rating'};
	    }
	    if ($slot->{'scheduled'} == 1) {
		push @{$pr->{'slots'}}, { 'start_epoch' => $slot->{'scheduled_start'} * 1,
					  'end_epoch' => ($slot->{'scheduled_start'} +
							  $slot->{'scheduled_duration'} * 3600) };
	    }
	}
	$json_override{$proj->{'ident'}} = $pr;
    }
    # Make the JSON string.
    open(O, ">".$rrs_file) || die "Unable to open $rrs_file for writing\n";
    printf O "%s\n", $json->pretty->encode(\%json_override);
    close(O);
}

sub codeSort {
    if (($a =~ /^\D+(\d+)$/) &&
	($b =~ /^\D+(\d+)$/)) {
	my $na = $a =~ s/^\D+(\d+)$/$1/r;
	my $nb = $b =~ s/^\D+(\d+)$/$1/r;
	if ($na < $nb) {
	    return -1;
	} elsif ($na == $nb) {
	    return 0;
	} else {
	    return 1;
	}
    } else {
	if ($a =~ /^\D+(\d+)$/) {
	    return 1;
	} elsif ($b =~ /^\D+(\d+)$/) {
	    return -1;
	} else {
	    return $a cmp $b;
	}
    }
}

sub writeOPALFile($) {
    my $prog = shift;

    my %codes;
    
    for (my $i = 0; $i <= $#{$prog->{'project'}}; $i++) {
	my $proj = $prog->{'project'}->[$i];
	my $ident = $proj->{'ident'};
	if ($proj->{'type'} ne "ASTRO") {
	    next;
	}
	$codes{$ident} = { 'time' => 0, 'napa' => 0, 
			   'title' => $proj->{'title'}, 'pi' => $proj->{'PI'} };
	if ($proj->{'title'} =~ /^NAPA/) {
	    $codes{$ident}->{'napa'} = 1;
	}
	for (my $j = 0; $j <= $#{$proj->{'slot'}}; $j++) {
	    my $slot = $proj->{'slot'}->[$j];
	    $codes{$ident}->{'time'} += $slot->{'scheduled_duration'};
	}
    }

    my @p = keys %codes;
    my @sp = sort codeSort @p;
    my $sem = $prog->{'term'}->{'term'}."S";

    my $opalfile = sprintf("%s/%s-opal.csv", $obsStrings{'directory'},
			   lc($obsStrings{'name'}));
    my $legendfile = sprintf("%s/%s_%s_summary.html", $obsStrings{'directory'},
			     lc($prog->{'observatory'}->{'observatory'}),
			     lc($prog->{'term'}->{'term'}));
    open(O, ">".$opalfile) || die "Unable to open $opalfile for writing\n";
    open(L, ">".$legendfile) || die "Unable to open $legendfile for writing\n";
    printf L ("<!DOCTYPE html>\n<html>\n<head><title>%s Proposal Summary</title></head>\n",
	      $prog->{'term'}->{'term'});
    printf L ("<body>\n<h2>%s Observing Schedule Proposals Legend</h2>\n",
	      $prog->{'term'}->{'term'});
    print L "<center><table border=\"0\" cellspacing=\"2\" cellpadding=\"2\">\n";
    print L "<tr><th>Project Ident</th><th>Project Description (Principal Investigator)</th></tr>\n";
    
    for (my $i = 0; $i <= $#sp; $i++) {
	my $y = 0;
	if (($codes{$sp[$i]}->{'time'} > 0) ||
	    ($codes{$sp[$i]}->{'napa'} == 1)) {
	    $y = 1;
	}
	printf O ("\"%s\",\"%s\",\"%.1f\",\"%d\"\n",
		  $sem, $sp[$i], $codes{$sp[$i]}->{'time'}, $y);
	if ($y == 1) {
	    printf L ("<tr><td align=\"center\">%s</td><td>%s (%s)</td></tr>\n",
		      $sp[$i], $codes{$sp[$i]}->{'title'},
		      $codes{$sp[$i]}->{'pi'});
	} 
    }

    print L "</table></center><p></p></body></html>\n";
    
    close(O);
    close(L);
}
