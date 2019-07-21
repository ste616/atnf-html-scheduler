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

#open(D, ">debug.txt");
#print D $q->param;
#print D "\n";

my $reqtype = $q->param('request');
#$reqtype = "loadtime";
#$reqtype = "save";
my $schedstring = $q->param('schedule');
#$schedstring = "{ \"program\": { \"observatory\": \"atca\", \"term\": { \"term\": \"2019OCT\" } } }";
#print $reqtype."\n".$schedstring."\n";
#print D $reqtype."\n";
#if (defined $schedstring) {
#    print D $schedstring."\n";
#}
#close(D);


if ($reqtype eq "load") {
    print &loadLatest()."\n";
} elsif ($reqtype eq "loadtime") {
    my $jstring = &loadLatest();
    my $j = from_json($jstring);
    my $oj = { 'modificationTime' => $j->{'modificationTime'} };
    my $ojstring = to_json($oj);
    print $ojstring."\n";
} elsif ($reqtype eq "save") {
    my $retjson = { 'action' => 'save', "received" => $schedstring };
    if (!defined $schedstring) {
	$retjson->{'error'} = "No schedule given.";
    } else {
	my $rv = &saveSchedule($schedstring);
	if ($rv == 1) {
	    $retjson->{"error"} = "Unable to save.";
	} else {
	    $retjson->{"status"} = "Success.";
	}
    }
    print to_json($retjson)."\n";
}

sub loadLatest() {
    # Load the latest JSON file we have.
    my @files = `ls -t schedule*.json | head -n 1`;
    chomp(my $jsonfile = $files[0]);
    my $json_content = read_file($jsonfile);
    return $json_content;
}

sub saveSchedule($) {
    my $schedstring = shift;

    # Check that what we have is actually a schedule.
    my $cjson = from_json($schedstring);
    #print Dumper $cjson;
    if ((!defined $cjson->{'program'}->{'observatory'}) ||
	(!defined $cjson->{'program'}->{'term'}->{'term'})) {
	# Bad schedule.
	print "bad schedule\n";
	return 1;
    }
    
    # Create a new file. We put the date in this filename.
    my $ndate = DateTime->now();
    my $outfile = sprintf "schedule-%s-%s-%4d%02d%02d_%02d%02d%02d.json",
    $cjson->{'program'}->{'observatory'}, $cjson->{'program'}->{'term'}->{'term'},
    $ndate->year(), $ndate->month(), $ndate->day(), $ndate->hour(),
    $ndate->minute(), $ndate->second();
    open(O, ">".$outfile) || return 1;
    print O $schedstring."\n";
    close(O);

    return 0;
}
