#!/usr/bin/perl -wT

use CGI qw (:standard);
#use CGI::Carp qw( fatalsToBrowser );
use CGI::Carp;
use JSON;
use DateTime;
use strict;

$CGI::POST_MAX = 2500000;
$CGI::DISABLE_UPLOADS = 0;

my $q = CGI->new;
my $root_dir = "/n/ste616/usr/schedules";
$ENV{"PATH"} = "/bin:/usr/bin";

print $q->header(
    -type => "application/json"
    );

my $reqcheck = $q->param('request');
# Check against allowed request types.
my @allowed_requests = ( "load", "loadtime", "save", "listsemesters",
			 "authenticate", "listobservatories", "updateObservatories" );
my $reqtype = "";
for (my $i = 0; $i <= $#allowed_requests; $i++) {
    if ($reqcheck eq $allowed_requests[$i]) {
	$reqtype = $allowed_requests[$i];
	last;
    }
}
if ($reqtype eq "") {
    exit;
}

# We can't really sanitise the schedule string, since it can have all sorts
# of things in there. But this string is never executed or acted upon, just
# written to file.
my $schedstring = $q->param('schedule');

# Get the list of observatories.
my @observatories = &listObservatories();
my $obscheck = $q->param('observatory');
my $obs;
if ($reqtype ne "updateObservatories") {
    # Check if the observatory is one we know about.
    for (my $i = 0; $i <= $#observatories; $i++) {
	if ($obscheck eq $observatories[$i]->{'id'}) {
	    $obs = $observatories[$i]->{'id'};
	    last;
	}
    }
} else {
    # We sanitise the name of the new observatory.
    $obs = &sanitise_input($obscheck);
}

my $term = &sanitise_input(scalar($q->param('term')));
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
} elsif ($reqtype eq "listobservatories") {
    my $retjson = { 'action' => 'listobservatories' };
    $retjson->{'observatories'} = \@observatories;
    print to_json($retjson)."\n";
} elsif ($reqtype eq "updateObservatories") {
    # Check we have a valid authentication token.
    my @authtokens = &loadAuthFile();
    my $isauthed = 0;
    for (my $i = 0; $i <= $#authtokens; $i++) {
	if ($q->param('auth') eq $authtokens[$i]) {
	    $isauthed = 1;
	    last;
	}
    }
    my $retjson = { 'action' => "writeobservatories" };
    if ($isauthed) {
	&writeObservatories($q->param('observatories'));
	$retjson->{'success'} = 1;
    } else {
	$retjson->{'success'} = 0;
    }
    print to_json($retjson)."\n";
}

sub loadAuthFile() {
    my $authfile = $root_dir."/.auth";
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

    my $pattern = $root_dir."/schedule-$obs";
    if ($term ne "") {
	$pattern .= "-$term";
    }
    $pattern .= "*.json";
    # Allow for escaping special characters.
    $pattern =~ s/\s/\\ /g;
    # Load the latest JSON file we have.
    my @files = `ls -t $pattern | head -n 1`;
    chomp(my $jsonfile = $files[0]);
    open(J, $jsonfile);
    my $json_content = do { local $/; <J> };
    close(J);
    return $json_content;
}

sub listSemesters($) {
    my $obs = shift;
    
    # Return a list of the semesters that we have schedules for.
    my @semesters;
    open(L, "-|") || exec "ls -t ".$root_dir."/schedule-$obs*.json";
    while(<L>) {
	chomp;
	my $line = $_;
	if (($line =~ /schedule\-$obs\-(.*)\-.*\.json$/) ||
	    ($line =~ /schedule\-$obs\-([^-]*)\.json$/)) {
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

sub writeObservatories($) {
    my $obsarrjson = shift;
    my $obsarr = from_json($obsarrjson);
    my $jsonfile = $root_dir."/.observatories";
    my $obsobj = { "observatories" => $obsarr };
    open(J, ">".$jsonfile);
    print J to_json($obsobj);
    close(J);
}

sub listObservatories() {
    #my $obs = shift;

    # Return a list of the observatories we know about.
    my @observatories;
    my $jsonfile = $root_dir."/.observatories";
    open(J, $jsonfile);
    chomp(my $jcontentt = <J>);
    close(J);
    my $json_regex = qr/[a-zA-Z0-9\:\+\-\_\,\.\s\"\{\}\[\]\*]+/;

    my $jcontent = "";
    if ($jcontentt =~ /($json_regex)/) {
	$jcontent = $1;
    }
    
    my $jobj = from_json($jcontent);
    return @{$jobj->{'observatories'}};
}

sub saveSchedule($$$) {
    my $obs = shift;
    my $term = shift;
    my $schedstring = shift;

    # Check that what we have is actually a schedule.
    my $cjson = from_json($schedstring);
    #print Dumper $cjson;
    my $outobs = &sanitise_input($cjson->{'program'}->{'observatory'}->{'observatory'});
    my $outterm = &sanitise_input($cjson->{'program'}->{'term'}->{'term'});
    if (($outobs eq "") || ($outterm eq "")) {
	# Bad schedule.
	$errstring = "bad schedule\n";
	return 1;
    } elsif (($obs ne $outobs) || ($term ne $outterm)) {
	if ($obs ne $outobs) {
	    $errstring = "unmatched observatory ".$obs." cf ".
		$outobs;
	} else {
	    $errstring = "unmatched semester ".$term." cf ".
		$outterm;
	}
	#$errstring = "unmatched schedule\n";
	return 1;
    }
    
    # Create a new file. We put the date in this filename.
    my $ndate = DateTime->now();
    my $outfile = sprintf("%s/schedule-%s-%s-%4d%02d%02d_%02d%02d%02d.json",
			  $root_dir,
			  $obs,
			  $term,
			  $ndate->year(), $ndate->month(), $ndate->day(), 
			  $ndate->hour(),
			  $ndate->minute(), $ndate->second());
    open(O, ">".$outfile) || return 1;
    print O $schedstring."\n";
    close(O);

    return 0;
}

sub sanitise_input {
    my $u = shift;

    if (!defined $u) {
	return "";
    }
    
    # We make sure bad characters don't get in here.
    my $goodchars = qr/[a-zA-Z0-9\:\+\-\_\,\.\s]+/;
    my $badchars = qr/[^a-zA-Z0-9\:\+\-\_\,\.\s]/;

    $u =~ s/$badchars//g;

    my $c = "";
    if ($u =~ /($goodchars)/) {
	$c = $1;
    }

    # Put in a length limit of 40 characters.
    if (length($c) > 40) {
	# This is bad and we kill it.
	$c = "";
    }
    
    return $c;
}
