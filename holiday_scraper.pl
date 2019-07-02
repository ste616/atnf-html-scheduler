#!/usr/bin/perl

use URI;
use Web::Scraper;
use Encode;
use DateTime;
use strict;

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
printf "found %d rows\n", $nrows;
my $ncols = ($#{$res->{dates}} + 1) / $nrows;
printf "there must be %d columns\n", $ncols;

# Form the dates.
for (my $i = 1; $i < $ncols; $i++) {
    my $year = $res->{dates}->[$i] * 1;
    for (my $j = 1; $j < $nrows; $j++) {
	my $n = $j * $ncols + $i;
	my $d = Encode::encode("ascii", $res->{dates}->[$n]);
	$d =~ s/\?//g;
	printf "d is \"%s\"\n", $d;
	$d =~ s/^.*\,\s*(.*)$/$1/;
	my @de = split(/\s+/, $d);
	my $day = $de[0];
	my $month = &month2number($de[1]);
	if ($d ne "") {
	    printf "%4d - %02d - %02d\n", $year, $month, $day;
	    my $dt = DateTime->new(
		year => $year, month => $month, day => $day,
		hour => 8, time_zone => 'Australia/Sydney' );
	    printf "this is weekday %d\n", $dt->day_of_week;
	#   if ($dt->is_dst()) {
	#	printf "day has DST\n";
	#    }
	}
    }
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
    }
    return 0;
}
