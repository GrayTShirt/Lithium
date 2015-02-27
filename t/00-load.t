#!/usr/bin/perl -T

use strict;
use warnings;

use Test::More;

BEGIN {
	use_ok('Lithium');
	use_ok('Lithium::Cache');
	use_ok('Lithium::Daemon');
}

diag("Testing Lithium $Lithium::VERSION, Perl $], $^X");

done_testing;
