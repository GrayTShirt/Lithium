#!/usr/bin/perl -T

use strict;
use warnings;

use Test::More;

BEGIN { use_ok('Lithium'); }

diag("Testing Lithium $Lithium::VERSION, Perl $], $^X");

done_testing;
