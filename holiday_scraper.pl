#!/usr/bin/perl

use URI;
use Web::Scraper;
use Encode;

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
for my $date (@{$res->{dates}}) {
    print Encode::encode("utf8", "$date\n");
}
