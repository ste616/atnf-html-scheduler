#!/usr/bin/perl

use CGI;
use JSON;
use File::Slurp;
use strict;

my $q = CGI->new;

print $q->header(
    -type => "application/json"
    );
my $reqtype = $q->param('request');
#$reqtype = "loadtime";

if ($reqtype eq "load") {
    print &loadLatest()."\n";
} elsif ($reqtype eq "loadtime") {
    my $jstring = &loadLatest();
    my $j = from_json($jstring);
    my $oj = { 'modificationTime' => $j->{'modificationTime'} };
    my $ojstring = to_json($oj);
    print $ojstring."\n";
}

sub loadLatest() {
    # Load the latest JSON file we have.
    my @files = `ls -t schedule*.json | head -n 1`;
    chomp(my $jsonfile = $files[0]);
    my $json_content = read_file($jsonfile);
    return $json_content;
}
