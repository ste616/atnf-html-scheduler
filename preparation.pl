#!/usr/bin/perl

use URI;
use Web::Scraper;
use Encode;
use DateTime;
#use JSON::Simple;
use Getopt::Long;
use XML::Simple;
use String::ShellQuote;
use Astro::Coord;
use Astro::Time;
use POSIX;
use strict;

# This script does all the necessary preparatory work for the semester.

# Get the arguments.
my $sem = "";
my $proposal_zip = "";
my $map_file = "";
my $clean = "";
GetOptions(
    "semester=s" => \$sem,
    "zip=s" => \$proposal_zip,
    "map=s" => \$map_file,
    "clean" => \$clean
    ) or die "Error in command line arguments.\n";

$sem = lc($sem); # Should look like 2019OCT
my $semname = uc($sem);
print "== Preparing for semester $semname\n";

# Step 1: make the directories.
&makeMasterDirectory($sem, $clean);

# Step 2: download the OPAL files.
printf "== Downloading proposals from OPAL...\n";
&getProposalArchive($sem, $proposal_zip);
## TODO

# Step 3: extract the proposals.
&extractProposalArchive($sem);

# Step 4. download the proposal mapping file.
my $mapfile = &downloadProposalMapping($sem, $map_file);
## TODO

# Step 5. rename each proposal as required.
&renameProposals($sem);

# Step 6. prepare the summary file.
# Get the public holidays.
my %publicHolidays = &getPublicHolidays();
# Get the semester start and end dates.
my $semesterDetails = &semesterDateRange($sem);
printf "II Semester runs from %s to %s (%d days)\n", 
    $semesterDetails->{"startString"},
    $semesterDetails->{"endString"},
    $semesterDetails->{"nDays"};
# Work out which holidays are in the semester.
my $semesterHolidays = &restrictDates($semesterDetails,
				      \%publicHolidays);
