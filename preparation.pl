#!/usr/bin/perl

use URI;
use Web::Scraper;
use Encode;
use DateTime;
use JSON;
use Getopt::Long;
use XML::Simple;
use String::ShellQuote;
use Astro::Coord;
use Astro::Time;
use POSIX;
use Data::Dumper;
use strict;

# This script does all the necessary preparatory work for the semester.

# Get the arguments.
my $sem = "";
my $proposal_zip = "";
my $map_file = "";
my $clean = "";
my $obs = "atca";
my $maint_time = 600; # hours.
my $vlbi_time = 288; # hours.
my $legacy_time = 1200; # hours.
my $calibration_time = 144; # hours.
my $first_array = "";
my $first_array_reconfignum = 100;
my $arrays = "";
my $last_project = "C007";
my $big_count = 200;
# The maintenance_days is a list of how many
# 4-day, 3-day, 2-day and 1-day maintenance blocks to include.
my $maintenance_days = "4,5,4,37";
# The VLBI days is a list of how many
# 168h, 96h, 72h, 48h, 24h, 8h VLBI blocks to include.
my $vlbi_days = "2,3,1,3,3,7";
my $vlbi_length = "168,96,72,48,24,8";
my $grades_file = "";
my @legacy;
# You can add projects on the command line.
# For example, to add C1726 in the summer semester:
# --add C1726,Hollow,5,1,72,any,4cm,CFB1M,many,00:00:00,-90:00:00
# That is code, PI, grade, number of slots, length of each slot (hours), array,
# band, bandwidth, source, ra, dec
my @added_projects;
# Specifying colours for codes.
# --colour MAINT,0000ff for really blue maintenance for example
my @colour_specs;
GetOptions(
    "semester=s" => \$sem,
    "zip=s" => \$proposal_zip,
    "map=s" => \$map_file,
    "clean" => \$clean,
    "obs=s" => \$obs,
    "legacy=s" => \@legacy,
    "maintenance=i" => \$maint_time,
    "vlbi=i" => \$vlbi_time,
    "calibration=i" => \$calibration_time,
    "tlegacy=i", \$legacy_time,
    "first=s" => \$first_array,
    "firstnum=i" => \$first_array_reconfignum,
    "arrays=s" => \$arrays,
    "last=s" => \$last_project,
    "big=i" => \$big_count,
    "grades=s" => \$grades_file,
    "add=s" => \@added_projects,
    "colour=s" => \@colour_specs
    ) or die "Error in command line arguments.\n";

# Set some default colours.
my %colours = (
    'default' => "cdcdcd",
    'unscheduled' => "9ae68d",
    'MAINT' => "cdcdff",
    'CONFIG' => "ffff8d",
    'CABB' => "ffcdcd",
    'BL' => "ffcdff",
    'FAST' => "ffc000"
    );
# Assign any colours we've been given.
for (my $i = 0; $i <= $#colour_specs; $i++) {
    my @cspec = split(/\,/, $colour_specs[$i]);
    $colours{$cspec[0]} = $cspec[1];
}

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

# Step 6. download the scores file.
my $scorefile = &downloadScores($sem, $grades_file);

# Step 7. Gather the scores.
my $projectScores = &parseScoreFile($scorefile, \@legacy);
#print Dumper($projectScores);

# Step 8. prepare the summary file.
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
# Parse the XML for each project.
my @projects = &xmlParse($sem, $obs);
&addExtraProjects(\@added_projects, \@projects, $projectScores);

