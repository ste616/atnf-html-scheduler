#!/usr/bin/perl

# A script to compile a great deal of statistical information about
# OPAL proposals over however many semesters you want. It then outputs
# statistics as a JSON file for easy presentation on the web.
use XML::Simple;
use Data::Dumper;
use strict;
use JSON;

# Get a list of all the coversheet .xml files under this directory.
my $coversheets = &get_coversheets();

# We keep track of a bunch of things.
my @semnames = keys %{$coversheets};
my %sems;
my %observatories;
my %categories;
my %abstracts;
my %codes;
my %pi_details;
my $cloudstring = "";

# Pass the name of the observatory to assess statistics for as the
# first argument.
my $obs = $ARGV[0];

# Make the statistics per semester.
my $sn = 0;
for (my $i = 0; $i <= $#semnames; $i++) {
    $sems{$semnames[$i]} = $sn + 1;
    foreach my $k (keys %categories) {
	push @{$categories{$k}}, 0;
    }
    $abstracts{$semnames[$i]} = {};
    $codes{$semnames[$i]} = [];
    $pi_details{$semnames[$i]} = { 
	'gender' => { 'male' => 0, 'female' => 0, 'notspecified' => 0 },
	'affiliation' => { 'country' => {} },
	'phd' => 0
    };
    $sn++;
    my @obsnames = keys %{$coversheets->{$semnames[$i]}};
    for (my $j = 0; $j <= $#obsnames; $j++) {
	if ($obsnames[$j] ne $obs) {
	    next;
	}
	if (!$observatories{$obsnames[$j]}) {
	    $observatories{$obsnames[$j]} = 1;
	}
	my $allc = $coversheets->{$semnames[$i]}->{$obsnames[$j]};
	for (my $k = 0; $k <= $#{$allc->{'coversheets'}}; $k++) {
	    # Get the coversheet as a string.
	    my $cover = &get_coversheet_string(
		$allc->{'coversheets'}->[$k]);
	    my $cats = &get_categories($cover);
	    for (my $l = 0; $l <= $#{$cats}; $l++) {
		my $c = $cats->[$l]->{'content'};
		if (!defined $categories{$c}) {
		    $categories{$c} = [];
		    for (my $m = 0; $m <= $sn; $m++) {
			push @{$categories{$c}}, 0;
		    }
		}
		$categories{$c}->[$sn] += 1;
	    }
	    $abstracts{$semnames[$i]}->{$allc->{'codes'}->[$k]} =
		&get_abstracts($cover);
	    push @{$codes{$semnames[$i]}}, $allc->{'codes'}->[$k];
	    # Get details about the PI.
	    my $pidetails = &get_pi_details($cover);
	    $pi_details{$semnames[$i]}->{'gender'}->{$pidetails->{'gender'}} += 1;
	    if (!defined $pi_details{$semnames[$i]}->{'affiliation'}->{'country'}->{$pidetails->{'country'}}) {
		$pi_details{$semnames[$i]}->{'affiliation'}->{'country'}->{$pidetails->{'country'}} = 0;
	    }
	    $pi_details{$semnames[$i]}->{'affiliation'}->{'country'}->{$pidetails->{'country'}} += 1;
	    if ($pidetails->{'phd'} eq "true") {
		$pi_details{$semnames[$i]}->{'phd'} += 1;
	    }
	}
    }
}

# Output the statistics.
# This object will be turned into JSON at the end.
my %jo = ( 'observatory' => $obs );
&json_add_semesters(\%sems, \%jo);
&json_add_categories(\%categories, \%jo);
&collate_project_totals($jo{'semesterNames'}, \%codes, \%jo);
&collate_category_totals($jo{'semesterNames'}, \%sems,
			 $jo{'categoryNames'}, \%categories, \%jo);
&json_add_category_fractions($jo{'semesterNames'}, \%sems,
			     $jo{'categoryNames'}, \%categories, \%jo);
&json_add_abstracts(\%abstracts, \%jo);
&json_add_pidetails(\%pi_details, \%jo);

# Output the JSON now.
&output_json(\%jo);


sub get_categories($) {
    my $cover = shift;
    my $cstrings = $cover->{'categories'}->{'unserializable-parents'}->{'collection'}->{'string'};
    if (ref $cstrings ne "ARRAY") {
	$cstrings = [ $cstrings ];
    }
    return $cstrings;
}

sub get_coversheet_string($) {
    my $csname = shift;
    print "getting coversheet information from file $csname\n";
    
    my $coverstring = `iconv -f utf-8 -t utf-8 -c $csname`;
    $coverstring =~ s/\&\#.*?\;//g;
    my $cover = XMLin($coverstring, ForceContent => 1);
    return $cover;
}

