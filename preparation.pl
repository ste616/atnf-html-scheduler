#!/usr/bin/perl

use strict;

# This script does all the necessary preparatory work for the semester
# specified as the first argument.
my $sem = lc($ARGV[0]); # Should look like 2019OCT
my $semname = uc($sem);
print "== Preparing for semester $semname\n";

# Step 1: make the directories.
printf "== Checking for directory %s... ", $sem;
if (-e $sem) {
    print "already exists.\n";
} else {
    system "mkdir ".$sem;
    if (-e $sem) {
	print "directory made.\n";
    } else {
	print "failed!\n";
	exit;
    }
}

# Step 2: download the OPAL files.
printf "== Downloading proposals from OPAL...\n";
## TODO

# Step 3: extract the proposals.
printf "== Extracting proposals...\n";
my $exp_file = $semname."-proposals.zip";
if (-e $exp_file) {
    printf "   found file %s\n", $exp_file;
    system "unzip -qq $exp_file";
} else {
    printf "   unable to find file %s!\n", $exp_file;
    exit;
}
