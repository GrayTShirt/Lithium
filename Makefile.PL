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
	PREREQ_PM => {
		'Test::More' => 0,
	},
	dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
	clean               => { FILES => 'Lithium-*' },
);