sub get_coversheets() {

    # Find the cover sheets.
    my $coversheets = `find . -name "coversheet.xml"`;
    my @coversheets = split(/\n/, $coversheets);

    # Split them up by observatory and semester.
    my $rlist = {};
    for (my $i = 0; $i <= $#coversheets; $i++) {
	my @e = split(/\//, $coversheets[$i]);
	if (($#e != 4) || ($e[4] ne "coversheet.xml")) {
	    # Got no idea what this is.
	    next;
	}
	my $sem = $e[1];
	my $obs = $e[2];
	my $proj = $e[3];
	if (!defined $rlist->{$sem}) {
	    $rlist->{$sem} = {};
	}
	if (!defined $rlist->{$sem}->{$obs}) {
	    $rlist->{$sem}->{$obs} = { 'codes' => [], 
				       'coversheets' => [] };
	}
	push @{$rlist->{$sem}->{$obs}->{'coversheets'}}, $coversheets[$i];
	push @{$rlist->{$sem}->{$obs}->{'codes'}}, $proj;
    }

    return $rlist;
}

sub get_abstracts($) {
    my $cs = shift;

    return { 'abstract' => $cs->{'abstractText'}->{'content'},
	     'outreach' => $cs->{'outreachAbstractText'}->{'content'} };
}

sub get_pi_details($) {
    my $cs = shift;

    my %rv;

    $rv{'gender'} = lc($cs->{'principalInvestigator'}->{'gender'}->{'content'});
    # TODO: if non-specified, guess based on name.
    if ($rv{'gender'} eq "not given") {
	$rv{'gender'} = "notspecified";
    }

    $rv{'country'} = lc($cs->{'principalInvestigator'}->{'affiliation'}->{'country'}->{'name'}->{'content'});
    
    $rv{'phd'} = $cs->{'principalInvestigator'}->{'phdStudent'}->{'content'};
    
    return \%rv;
}

sub json_add_semesters($$) {
    my $semref = shift;
    my $jref = shift;

    # Add a sorted list of the semesters to the JSON.
    my @semester_names = sort keys %{$semref};
    $jref->{'semesterNames'} = \@semester_names;

}

sub json_add_categories($$) {
    my $catref = shift;
    my $jref = shift;

    # Add a sorted list of the categories to the JSON.
    my @category_names = sort keys %{$catref};
    $jref->{'categoryNames'} = \@category_names;
    
}

sub json_add_pidetails($$) {
    my $piref = shift;
    my $jref = shift;

    # Add details about the principal investigators to the JSON.
    $jref->{'principalInvestigators'} = $piref;
}

sub collate_category_totals($$$$$) {
    my $semnames = shift;
    my $semref = shift;
    my $catnames = shift;
    my $catref = shift;
    my $jref = shift;

    my %semester_totals;
    # Work out the total number of proposals of each category in
    # each semester.
    for (my $i = 0; $i <= $#{$semnames}; $i++) {
	$semester_totals{$semnames->[$i]} = 0;
	for (my $j = 0; $j <= $#{$catnames}; $j++) {
	    $semester_totals{$semnames->[$i]} += 
		$catref->{$catnames->[$j]}->[$semref->{$semnames->[$i]}];
	}
    }

    $jref->{'semesterCategoryTotals'} = \%semester_totals;
}

sub collate_project_totals($$$) {
    my $semnames = shift;
    my $coderef = shift;
    my $jref = shift;

    my %semester_nprojects;
    # Collate the total number of proposals in each semester.
    for (my $i = 0; $i <= $#{$semnames}; $i++) {
	$semester_nprojects{$semnames->[$i]} =
	    ($#{$coderef->{$semnames->[$i]}} + 1);
    }

    $jref->{'semesterNumProjects'} = \%semester_nprojects;
}

sub json_add_category_fractions($$$$$) {
    my $semnames = shift;
    my $semref = shift;
    my $catnames = shift;
    my $catref = shift;
    my $jref = shift;

    my %catf;
    for (my $i = 0; $i <= $#{$catnames}; $i++) {
	$catf{$catnames->[$i]} = {};
	for (my $j = 0; $j <= $#{$semnames}; $j++) {
	    my $f = 0;
	    if ((defined $jref->{'semesterCategoryTotals'}) &&
		(defined $jref->{'semesterCategoryTotals'}->{$semnames->[$j]}) &&
		($jref->{'semesterCategoryTotals'}->{$semnames->[$j]} > 0)) {
		$f = $catref->{$catnames->[$i]}->[$semref->{$semnames->[$j]}] /
		    $jref->{'semesterCategoryTotals'}->{$semnames->[$j]};
		$catf{$catnames->[$i]}->{$semnames->[$j]} = $f * 100;
	    }
	}
    }

    $jref->{'categoryFractions'} = \%catf;
}

sub json_add_abstracts($$) {
    my $absref = shift;
    my $jref = shift;

    # Add all the abstracts to the JSON output.
    $jref->{'abstracts'} = $absref;
}

sub output_json($) {
    my $jref = shift;

    my $json = JSON->new->allow_nonref;
    
    # Form the filename.
    my $fname = sprintf ("%s_statistics.json",
			 $jref->{'observatory'});
    open(O, ">".$fname) || die "Unable to open $fname for writing\n";
    printf O "%s\n", $json->pretty->encode($jref);
    close(O);
}
