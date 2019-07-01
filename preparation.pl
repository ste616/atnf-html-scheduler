#!/usr/bin/perl

use XML::Simple;
use String::ShellQuote;
use Astro::Coord;
use Astro::Time;
use POSIX;
use strict;

# This script does all the necessary preparatory work for the semester
# specified as the first argument.
my $sem = lc($ARGV[0]); # Should look like 2019OCT
my $semname = uc($sem);
print "== Preparing for semester $semname\n";

# Step 1: make the directories.
&makeMasterDirectory($sem);

# Step 2: download the OPAL files.
printf "== Downloading proposals from OPAL...\n";
## TODO

# Step 3: extract the proposals.
&extractProposalArchive($sem);

# Step 4. download the proposal mapping file.
my $mapfile = &downloadProposalMapping($sem);
## TODO

# Step 5. rename each proposal as required.
&renameProposals($sem);

### SUBROUTINES FOLLOW
### SHOULD ALL BE MOVED TO ANOTHER MODULE AT SOME POINT

sub makeMasterDirectory($) {
    my $semdir = shift;

    printf "== Checking for directory %s... ", $semdir;
    if (-d $semdir) {
	print "already exists.\n";
    } else {
	system "mkdir ".$semdir;
	if (-d $semdir) {
	    print "directory made.\n";
	} else {
	    print "failed!\n";
	    exit;
	}
    }
    return;
}

sub extractProposalArchive($) {
    my $semdir = shift;
    my $semdname = uc($semdir);
    
    printf "== Extracting proposals...\n";
    my $exp_file = $semdir."/".$semdname."S-proposals.zip";
    if (-e $exp_file) {
	printf "   found file %s\n", $exp_file;
	system "unzip -qq $exp_file";
    } else {
	printf "   unable to find file %s!\n", $exp_file;
	exit;
    }
    return;
}

sub downloadProposalMapping($) {
    my $semester = shift;

    printf "== Downloading proposal information from OPAL...\n";
    my $mapfile = $semester."/Download Proposals.html";

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
