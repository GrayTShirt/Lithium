#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Deep;

use Lithium;

diag "Testing lithium-$Lithium::VERSION Daemonization";

no strict 'refs';
cmp_deeply(${*{"Lithium::CONFIG"}}, {
	'cache_file'   => "/tmp/lithium-cache.tmp",
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
	}, "Check the default configuration");
use strict 'refs';

Lithium::_configure(config => 't/data/config', debug => 1);
no strict 'refs';
cmp_deeply(${*{"Lithium::CONFIG"}}, {
	'cache_file'   => "/tmp/lithium-cache.tmp",
	'keepalive'    => "150",
	'log'          => "syslog",
	'log_facility' => "daemon",
	'config'       => 't/data/config',
	'idle_session' =>  5,
	'log_file'     => "/var/log/lithium.log",
	'log_level'    => "debug",
	'pidfile'      => "/var/run/lithium",
	'port'         => "8910",
	'uid'          => "lithium",
	'gid'          => "lithium",
	'worker_splay' =>  5,
	'workers'      =>  3,
	 debug         =>  1,
	}, "Check the default configuration");
use strict 'refs';

done_testing;
