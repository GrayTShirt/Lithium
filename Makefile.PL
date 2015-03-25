#!/usr/bin/perl

use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
	NAME                => 'Lithium',
	AUTHOR              => q{Dan Molik <dmolik@synacor.com>},
	VERSION_FROM        => 'lib/Lithium.pm',
	ABSTRACT_FROM       => 'lib/Lithium.pm',
	($ExtUtils::MakeMaker::VERSION >= 6.3002
		? ('LICENSE'=> 'perl')
		: ()),
	PL_FILES            => {},
	EXE_FILES           => [
		                     'bin/lithium',
		                   ],
	TEST_REQUIRES => {
		'Test::More'             => 0,
		'Test::Lithium'          => 0,
	},
	PREREQ_PM => {
		'Dancer'                 => 0,
		'Dancer::Logger::Syslog' => 0,
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