printf "II Found %d projects.\n", ($#projects + 1);
#for (my $i = 0; $i <= $#projects; $i++) {
#    printf "II Project %d: Code %s\n", ($i + 1), $projects[$i]->{'project'};
#}
my $summary = &semesterTimeSummary(\@projects, \@legacy, $last_project, $big_count);
&printSummary($summary, {
    'name' => $semname, 'length' => $semesterDetails->{'nDays'},
    'maintenance' => $maint_time, 'calibration' => $calibration_time,
    'legacy' => $legacy_time, 'vlbi' => $vlbi_time
});

# Prepare to output all our files.
# Arrange the arrays.
my @available_arrays = split(/\,/, $arrays);
for (my $i = 0; $i <= $#available_arrays; $i++) {
    if (($available_arrays[$i] eq $first_array) &&
	($i != 0)) {
	splice @available_arrays, $i, 1;
	unshift @available_arrays, $first_array;
    }
}
# Split up the maintenance frequency string.
my @n_maint = split(/\,/, $maintenance_days);
# Split up the VLBI frequency string.
my @n_vlbi = split(/\,/, $vlbi_days);
my @l_vlbi = split(/\,/, $vlbi_length);
# Output the text schedule summary.
my $summary_file = sprintf "ca-prep-%s.txt", $semname;
&printFileTextSummary($summary_file, $obs, $semname, \@available_arrays, 
		      \@n_maint, \@n_vlbi, \@l_vlbi, $semesterHolidays,
		      \@projects, $projectScores);
my $summary_json = sprintf "ca-%s.json", $semname;
&printFileJson($summary_json, $obs, $semname, \@available_arrays,
	       \@n_maint, \@n_vlbi, \@l_vlbi, $semesterHolidays,
	       \@projects, $semesterDetails, $projectScores,
	       $first_array_reconfignum, \%colours);

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

sub downloadScores($$) {
    my $semester = shift;
    my $oscorefile = shift;

    printf "== Downloading scores information from OPAL...\n";
    my $scorefile = $semester."/scores.html";

    if (($oscorefile ne "") && (-e $oscorefile)) {
	printf "== Copying score file %s to %s ...", $oscorefile, $scorefile;
	system "cp \"".$oscorefile."\" \"".$scorefile."\"";
	if (-e $scorefile) {
	    print " success.\n";
	} else {
	    print " failed.\n";
	    exit;
	}
    } else {
	# We don't support this yet.
	printf "!! Unable to get scores from OPAL, development required.\n";
	exit;
    }

    return $scorefile;
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
	    my $ts = ($scorebits[1] eq "-1.0") ? $scorebits[2] : $scorebits[1];
	    # Over-ride this if it's a Legacy project.
	    for (my $i = 0; $i <= $#{$legacy}; $i++) {
		if ($legacy->[$i] eq $scorebits[0]) {
		    $ts = "5.0";
		    last;
		}
	    }
	    $s->{$scorebits[0]} = $ts;
	}
    }
    close(S);

    return $s;
}

sub nicePrint($$) {
    # The block will have this title - basically the left indent amount.
    my $title = shift;
    # The string to print nicely.
    my $s = shift;
    # Any optional parts (a hash ref).
    my $opts = shift;

    # Begin by stripping non-ASCII characters out.
    $s =~ s/[^[:ascii:]]+//g;
    
    my @rstrings;
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
	push @rstrings, sprintf $title."\n";
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
		push @rstrings, sprintf $pformat, $title, $o, "\\";
	    } else {
		push @rstrings, sprintf $pformat, $title, $o;
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
	push @rstrings, sprintf $pformat, $title, $o;
    }
    return @rstrings;
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

sub addExtraProjects($$) {
    my $added_projects = shift;
    my $projects = shift;
    my $scores = shift;
    
    # Add in the extra projects, if any.
    for (my $i = 0; $i <= $#{$added_projects}; $i++) {
	my @details = split(/\,/, $added_projects->[$i]);
	# Check that it is not already on our list.
	my $existant = 0;
	for (my $j = 0; $j <= $#{$projects}; $j++) {
	    if ($projects->[$j]->{'project'} eq $details[0]) {
		$existant = 1;
		last;
	    }
	}
	if ($existant == 0) {
	    my @rt = ( $details[4] );
	    my @rp = ( $details[3] );
	    my @ra = ( $details[5] );
	    my @rb = ( $details[6] );
	    my @rc = ( $details[7] );
	    my @rs = ( $details[8] );
	    my @rd = ( &stripSpacing($details[9].",".$details[10]) );
	    my @rl = ( [ "00:00", "23:59" ] );
	    my $srt = &concatArray(\@rt, \@rp, 4);
	    my $sra = &concatArray(\@ra, \@rp, 3);
	    my $srb = &concatArray(\@rb, \@rp, 3);
	    my $src = &concatArray(\@rc, \@rp, 3);
	    my $srs = &concatArray(\@rs, \@rp, 3);
	    my $srd = &concatArray(\@rd, \@rp, 3);
	    push @{$projects}, {
		"project" => $details[0], "title" => "Added project",
		"preferred" => "", "impossible" => "",
		"service" => "", "comment" => "",
		"other" => "", "proptype" => "ASTRO", 
		"principal" => $details[1], "pi_email" => "",
		"observations" => {
		    'requested_times' => \@rt,
		    'summary_requested_times' => $srt,
		    'requested_arrays' => \@ra,
		    'summary_requested_arrays' => $sra,
		    'requested_bands' => \@rb,
		    'summary_requested_bands' => $srb,
		    'requested_bandwidths' => \@rc,
		    'summary_requested_bandwidths' => $src,
		    'requested_sources' => \@rs,
		    'summary_requested_sources' => $srs,
		    'requested_positions' => \@rd,
		    'summary_requested_positions' => $srd,
		    'nrepeats' => \@rp,
		    'lsts' => \@rl
		}
	    };
	    $scores->{$details[0]} = $details[2];
	}
    }

}