my @hkeys = keys %{$semesterHolidays};
printf "II %d holidays found in semester:\n", ($#hkeys + 1);
for (my $i = 0; $i <= $#hkeys; $i++) {
    printf "II holiday %d: %s\n", ($i + 1), $hkeys[$i];
}

### SUBROUTINES FOLLOW
### SHOULD ALL BE MOVED TO ANOTHER MODULE AT SOME POINT

sub makeMasterDirectory($$) {
    my $semdir = shift;
    my $clean = shift;

    printf "== Checking for directory %s... ", $semdir;
    my $makeit = 1;
    if (-d $semdir) {
	print "already exists.\n";
	$makeit = 0;
	if ($clean == 1) {
	    printf "== Directory cleaning required.\n";
	    system "rm -rf $semdir";
	    $makeit = 2;
	}
    }
    if ($makeit >= 1) {
	system "mkdir ".$semdir;
	if (-d $semdir) {
	    if ($makeit == 2) {
		print "II Directory made successfully.\n";
	    } else {
		print "directory made.\n";
	    }
	} else {
	    if ($makeit == 2) {
		print "!! Could not make directory.\n";
	    } else {
		print "failed!\n";
	    }
	    exit;
	}
    }
    return;
}

sub getProposalArchive($$) {
    my $semdir = shift;
    my $propfile = shift;

    my $outfile = sprintf "%s/%sS-proposals.zip", $semdir, uc($semdir);
    
    # If we've been given the name of a file, we copy it in.
    if (($propfile ne "") && (-e $propfile)) {
	printf "== Copying proposal zip file %s to %s ...", $propfile, $outfile;
	system "cp \"".$propfile."\" ".$outfile;
	if (-e $outfile) {
	    print " success.\n";
	} else {
	    print " failed.\n";
	    exit;
	}
    } else {
	# We don't support this yet.
	printf "!! Unable to get proposals from OPAL, development required.\n";
	exit;
    }
}

sub extractProposalArchive($) {
    my $semdir = shift;
    my $semdname = uc($semdir);
    
    printf "== Extracting proposals...\n";
    my $exp_file = $semdir."/".$semdname."S-proposals.zip";
    if (-e $exp_file) {
	printf "II found file %s\n", $exp_file;
	system "unzip -qq $exp_file";
    } else {
	printf "!! unable to find file %s!\n", $exp_file;
	exit;
    }
    return;
}

sub downloadProposalMapping($$) {
    my $semester = shift;
    my $omapfile = shift;

    printf "== Downloading proposal information from OPAL...\n";
    my $mapfile = $semester."/Download Proposals.html";

    if (($omapfile ne "") && (-e $omapfile)) {
	printf "== Copying proposal map file %s to %s ...", $omapfile, $mapfile;
	system "cp \"".$omapfile."\" \"".$mapfile."\"";
	if (-e $mapfile) {
	    print " success.\n";
	} else {
	    print " failed.\n";
	    exit;
	}
    } else {
	# We don't support this yet.
	printf "!! Unable to get proposal map from OPAL, development required.\n";
	exit;
    }

    return $mapfile;
}

sub renameProposals($) {
    my $semdir = shift;

    printf "== Organising proposals...\n";
    my @pdirs = ( "atca", "parkes", "lba" );
    for (my $i = 0; $i <= $#pdirs; $i++) {
	my $mdir = $semdir."/".$pdirs[$i];
	if (!-d $mdir) {
	    printf "-- making directory %s\n", $pdirs[$i];
	    system "mkdir ".$mdir;
	} else {
	    printf "-- directory %s already exists\n", $pdirs[$i];
	}
    }
    if (!-e $mapfile) {
	printf "!! Unable to find the proposal mapping file %s.\n", $mapfile;
	exit;
    }
    
    my %codes;
    open(A, $mapfile);
    my $pid = -1;
    my $pcode = "";
    while (<A>) {
	chomp(my $line = $_);
	if ($line =~ /\<td\>.*name\=\"pid\" value=\"(.*?)\"/) {
	    $pid = $1;
	} elsif ($pid > -1) {
	    if ($line =~ /\<td\>(.*?)\<\/td\>/) {
		$pcode = $1;
		$codes{$pid} = lc($pcode);
		$pid = -1;
	    }
	}
    }
    close(A);
    
    # All directories from that file are called "proposal*"
    my @dirs = `ls -d proposal*`;
    for (my $i = 0; $i <= $#dirs; $i++) {
	chomp($dirs[$i]);
	# Get the project ID.
	my ($telescope, $project_code, $obstable_file, $coversheet_file);
	if ($dirs[$i] =~ /^proposal(.*)$/) {
	    $project_code = $codes{$1};
	}
	if ($project_code =~ /^c/) {
	    $telescope = "atca";
	} elsif ($project_code =~ /^p/) {
	    $telescope = "parkes";
	} elsif ($project_code =~ /^v/) {
	    $telescope = "lba";
	} else {
	    printf "WW Deleting proposal %s, code %s\n", $dirs[$i], $project_code;
	    system "rm -rf ".$dirs[$i];
	    next;
	}
	# In each directory should be a couple of XML files, which we will use
	# to work out where to put this directory and rename the files
	# appropriately.
	my @files = `ls $dirs[$i]/*xml*`;
	for (my $j = 0; $j <= $#files; $j++) {
	    chomp($files[$j]);
	    # Open the file.
	    $files[$j] = shell_quote $files[$j];
	    
	    chomp(my $filetype = `head -n 1 $files[$j]`);
	    if ($filetype =~ /ObservationsTable/) {
		$obstable_file = $files[$j];
	    } elsif ($filetype =~ /CoverSheetForm/) {
		$coversheet_file = $files[$j];
	    }
	}
	# Do the things.
	printf "++ Renaming %s as %s project %s\n", $dirs[$i], uc($telescope), 
	uc($project_code);
	if ($coversheet_file !~ /\/coversheet.xml$/) {
	    my $rename_coversheet_cmd = "mv $coversheet_file $dirs[$i]/coversheet.xml";
	    system $rename_coversheet_cmd;
	}
	if ($obstable_file !~ /\/observations.xml$/) {
	    my $rename_observations_cmd = "mv $obstable_file $dirs[$i]/observations.xml";
	    system $rename_observations_cmd;
	}
	my $rename_directory = "mv $dirs[$i] $semdir/$telescope/".uc($project_code);
	system $rename_directory;
    }
    
}

sub nicePrint($$) {
    # The block will have this title - basically the left indent amount.
    my $title = shift;
    # The string to print nicely.
    my $s = shift;
    # Any optional parts (a hash ref).
    my $opts = shift;

    # Check the options.
    # The delimiter to break lines on - normally, and by default, space.
    my $d = " ";
    if (defined $opts && defined $opts->{'delimiter'}) {
	$d = $opts->{'delimiter'};
    }
    # Replacing strings.
    my ($ra, $rb);
    if (defined $opts && defined $opts->{'replace'}) {
	$ra = $opts->{'replace'}->[0];
	$rb = $opts->{'replace'}->[1];
    }
    # Don't break this line.
    my $nobreaks = 0;
    if (defined $opts && defined $opts->{'nobreaks'} &&
	$opts->{'nobreaks'} == 1) {
	$nobreaks = 1;
    }
    # Print under the title.
    my $undertitle = 0;
    if (defined $opts && defined $opts->{'undertitle'} &&
	$opts->{'undertitle'} == 1) {
	$undertitle = 1;
    }
    # Don't include slashes at the end of continuing lines.
    my $eol_slashes = 1;
    if (defined $opts && defined $opts->{'eol_slashes'} &&
	$opts->{'eol_slashes'} == 0) {
	$eol_slashes = 0;
    }

    # Get rid of ctrl-m line breaks.
    $s =~ s/[\r\n]+/ /g;
    # And remove double spaces.
    $s =~ s/\s+/ /g;

    # Print out the string $s making sure the lines don't go over the
    # maximum number of characters long.
    my @e = split($d, $s);
    $title .= " ";
    my $tlen = length($title);
    if ($undertitle == 1) {
	$tlen = 0;
    }
    my $pformat = "%".$tlen."s%s %s\n";
    my $o = "";
    my $lo = length($o);
    my $title_printed = 0;
    if ($undertitle == 1) {
	printf $title."\n";
	$title = "";
	$title_printed = 1;
    }
    my $maxlength = 70;
    if ($nobreaks == 1) {
	$maxlength = 1e9;
    }
    for (my $i = 0; $i <= $#e; $i++) {
	if (defined $a && defined $b) {
	    $e[$i] =~ s/$a/$b/g;
	}
	my $le = length($e[$i]);
	if (($tlen + $lo + $le + 1) > $maxlength) {
	    if ($i <= $#e && $eol_slashes == 1) {
		printf $pformat, $title, $o, "\\";
	    } else {
		printf $pformat, $title, $o;
	    }
	    if ($title_printed == 0) {
		$title = "";
		$title_printed = 1;
	    }
	    $o = "";
	}
	$o .= $e[$i].$d;
	$lo = length($o);
    }
    # Get rid of the delimiter at the end.
    if ($o =~ /\Q$d\E$/) {
	$o =~ s/\Q$d\E$//;
    }
    if ($o ne "" || $title_printed == 0) {
	printf $pformat, $title, $o;
    }
}

sub stripSpacing {
    my $a = shift;

    $a =~ s/^\s*(.*?)\s*$/$1/;

    return $a;
}

sub getPI($) {
    my $cover_ref = shift;

    # Get the name of the PI from the XML hash of the cover sheet,
    # and their email address.
    return ( &stripSpacing($cover_ref->{'principalInvestigator'}->{'lastName'}->{'content'}),
	     &stripSpacing($cover_ref->{'principalInvestigator'}->{'email'}->{'content'}) );
}

sub getTitle($) {
    my $cover_ref = shift;
    
    # Get the title from the XML hash of the cover sheet.
    my $title = $cover_ref->{'title'}->{'content'};
    # Alter the title if it's a NAPA proposal.
    my $proptype = $cover_ref->{'type'}->{'content'};
    if ($proptype eq "NAPA" && $title !~ m{^NAPA}) {
	$title = "NAPA: ".$title;
    }
    
    return &stripSpacing($title);
}

sub zapper($) {
    my $val = shift;

    # Remove trailing full stop.
    $val =~ s/\.$//;

    # Check for essentially blank values.
    if ($val =~ m{^no preference$}i ||
	$val =~ m{^none$}i ||
	$val =~ m{^no$}i) {
	$val = "";
    }

    return &stripSpacing($val);
}

sub getObs($$$) {
    my $obs = shift;
    my $obsref = shift;
    my $coverref = shift;

    # Go through the observation XML hash and get useful information.

    my @requested_times;
    my @repeats;
    my @arrays;
    my @bands;
    my @bandwidths;
    my @sources;
    my @radecs;

    my $obsarr;
    if ($obs eq "atca") {
	$obsarr = $obsref->{'sources'}->{'au.csiro.atnf.opal.domain.AtcaObservation'};
    } elsif ($obs eq "parkes") {
	$obsarr = $obsref->{'sources'}->{'au.csiro.atnf.opal.domain.ParkesContinuumObservation'};
    }	
    if (ref($obsarr) eq "HASH") {
	# Turn it into an array.
	my $h = $obsarr;
	$obsarr = [ $h ];
    }
    for (my $i = 0; $i <= $#{$obsarr}; $i++) {
	# Get the position of this source.
	my ($ra, $dec) = ("", "");
	if ($obsarr->[$i]->{'position'}) {
	    my $p1 = $obsarr->[$i]->{'position'}->{'xAngle'}->{'itsValue'};
	    my $x1 = $obsarr->[$i]->{'position'}->{'xAngle'}->{'precision'};
	    my $p2 = $obsarr->[$i]->{'position'}->{'yAngle'}->{'itsValue'};
	    my $x2 = $obsarr->[$i]->{'position'}->{'yAngle'}->{'precision'};
	    my $coordsys = $obsarr->[$i]->{'position'}->{'system'};
	    ($ra, $dec) = &translateCoord($p1, $p2, $x1, $x2, $coordsys);
	} else {
	    # When we can't find a position.
	    $ra = "00:00:00";
	    $dec = "-90:00:00";
	}
	my $tdec = str2turn($dec, "D");
	my $b;
	if ($obs eq "atca") {
	    $b = lc $obsarr->[$i]->{'band'};
	    if ($b =~ /\s+$/) {
		$b =~ s/\s+$//;
	    }
	} else {
	    $b = "";
	}
	my ($xtra_reps, $reptime) = &roundRequestedTimes($obsarr->[$i]->{'integrationTime'},
							 $tdec, $b);
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
	    if ($b =~ /\s+$/) {
		$b =~ s/\s+$//;
	    }
	    push @bands, &stripSpacing($b);
	    if ((ref($obsarr->[$i]->{'bandwidths'}) ne "HASH") &&
		($obsarr->[$i]->{'bandwidths'} ne "Select")) {
		push @bandwidths, $obsarr->[$i]->{'bandwidths'};
	    } else {
		push @bandwidths, "ReplaceMe";
	    }
	    # Check for bad values.
	    my $replacer = "";
	    for (my $j = 0; $j <= $#bandwidths; $j++) {
		if ($bandwidths[$j] eq "ReplaceMe") {
		    if ($j < $#bandwidths && $bandwidths[$j + 1] ne "ReplaceMe") {
			$bandwidths[$j] = $bandwidths[$j + 1];
			$replacer = $bandwidths[$j + 1];
		    } elsif ($j > 0 && $bandwidths[$j - 1] ne "ReplaceMe") {
			$bandwidths[$j] = $bandwidths[$j - 1];
			$replacer = $bandwidths[$j - 1];
		    }
		}
	    }
	    if ($replacer eq "") {
		$replacer = "CFB 1M (no zooms)";
	    }
	    for (my $j = 0; $j <= $#bandwidths; $j++) {
		if ($bandwidths[$j] eq "ReplaceMe") {
		    $bandwidths[$j] = $replacer;
		}
	    }
	} elsif ($obs eq "parkes") {
	    push @arrays, "any";
	    my $fs = $obsarr->[$i]->{'frequencies'};
	    if (ref($fs) eq "HASH") {
		push @bands, $fs->{'string'};
	    } elsif (ref($fs) eq "ARRAY") {
		for (my $j = 0; $j <= $#{$fs}; $j++) {
		    push @bands, &stripSpacing($fs->[$j]->{'string'});
		}
	    }
	    my $insentry = $coverref->{'instrumentSetups'}->{'m'}->{'entry'};
	    if (ref($insentry) eq "HASH") {
		my $h = $insentry;
		$insentry = [ $h ];
	    }
	    for (my $j = 0; $j <= $#{$insentry}; $j++) {
		if (defined $insentry->[$j]->{'au.csiro.atnf.opal.domain.ParkesDetails'}) {
		    $insentry = $insentry->[$j]->{'au.csiro.atnf.opal.domain.ParkesDetails'};
		    last;
		}
	    }
	    my $backends = $insentry->{'backEndSystem'}->{'org.apache.commons.collections.set.ListOrderedSet'}->{'default'}->{'setOrder'}->{'string'};
	    if (ref($backends) ne "ARRAY") {
		my $h = $backends;
		$backends = [ $h ];
	    }
	    my @bends;
	    for (my $j = 0; $j <= $#{$backends}; $j++) {
		push @bends, &stripSpacing($backends->[$j]->{'content'});
	    }
	    push @bandwidths, join("/", @bends);
	}
	push @sources, &stripSpacing($obsarr->[$i]->{'name'});

    }
	
    
    # Summarise the information in the output.
    my $times_string = &concatArray(\@requested_times, \@repeats, 4);
    &nicePrint("Requested time:", $times_string, { 'delimiter' => "; " });

    my $arrays_string = &concatArray(\@arrays, \@repeats, 3);
    &nicePrint("Array:", $arrays_string, { 'delimiter' => "; " });

    my $bands_string = &concatArray(\@bands, \@repeats, 3);
    &nicePrint("Band:", $bands_string, {
	'delimiter' => "; ",
	'replace' => [ "/", " " ]
	       });
    
    my $bandwidths_string = &concatArray(\@bandwidths, \@repeats, 3);
    &nicePrint("BW:", $bandwidths_string, { 'delimiter' => "; " });

    my $sources_string = &concatArray(\@sources, \@repeats, 3);
    &nicePrint("Source:", $sources_string, { 'delimiter' => "; " });

    my $pos_string = &concatArray(\@radecs, \@repeats, 3);
    &nicePrint("RADEC:", $pos_string, { 'delimiter' => "; " });

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

sub translateCoord($$$$$) {
    my ($p1, $p2, $x1, $x2, $c) = @_;
    # Turn the XML-format coordinates into something more friendly.

    my $coordtype = ($c eq "Galactic") ? 3 : 1;

    my ($ra_string, $dec_string);
    my $pi = 3.141592654;
    
    if ($coordtype == 1) {
	# We have p1 = RA, p2 = Dec
	$p1 *= 24.0 / (2 * $pi);
	$p2 *= 180 / $pi;
	my $rah = floor($p1);
	$p1 -= $rah;
	$p1 *= 60.0;
	my $ram = floor($p1);
	$p1 -= $ram;
	$p1 *= 60.0;
	my $ras = $p1;
	my $raf = "%02d:%02d:%0";
	if ($x1 > 0) {
	    $raf .= (3 + $x1).".".$x1."f";
	} else {
	    $raf .= "2.0f";
	}
	$ra_string = sprintf $raf, $rah, $ram, $ras;

	my $decs = ($p2 < 0) ? -1 : 1;
	$p2 *= $decs;
	my $decd = floor($p2);
	$p2 -= $decd;
	$p2 *= 60.0;
	my $decm = floor($p2);
	$p2 -= $decm;
	$p2 *= 60.0;
	my $decsec = $p2;
	my $decf = "%+03d:%02d:%0";
	if ($x2 > 0) {
	    $decf .= (3 + $x2).".".$x2."f";
	} else {
	    $decf .= "2.0f";
	}
	$decd *= $decs;
	$dec_string = sprintf $decf, $decd, $decm, $decsec;
    } elsif ($coordtype == 3) {
	# We have p1 = Lon, p2 = Lat
	$p1 *= 180 / $pi;
	$p2 *= 180 / $pi;
	my ($ra, $dec) = (`cotra radec=$p1,$p2 type=galactic` =~ m{J2000:\s+(\S+)\s+(\S+)});
	$ra =~ s/\.\d+$//;
	$dec =~ s/\.\d+$//;
	$ra_string = $ra;
	$dec_string = $dec;
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

sub getPublicHolidays() {
    # Set up the web scraper.
    my $dates = scraper {
	process 'table td', "dates[]" => 'TEXT';
	process 'table tr', "rows[]" => 'TEXT';
    };
    
    # Get the information from the web site.
    my $res = $dates->scrape(
	URI->new("https://www.industrialrelations.nsw.gov.au/public-holidays/public-holidays-nsw")
	);
    
    # Work out the shape of the table.
    my $nrows = $#{$res->{rows}} + 1;
    #printf "found %d rows\n", $nrows;
    my $ncols = ($#{$res->{dates}} + 1) / $nrows;
    #printf "there must be %d columns\n", $ncols;
    
    # Form the dates.
    my %phdates;
    for (my $i = 1; $i < $ncols; $i++) {
	my $year = $res->{dates}->[$i] * 1;
	for (my $j = 1; $j < $nrows; $j++) {
	    my $n = $j * $ncols + $i;
	    my $d = Encode::encode("ascii", $res->{dates}->[$n]);
	    $d =~ s/\?//g;
	    #printf "d is \"%s\"\n", $d;
	    $d =~ s/^.*\,\s*(.*)$/$1/;
	    my @de = split(/\s+/, $d);
	    my $day = $de[0];
	    my $month = &month2number($de[1]);
	    if ($d ne "") {
		#printf "%4d - %02d - %02d\n", $year, $month, $day;
		my $dt = DateTime->new(
		    year => $year, month => $month, day => $day,
		    hour => 8, time_zone => 'Australia/Sydney' );
		my $k = sprintf "%4d-%02d-%02d", $year, $month, $day;
		$phdates{$k} = { 'datetime' => $dt,
				 'string' => sprintf "%02d/%02d", $day, $month };
	    }
	}
    }
    return %phdates;
}

sub month2number($) {
    my $m = shift;
    $m = lc($m);
    my @months = ( "january", "february", "march", "april", "may", "june",
		   "july", "august", "september", "october", "november", "december" );
    for (my $i = 0; $i <= $#months; $i++) {
	if ($m eq $months[$i]) {
	    return ($i + 1);
	}
	if ($months[$i] =~ /^$m/) {
	    return ($i + 1);
	}
    }
    return 0;
}

sub semesterDateRange($) {
    my $semname = shift;
    # Work out the date ranges for this semester.
    my ($semyear, $semmonth) = $semname =~ m/^(\d+)(\D+)$/;
    $semyear *= 1;
    $semmonth = &month2number($semmonth);
    my $semStartDate = DateTime->new(
	year => $semyear, month => $semmonth, day => 1,
	hour => 0, time_zone => "Australia/Sydney" );
    my $semendyear = $semyear;
    my $semendmonth = 10;
    if ($semmonth == 10) {
	$semendyear += 1;
	$semendmonth = 4;
    }
    my $semEndDate = DateTime->new(
	year => $semendyear, month => $semendmonth, day => 1,
	hour => 0, time_zone => "Australia/Sydney" );

    return { "start" => $semStartDate, "end" => $semEndDate,
	     "startString" => $semStartDate->strftime("%Y-%m-%d"),
	     "endString" => $semEndDate->strftime("%Y-%m-%d"),
	     "nDays" => ($semEndDate->mjd() - $semStartDate->mjd() + 1)
    };

}

sub restrictDates($$) {
    my $sem = shift;
    my $dates = shift;

    # Restrict the dates present in $dates to those within
    # the semester.
    my $gdates = {};
    foreach my $d (keys %{$dates}) {
	if (($dates->{$d}->{'datetime'} >= $sem->{'start'}) &&
	    ($dates->{$d}->{'datetime'} < $sem->{'end'})) {
	    $gdates->{$d} = $dates->{$d};
	}
    }

    return $gdates;
}
