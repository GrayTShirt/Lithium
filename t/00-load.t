#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'lithium' );
}

diag( "Testing lithium $lithium::VERSION, Perl $], $^X" );