sub getObs($$$) {
    my $obs = shift;
    my $obsref = shift;
    my $coverref = shift;

    # Need some information about the observatory.
    my %ellim = ( 'atca' => 12, 'parkes' => 30 );
    my %lat = ( 'atca' => -30.31288, 'parkes' => -32.99841 );
    
    # Go through the observation XML hash and get useful information.

    my @requested_times;
    my @repeats;
    my @arrays;
    my @bands;
    my @bandwidths;
    my @sources;
    my @radecs;
    my @lsts;

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
	# Get the LSTs as well.
	my $lst_start = $obsarr->[$i]->{'lstStart'};
	if (ref $lst_start eq "HASH") {
	    $lst_start = "00:00";
	}
	my $lst_end = $obsarr->[$i]->{'lstEnd'};
	if ($lst_end eq "Never") {
	    $lst_end = "23:59";
	}
	push @lsts, [ $lst_start, $lst_end ];
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
	    $ras = floor($ras);
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
	    $decsec = floor($decsec);
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
		    hour => 0, time_zone => 'Australia/Sydney' );
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
	     "nDays" => ($semEndDate->mjd() - $semStartDate->mjd())
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

sub xmlParse($$) {
    my $semdir = shift;
    my $obs = shift;

    # Get a list of the project directories.
    printf "== Getting list of project directories in %s/%s.\n", $semdir, $obs;
    my @olist = <$semdir/$obs/*>;
    my @list = sort {
	(my $aproj) = $a =~ m{^\S+/\w(\d+)$};
	(my $bproj) = $b =~ m{^\S+/\w(\d+)$};
	return $aproj <=> $bproj; } <$semdir/$obs/*>;
    
    my @outproj;
    # Cycle through the projects.
    foreach my $dir (@list) {
	(my $proj) = $dir =~ m{^$semdir/$obs/(\S+)$};
	# Read in the cover sheet and the observation tables. We pass it through
	# iconv so we don't get problems with invalid characters not in UTF-8.
	my $coverstring = `iconv -f utf-8 -t utf-8 -c $dir/coversheet.xml`;
	$coverstring =~ s/\&\#x.*?\;//g;
	my $cover = XMLin($coverstring, ForceContent => 1);
	my $obstablestring = `iconv -f utf-8 -t utf-8 -c $dir/observations.xml`;
	$obstablestring =~ s/\&\#x.*?\;//g;
	my $obstable = XMLin(
	    $obstablestring, keyattr => [],
	    forcearray => [ 'au.csiro.atnf.opal.domain.AtcaObservation' ] );
	my $a = { "project" => $proj, "title" => &getTitle($cover),
		  "preferred" => &zapper($cover->{'preferredDates'}->{'content'}),
		  "impossible" => &zapper($cover->{'impossibleDates'}->{'content'}),
		  "service" => &zapper($cover->{'serviceObserving'}->{'content'}),
		  "comments" => &zapper($cover->{'specialRequirements'}->{'content'}),
		  "other" => &zapper($cover->{'otherInformation'}->{'content'}),
		  "proptype" => &zapper($cover->{'type'}->{'content'})
	};
	my ($principal, $pi_email) = &getPI($cover);
	$a->{"principal"} = $principal;
	$a->{"pi_email"} = $pi_email;

	$a->{"observations"} = &getObs($obs, $obstable, $cover);

	push @outproj, $a;
	
    }
    
    return @outproj;
}

sub allBands {
    return ( '16cm', '4cm', '15mm', '7mm', '3mm' );
}

sub initBandRef {
    my @bands = &allBands();
    my $t = {};
    for (my $i = 0; $i <= $#bands; $i++) {
	$t->{$bands[$i]} = 0;
    }
    return $t;
}

sub codeToNumber($) {
    my $pcode = shift;

    my ($t, $code) = ($pcode =~ m/^(\D+)(\d+)$/);
    return ($code * 1);
}

sub semesterTimeSummary($$$) {
    my $projects = shift;
    my $exprojects = shift;
    my $lp = shift;
    my $biglimit = shift;

    # Make a summary of amount of time requested as a function of array,
    # band, and type.
    my %array_requests;
    my %otype = ( "total" => 0, "normal" => 0, "napa" => 0, "large" => 0,
		  "weird" => 0, "excluded" => 0,
		  "continuum" => 0, "1zoom" => 0, "64zoom" => 0,
		  "pulsar" => 0, "vlbi" => 0, "new" => 0, "big" => 0 );
    my %omap = ( "CFB1M" => "continuum", "CFB1M-0.5k" => "1zoom",
		 "CFB64M-32k" => "64zoom", "CFB1M-pulsar" => "pulsar",
		 "CFB1-64M" => "hybrid" );
    my %amap = ( "6a" => "6km", "6b" => "6km", "6c" => "6km", "6d" => "6km",
		 "any6" => "6km", "1.5a" => "1.5km", "1.5b" => "1.5km",
		 "1.5c" => "1.5km", "1.5d" => "1.5km", "any1.5" => "1.5km",
		 "750a" => "750m", "750b" => "750m", "750c" => "750m",
		 "750d" => "750m", "any750" => "750m", "ew367" => "compact",
		 "anycompact" => "compact", "ew352" => "compact",
		 "h75/168" => [ "h75", "h168" ],
		 "any 750 or greater" => [ "750m", "1.5km", "6km" ],
		 "any" => "any" );
    my $band_totals = &initBandRef();
    my %ttotal = ( "normal" => 0, "large" => 0, "napa" => 0, "continuum" => 0,
		   "1zoom" => 0, "64zoom" => 0, "pulsar" => 0, "vlbi" => 0,
		   "new" => 0, "hybrid" => 0 );
    
    my $newcut = &codeToNumber($lp);
    
    printf "== Summarising time requests.\n";
    for (my $i = 0; $i <= $#{$projects}; $i++) {
	$otype{'total'} += 1;
	my $exclude = 0;
	for (my $j = 0; $j <= $#{$exprojects}; $j++) {
	    if (lc($projects->[$i]->{'project'}) eq lc($exprojects->[$j])) {
		$exclude = 1;
		last;
	    }
	}
	if ($exclude == 1) {
	    $otype{'excluded'} += 1;
	    next;
	}
	my $p = $projects->[$i];
	#printf "DD project %s:\n", $p->{'project'};
	my $pn = &codeToNumber($p->{'project'});
	my $np = 0;
	if ($pn > $newcut) {
	    # New project.
	    $otype{'new'} += 1;
	    $np = 1;
	}
	# Check for a NAPA.
	my $et = "weird";
	if ($p->{'proptype'} eq "NAPA") {
	    $et = "napa";
	} elsif ($p->{'proptype'} eq "Standard") {
	    $et = "normal";
	} elsif ($p->{'proptype'} eq "Large Project") {
	    $et = "large";
	}
	$otype{$et} += 1;
	
	#printf "DD requests arrays:\n";
	my $o = $p->{'observations'};
	my $rw = {};
	my $ptotaltime = 0;
	for (my $j = 0; $j <= $#{$o->{'requested_arrays'}}; $j++) {
	    #printf "DD  %s\n", $o->{'requested_arrays'}->[$j];
	    my $a = lc($o->{'requested_arrays'}->[$j]);
	    if (defined $amap{$a}) {
		$a = $amap{$a};
	    }
	    if (ref $a ne 'ARRAY') {
		# Turn it into an array ref.
		$a = [ $a ];
	    }
	    for (my $k = 0; $k <= $#{$a}; $k++) {
		my $ta = $a->[$k];
		#printf "DD found array request %s\n", $ta;
		
		if (!defined $array_requests{$ta}) {
		    $array_requests{$ta} = &initBandRef();
		}
		my $bstring = $o->{'requested_bands'}->[$j];
		$bstring =~ s/and//g;
		$bstring =~ s/\,/ /g;
		my @bands = split(/\s+/, $bstring);
		my $dt = $o->{'requested_times'}->[$j] / (($#bands + 1) * ($#{$a} + 1));
		$dt *= $o->{'nrepeats'}->[$j];
		for (my $l = 0; $l <= $#bands; $l++) {
		    # Get rid of punctuation.
		    $bands[$l] =~ s/[\.\,\s]//g;
		    $ptotaltime += $dt;
		    if (defined $array_requests{$ta}->{$bands[$l]}) {
			#printf "++ Adding %.2f hrs in band %s\n", $dt, $bands[$k];
			$array_requests{$ta}->{$bands[$l]} += $dt;
			$band_totals->{$bands[$l]} += $dt;
			$ttotal{$et} += $dt;
			if ($np == 1) {
			    $ttotal{'new'} += $dt;
			}
		    } else {
			printf "WW Didn't find matching band %s (%s).\n", $bands[$k], $p->{'project'};
		    }
		}
		#printf "DD bands in array: %s\n", $o->{'requested_bands'}->[$j];
		#printf "DD time in array: %d\n", $o->{'requested_times'}->[$j];
		#printf "DD number of repeats: %d\n", $o->{'nrepeats'}->[$j];
		my $w = $o->{'requested_bandwidths'}->[$j];
		#printf "project %s requests bandwidth %s\n", $p->{'project'}, $o->{'requested_bandwidths'}->[$j];
		if (!defined $rw->{$w}) {
		    $rw->{$w} = 0;
		}
		$rw->{$w} += $dt * ($#bands + 1);
	    }
	}
	foreach my $t (keys %{$rw}) {
	    #printf "II Identified %s (%s) request.\n", $omap{$t}, $t;
	    $otype{$omap{$t}} += 1;
	    $ttotal{$omap{$t}} += $rw->{$t};
	}
	if ($ptotaltime > $biglimit) {
	    $otype{'big'} += 1;
	}
    }

    my @arrs = keys %array_requests;
    my $array_totals = {};
    my $gtotal = 0;
    for (my $i = 0; $i <= $#arrs; $i++) {
	my $t = $array_requests{$arrs[$i]};
	$array_totals->{$arrs[$i]} = ($t->{'16cm'} + $t->{'4cm'} +
				      $t->{'15mm'} + $t->{'7mm'} + $t->{'3mm'});
	$gtotal += $array_totals->{$arrs[$i]};
    }
    
    return {
	'requested' => \%array_requests,
	'arrays' => \@arrs,
	'array_totals' => $array_totals,
	'band_totals' => $band_totals,
	'total' => $gtotal,
	'types' => \%otype,
	'total_times' => \%ttotal
    };
    
}

sub printSummary($$) {
    # Take the object coming from semesterTimeSummary and print out
    # some information.
    my $s = shift;
    my $p = shift;

    # Print out the time totals.
    printf "II %10s %10s %10s %10s %10s %10s %10s\n", "Array", "16cm", "4cm",
    "15mm", "7mm", "3mm", "Total";
    
    my @array_order = ( "h75", "h168", "h214", "compact", "750m", "1.5km", 
			"6km", "any" );
    my @arrs = @{$s->{'arrays'}};

    my $j = 0;
    while (1) {
	for (my $i = 0; $i <= $#arrs; $i++) {
	    my $t = $s->{'requested'}->{$arrs[$i]};
	    if ((($j <= $#array_order) && ($arrs[$i] eq $array_order[$j])) ||
		($j > $#array_order)) {
		printf "II %10s %10.1f %10.1f %10.1f %10.1f %10.1f %10.1f\n",
		$arrs[$i], $t->{'16cm'}, $t->{'4cm'}, $t->{'15mm'}, $t->{'7mm'}, 
		$t->{'3mm'}, $s->{'array_totals'}->{$arrs[$i]};
		last;
	    }
	}
	$j++;
	if ($j > $#array_order) {
	    last;
	}
    }
    my $b = $s->{'band_totals'};
    printf "II %10s %10.1f %10.1f %10.1f %10.1f %10.1f %10.1f\n", "Total",
    $b->{'16cm'}, $b->{'4cm'}, $b->{'15mm'},
    $b->{'7mm'}, $b->{'3mm'}, $s->{'total'};

    my @reqtypes = ( "total", "new", "normal", "napa", "large", "excluded", "weird",
		     "continuum", "1zoom", "64zoom", "hybrid", "pulsar", "vlbi", "big" );
    my @reqtitles = ( "All", "New", "Normal", "NAPA", "Large Projects", 
		      "Legacy Projects", "Weird Projects", "Continuum",
		      "1 MHz zooms", "64 MHz zooms", "1/64 MHz hybrid",
		      "Pulsar Binning", "VLBI", "Big Ask" );
    
    printf "II Request types:\n";
    printf "II %30s %4s %7s %10s\n", "Experiment Type", "#", "(%)", "Time (h)";
    for (my $i = 0; $i <= $#reqtypes; $i++) {
	my $tdisp = "";
	if ($reqtypes[$i] eq "total") {
	    $tdisp = sprintf "%10.1f", $s->{'total'};
	} elsif (defined $s->{'total_times'}->{$reqtypes[$i]}) {
	    $tdisp = sprintf "%10.1f", $s->{'total_times'}->{$reqtypes[$i]};
	}
	printf "II %30s %4d (%5.1f) %10s\n", $reqtitles[$i],
	$s->{'types'}->{$reqtypes[$i]}, (100 * $s->{'types'}->{$reqtypes[$i]} /
					 $s->{'types'}->{'total'}), $tdisp;
    }

    # Print out the semester statistics.
    printf "II Semester %s summary:\n", $p->{'name'};
    my $thours = $p->{'length'} * 24;
    printf "II %30s %10d h\n", "Total term length", $thours;
    my $ahours = $thours - ($p->{'maintenance'} + $p->{'vlbi'} +
			    $p->{'calibration'} + $p->{'legacy'});
    printf "II %30s %10d h\n", "Maintenance time", $p->{'maintenance'};
    printf "II %30s %10d h\n", "VLBI", $p->{'vlbi'};
    printf "II %30s %10d h\n", "Calibration time", $p->{'calibration'};
    printf "II %30s %10d h\n", "Legacy Projects", $p->{'legacy'};
    printf "II %30s %10d h\n", "Available time", $ahours;
    my $shours = $ahours * 0.9;
    printf "II %30s %10d h\n", "Schedulable time", $shours;
    printf "II %30s %10d h\n", "Requested", $s->{'total'};
    my $osub = $s->{'total'} / $shours;
    printf "II %30s %10.1f\n", "Oversubscription rate", $osub;
}

sub printSep() {
    return "------------------------------------------------------------------------";
}

sub printFileTextSummary($$$$$$$$$) {
    my $fname = shift;
    my $obs = shift;
    my $sem = shift;
    my $arrays = shift;
    my $maint = shift;
    my $vlbi = shift;
    my $lvlbi = shift;
    my $holidays = shift;
    my $projects = shift;
    my $scores = shift;
    
    # Open the file.
    open(O, ">".$fname) || die "!! Unable to open $fname for writing.\n";

    # Print the header.
    printf O "Observatory: %s\n", $obs;
    printf O "Arrays: %s\;\n", join("; ", @{$arrays});
    printf O "Term: %sS\n", $sem;
    printf O "Maintenance:";
    for (my $i = 0; $i <= $#{$maint}; $i++) {
	my $n = 4 - $i;
	for (my $j = 0; $j < $maint->[$i]; $j++) {
	    printf O " %d-day;", $n;
	}
    }
    printf O "\n";
    printf O "Holidays:";
    my @hkeys = sort (keys %{$holidays});
    for (my $i = 0; $i <= $#hkeys; $i++) {
	my $d = $holidays->{$hkeys[$i]}->{'datetime'};
	printf O " %02d/%02d;", $d->day(), $d->month();
    }
    printf O "\n";
    printf O "VLBI:";
    for (my $i = 0; $i <= $#{$vlbi}; $i++) {
	for (my $j = 0; $j < $vlbi->[$i]; $j++) {
	    printf O " %d;", $lvlbi->[$i];
	}
    }
    printf O "\n";
    printf O "%s\n", &printSep();

    # Go through the list of projects.
    for (my $i = 0; $i <= $#{$projects}; $i++) {
	my $p = $projects->[$i];
	printf O "Project id: %s\n", $p->{'project'};
	printf O "%s", join("", &nicePrint("Title:", $p->{'title'}, {
	    'nobreaks' => 1 }));
	printf O "PI: %s\n", $p->{'principal'};
	printf O "Email: %s\n", $p->{'pi_email'};
	my $ob = $p->{'observations'};
	printf O "%s", join("", &nicePrint("Requested time:",
					   $ob->{'summary_requested_times'}, {
					       'delimiter' => "; " }));
	printf O "%s", join("", &nicePrint("Array:",
					   $ob->{'summary_requested_arrays'}, {
					       'delimiter' => "; " }));
	printf O "%s", join("", &nicePrint("Band:",
					   $ob->{'summary_requested_bands'}, {
					       'delimiter' => "; ",
					       'replace' => [ "/", " " ] }));
	printf O "%s", join("", &nicePrint("BW:",
					   $ob->{'summary_requested_bandwidths'}, {
					       'delimiter' => "; " }));
	printf O "%s", join("", &nicePrint("Source:",
					   $ob->{'summary_requested_sources'}, {
					       'delimiter' => "; " }));
	printf O "%s", join("", &nicePrint("RADEC:",
					   $ob->{'summary_requested_positions'}, {
					       'delimiter' => "; "}));
	# Nobody ever gets the good and impossible dates correct.
	printf O "Good dates:\n";
	printf O "Bad dates:\n";
	printf O "%s", join("", &nicePrint("Service obs:",
					   $p->{'service'}));
	printf O "%s", join("", &nicePrint("Comments:",
					   $p->{'comments'}." ".
					   $p->{'other'}." ".
					   $p->{'preferred'}." ".
					   $p->{'impossible'}, {
					       'undertitle' => 1,
					       'eol_slashes' => 0 }));
	printf O "%s\n", &printSep();
    }
   
    close(O);
}

sub printFileJson($$$$$$$$$$$) {
    my $fname = shift;
    my $obs = shift;
    my $sem = shift;
    my $arrays = shift;
    my $maint = shift;
    my $vlbi = shift;
    my $lvlbi = shift;
    my $holidays = shift;
    my $projects = shift;
    my $details = shift;
    my $scores = shift;
    my $firstreconfig = shift;
    my $colours = shift;

    # We assign a modification time.
    my $modtime = DateTime->now();
    my %jobj = (
	'program' => {
	    'observatory' => { 'observatory' => $obs },
	    'colours' => { 'default' => $colours->{'default'},
			   'unscheduled' => $colours->{'unscheduled'} },
	    'term' => { 'term' => $semname, 'version' => 1,
			'configs' => $arrays, 
			'start' => $details->{"startString"},
			'end' => $details->{"endString"}
	    },
	    'special' => { 'lastReconfigNumber' => $firstreconfig },
	    'project' => []
	}, 'modificationTime' => $modtime->epoch()
	);
    # Add each of the projects.
    my $u = $jobj{'program'};
    for (my $i = 0; $i <= $#{$projects}; $i++) {
	my $p = $projects->[$i];
	my $proj = &createProject($p->{'project'}, "ASTRO", $p->{'principal'},
				  $p->{'comments'}." ".$p->{'other'},
				  $p->{'title'}, $p->{'impossible'},
				  $p->{'preferred'}, $colours);
	my $s = $proj->{'slot'};
	my $o = $p->{'observations'};
	for (my $j = 0; $j <= $#{$o->{'requested_times'}}; $j++) {
	    for (my $k = 0; $k < $o->{'nrepeats'}->[$j]; $k++) {
		push @{$s}, &createSlot(
		    $o->{'requested_arrays'}->[$j],
		    $o->{'requested_bands'}->[$j],
		    $o->{'requested_bandwidths'}->[$j],
		    $o->{'requested_sources'}->[$j],
		    $o->{'requested_positions'}->[$j],
		    $o->{'requested_times'}->[$j],
		    $scores->{$p->{'project'}}, 0, 
		    $o->{'requested_lsts'}->[$j]->[0],
		    $o->{'requested_lsts'}->[$j]->[1]
		    );
	    }
	}
	push @{$u->{'project'}}, $proj;
    }
    # Put the maintenance time in.
    my $proj = &createProject("MAINT", "MAINT", "Mirtschin/Wilson",
			      "", "Maintenance/Test", $holidays, "",
			      $colours);
    push @{$u->{'project'}}, $proj;
    my $s = $proj->{'slot'};
    for (my $i = 0; $i <= $#{$maint}; $i++) {
	for (my $j = 0; $j < $maint->[$i]; $j++) {
	    my $sname = sprintf "%d-day", (4 - $i);
	    my $rdur = 8;
	    if ($i == 0) {
		$rdur = 103;
	    } elsif ($i == 1) {
		$rdur = 80;
	    } elsif ($i == 2) {
		$rdur = 32;
	    }
	    push @{$s}, &createSlot(
		"any", "", "", $sname, "00:00:00,-90:00:00",
		$rdur, 6, 0, "00:00", "23:59");
	}
    }
    # And the VLBI time.
    $proj = &createProject("VLBI", "ASTRO", "Phillips", "", "VLBI", "", "",
			   $colours);
    push @{$u->{'project'}}, $proj;
    $s = $proj->{'slot'};
    for (my $i = 0; $i <= $#{$vlbi}; $i++) {
	for (my $j = 0; $j < $vlbi->[$i]; $j++) {
	    push @{$s}, &createSlot(
		"any", "16cm 4cm 15mm", "VLBI", "VLBI",
		"00:00:00,-90:00:00", (1 * $lvlbi->[$i]), 5, 0, "00:00", "23:59");
	}
    }
    # And the reconfigurations.
    $proj = &createProject("CONFIG", "CONFIG", "Stevens", "", "Reconfig",
			   $holidays, "", $colours);
    push @{$u->{'project'}}, $proj;
    $s = $proj->{'slot'};
    for (my $i = 0; $i <= $#{$arrays}; $i++) {
	push @{$s}, &createSlot(
	    $arrays->[$i], "", "", "100", "00:00:00,-90:00:00",
	    24, 6, 0, "00:00", "23:59");
    }
    # And some CABB reconfigurations.
    $proj = &createProject("CABB", "NASA", "Stevens", "", "CABB", "", "",
			   $colours);
    push @{$u->{'project'}}, $proj;
    $s = $proj->{'slot'};
    for (my $i = 0; $i < 30; $i++) {
	push @{$s}, &createSlot(
	    "any", "", "", "CABB", "00:00:00,-90:00:00", 
	    1, 6, 0, "00:00", "23:59");
    }

    # Write out the JSON.
    my $json = JSON->new->allow_nonref;
    
    open(O, ">".$fname) || die "!! Unable to open $fname for writing.\n";
    printf O "%s\n", $json->pretty->encode(\%jobj);
    close(O);
}

sub createProject($$$$$$$$) {
    my $ident = shift;
    my $type = shift;
    my $pi = shift;
    my $comments = shift;
    my $title = shift;
    my $impossible = shift;
    my $preferred = shift;
    my $colours = shift;

    my $date_impossible = $impossible;
    my $date_preferred = $preferred;
    if (ref $date_impossible eq "HASH") {
	# Convert this into an array of epochs.
	$date_impossible = &datehash2epochs($impossible);
    }
    if (ref $date_preferred eq "HASH") {
	$date_preferred = &datehash2epochs($preferred);
    }

    # Remove any bad characters from the comments.
    $comments =~ s/\;//g;
    
    my $rob = {
	'ident' => $ident,
	'type' => $type,
	'PI' => $pi,
	'comments' => $comments,
	'title' => $title,
	'excluded_dates' => $date_impossible,
	'preferred_dates' => $date_preferred,
	'prefers_night' => 0,
	'slot' => []
    };

    if (defined $colours->{$ident}) {
	$rob->{'colour'} = $colours->{$ident};
    }
    
    return $rob;
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

sub datehash2epochs($) {
    my $dh = shift;

    my @dates;
    
    for my $dk (keys %{$dh}) {
	push @dates, $dh->{$dk}->{'datetime'}->epoch();
    }

    return \@dates;
}
