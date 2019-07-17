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
#$reqtype = "load";

if ($reqtype eq "load") {
    # We load the latest JSON file we have.
    my @files = `ls -t schedule*.json | head -n 1`;
    chomp(my $jsonfile = $files[0]);
    my $json_content = read_file($jsonfile);
    print $json_content."\n";
}
