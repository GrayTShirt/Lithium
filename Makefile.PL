#!/usr/bin/perl

use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
	NAME                => 'Lithium',
	AUTHOR              => q{Dan Molik <dan@d3fy.net>},
	VERSION_FROM        => 'lib/Lithium.pm',
	ABSTRACT_FROM       => 'lib/Lithium.pm',
	($ExtUtils::MakeMaker::VERSION >= 6.3002
		? ('LICENSE'=> 'perl')
		: ()),
	PL_FILES            => {},
	EXE_FILES           => [
		                     'bin/lithium',
		                   ],
	PREREQ_PM => {
		'Test::More'             => 0,
		'Dancer'                 => 0,
		'Dancer::Logger::Syslog' => 0,
		'Starman'                => 0,
		'Cache::FastMmap'        => 0,
		'YAML::XS'               => 0,
		'LWP::UserAgent'         => 0,
		'Time::HiRes'            => 0,
		'Devel::Size'            => 0,
		'HTTP::Request::Common'  => 0,
	},
	dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
	clean               => { FILES => 'Lithium-*' },
);
