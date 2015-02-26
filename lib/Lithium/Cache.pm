package Lithium::Cache;

use strict;
use warnings;

use Cache::FastMmap;

BEGIN {
	no strict 'refs'; no warnings 'once';
	${*{"Lithium::CACHE"}} = Cache::FastMmap->new(
		share_file     => ${*{"Lithium::CONFIG"}}->{cache_file},
		expire_time    =>  0,
		unlink_on_exit =>  0,
		empty_on_exit  =>  0,
		page_size      => '512k', # size of perl objects to store
		num_pages      =>  5,     # num of objects
	);
	for my $cache (qw/NODES OLD SESSIONS STATS/) {
		${*{"Lithium::$cache"}} = ${*{"Lithium::CACHE"}}->get($cache);
	}
	use strict 'refs'; use warnings 'once';
}

no strict 'refs';
for my $sub (qw/CONFIG NODES OLD SESSIONS STATS/){
	*{"Lithium::$sub"} = sub {
		my ($new) = @_;
		if ($new) {
			${*{"Lithium::$sub"}} = $new;
			${*{"Lithium::CACHE"}}->set($sub, $new);
		} else {
			${*{"Lithium::$sub"}} = ${*{"Lithium::CACHE"}}->get($sub);
		}
		return ${*{"Lithium::$sub"}};
	};
}
use strict 'refs';

=head1 NAME

Lithium::Cache - A shared memory mapped space.

=head2 SYNOPSIS

Lithium::Cache is cache object store, acessing and setting state information,
to a memory mapped file. Dual purpose functions are used to set and retrieve
data objects stored in memory. A filename, provided by the configuration must
be given to synchronize the memory locations.

=head2 FUNCTIONS

All functions are similar in that they set the cache for a particular data
object of the same name, or if no parameters are given, they fetch the data
same data object from the cache.

=over

=item CONFIG

=item NODES

=item OLD

=item SESSIONS

=item STATS

=back

=head2 REQUIRED MODULES

=over

=item L<Cache::FastMmap|https://metacpan.org/pod/Cache::FastMmap>

=back

=head2 AUTHOR

Dan Molik C<< <dmolik@synacor.com> >>

=head2 COPYRIGHT & LICENSE

Copyright 2015 Dan Molik <dmolik@synacor.com>

Licensed under the GNU GPL v3.

=cut

1;
