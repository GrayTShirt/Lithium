#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Deep;
use Lithium;

my $cache_file = 't/data/cache.tmp';

ok(!-e $cache_file, "The cache file [$cache_file] should not exist");
Lithium::_configure(
	cache_file => $cache_file,
);
ok(-r $cache_file, "The cache file [$cache_file] should now be readable");

# We only need to do one of STATS SESSIONS NODES or OLD
# because they are all the same.
cmp_deeply(Lithium::STATS(), undef, "The default stats object is undef");
Lithium::STATS({
	layer1 => { key2 => 'val2' },
	});
cmp_deeply(Lithium::STATS(), {layer1 => { key2 => 'val2' }}, "The new object should be multi-layered");

# CONFIG is handled slightly differently
cmp_deeply(Lithium::CONFIG(), {
	'cache_file'   => "t/data/cache.tmp",
	'config'       => "/etc/lithium.conf",
	'keepalive'    => "150",
	'log'          => "syslog",
	'log_facility' => "daemon",
	'log_file'     => "/var/log/lithium.log",
	'log_level'    => "info",
	'pidfile'      => "/var/run/lithium",
	'port'         => "8910",
	'uid'          => "lithium",
	'gid'          => "lithium",
	'worker_splay' => "30",
	'workers'      =>  3,
	}, "Check the default config object, and ensure it's set after _configure call");

unlink $cache_file;
done_testing;
