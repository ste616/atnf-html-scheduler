#!/usr/bin/perl

use HTTP::Proxy;
use HTTP::Recorder;
use strict;

my $proxy = HTTP::Proxy->new();

my $agent = new HTTP::Recorder;

$agent->file("/home/ste616/usr/src/atnf-html-scheduler/opalinteraction");

$proxy->agent($agent);
$proxy->start();

1;
