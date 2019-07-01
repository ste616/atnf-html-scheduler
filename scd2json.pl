#!/usr/bin/perl

use XML::LibXML;
use JSON;
use Data::Dumper;
use strict;

# Load in the SCD file.
my $scd_file = $ARGV[0];

open(A, $ARGV[0]) || die "cannot open $ARGV[0]\n";
my $scdlines = "";
while(<A>) {
    $scdlines .= $_;
}
close(A);

my $dom = XML::LibXML->load_xml(string => $scdlines);

