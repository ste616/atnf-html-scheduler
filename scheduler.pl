#!/usr/bin/perl

use CGI qw (:standard);
use CGI::Carp qw( fatalsToBrowser );
use JSON;
use File::Slurp;
use DateTime;
use strict;

$CGI::POST_MAX = 2500000;
$CGI::DISABLE_UPLOADS = 0;

my $q = CGI->new;

print $q->header(
    -type => "application/json"
    );

my $reqtype = $q->param('request');
my $schedstring = $q->param('schedule');
my $obs = $q->param('observatory');
my $term = $q->param('term');
if (!defined $term) {
    $term = "";
}
my $errstring = "";

if ($reqtype eq "load") {
    print &loadLatest($obs, $term)."\n";
} elsif ($reqtype eq "loadtime") {
    my $jstring = &loadLatest($obs, $term);
    my $j = from_json($jstring);
    my $oj = { 'modificationTime' => $j->{'modificationTime'} };
    my $ojstring = to_json($oj);
    print $ojstring."\n";
} elsif ($reqtype eq "save") {
    my $retjson = { 'action' => 'save', "received" => $schedstring };
    if (!defined $schedstring) {
	$retjson->{'error'} = "No schedule given.";
    } else {
	my $rv = &saveSchedule($obs, $term, $schedstring);
	if ($rv == 1) {
	    $retjson->{"error"} = "Unable to save: ".$errstring;
	} else {
	    $retjson->{"status"} = "Success.";
	}
    }
    print to_json($retjson)."\n";
} elsif ($reqtype eq "listsemesters") {
    my $retjson = { 'action' => 'listsemesters', 'obs' => $obs };
    my @semesters = &listSemesters($obs);
    $retjson->{'semesters'} = \@semesters;
    print to_json($retjson)."\n";
} elsif ($reqtype eq "authenticate") {
    my $retjson = { 'authenticated' => 0 };
    my @authtokens = &loadAuthFile();
    for (my $i = 0; $i <= $#authtokens; $i++) {
	if ($q->param('auth') eq $authtokens[$i]) {
	    $retjson->{'authenticated'} = 1;
	    last;
	}
    }
    print to_json($retjson)."\n";
}

sub loadAuthFile() {
    my $authfile = "/usr/lib/cgi-bin/.auth";
    open(A, $authfile);
    my @authtokens;
    while(<A>) {
	chomp(my $line = $_);
	push @authtokens, $line;
    }
    close(A);

    return @authtokens;
}

sub loadLatest($$) {
    my $obs = shift;
    my $term = shift;

    my $pattern = "schedule-$obs";
    if ($term ne "") {
	$pattern .= "-$term";
    }
    $pattern .= "*.json";
    # Load the latest JSON file we have.
    my @files = `ls -t $pattern | head -n 1`;
    chomp(my $jsonfile = $files[0]);
    my $json_content = read_file($jsonfile);
    return $json_content;
}

sub listSemesters($) {
    my $obs = shift;
    
    # Return a list of the semesters that we have schedules for.
    my @semesters;
    open(L, "-|") || exec "ls -t schedule-$obs*.json";
    while(<L>) {
	chomp;
	my $line = $_;
	if (($line =~ /^schedule\-$obs\-(.*)\-.*\.json$/) ||
	    ($line =~ /^schedule\-$obs\-([^-]*)\.json$/)) {
	    my $s = $1;
	    my $sf = 0;
	    for (my $i = 0; $i <= $#semesters; $i++) {
		if ($semesters[$i] eq $s) {
		    $sf = 1;
		    last;
		}
	    }
	    if ($sf == 0) {
		push @semesters, $s;
	    }
	}
    }
    close(L);

    return @semesters;
}

sub saveSchedule($$$) {
    my $obs = shift;
    my $term = shift;
    my $schedstring = shift;

    # Check that what we have is actually a schedule.
    my $cjson = from_json($schedstring);
    #print Dumper $cjson;
    if ((!defined $cjson->{'program'}->{'observatory'}->{'observatory'}) ||
	(!defined $cjson->{'program'}->{'term'}->{'term'})) {
	# Bad schedule.
	$errstring = "bad schedule\n";
	return 1;
    } elsif (($obs ne $cjson->{'program'}->{'observatory'}->{'observatory'}) ||
	     ($term ne $cjson->{'program'}->{'term'}->{'term'})) {
	if ($obs ne $cjson->{'program'}->{'observatory'}) {
	    $errstring = "unmatched observatory ".$obs." cf ".
		$cjson->{'program'}->{'observatory'}->{'observatory'};
	} else {
	    $errstring = "unmatched semester ".$term." cf ".
		$cjson->{'program'}->{'term'}->{'term'};
	}
	#$errstring = "unmatched schedule\n";
	return 1;
    }
    
    # Create a new file. We put the date in this filename.
    my $ndate = DateTime->now();
    my $outfile = sprintf "schedule-%s-%s-%4d%02d%02d_%02d%02d%02d.json",
	$cjson->{'program'}->{'observatory'}->{'observatory'}, 
	$cjson->{'program'}->{'term'}->{'term'},
	$ndate->year(), $ndate->month(), $ndate->day(), $ndate->hour(),
	$ndate->minute(), $ndate->second();
    open(O, ">".$outfile) || return 1;
    print O $schedstring."\n";
    close(O);

    return 0;
}
