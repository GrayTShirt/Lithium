#!/usr/bin/perl -T

use strict;
use warnings;
use Test::More;

BEGIN {
	use_ok('lithium');
}

diag("Testing lithium $lithium::VERSION, Perl $], $^X");

done_testing;
