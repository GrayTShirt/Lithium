package Lithium;

use Cache::FastMmap;

our $CACHE = Cache::FastMmap->new(
	share_file     => '/tmp/lithium-cache.tmp', # $CONFIG->{cache_file},
	expire_time    =>  0,
	unlink_on_exit =>  0,
	empty_on_exit  =>  0,
	page_size      => '512k', # size of perl objects to store
	num_pages      =>  5,     # num of objects
);
our $NODES    = $CACHE->get('NODES');
our $SESSIONS = $CACHE->get('SESSIONS');
our $STATS    = $CACHE->get('STATS');
our $OLD      = $CACHE->get('OLD');
our $CONFIG;

package Lithium::Cache;

use strict;
use warnings;

use Cache::FastMmap;

no strict 'refs';
*{"Lithium::NODES"} = sub {
	my ($new) = @_;
	if ($new) {
		$NODES = $new;
		$CACHE->set('NODES', $new);
	} else {
		$NODES = $CACHE->get('NODES');
	}
	return $NODES;
};
*{"Lithium::STATS"} = sub {
	my ($new) = @_;
	if ($new) {
		$STATS = $new;
		$CACHE->set('STATS', $new);
	} else {
		$STATS = $CACHE->get('STATS');
	}
	return $STATS;
};
*{"Lithium::SESSIONS"} = sub {
	my ($new) = @_;
	if ($new) {
		$SESSIONS = $new;
		$CACHE->set('SESSIONS', $new);
	} else {
		$SESSIONS = $CACHE->get('SESSIONS');
	}
	return $SESSIONS;
};
*{"Lithium::OLD"} = sub {
	my ($new) = @_;
	if ($new) {
		$OLD = $new;
		$CACHE->set('OLD', $new);
	} else {
		$OLD = $CACHE->get('OLD');
	}
	return $OLD;
};
*{"Lithium::CONFIG"} = sub {
	my ($new) = @_;
	if ($new) {
		$CONFIG = $new;
		$CACHE->set('CONFIG', $new);
	} else {
		$CONFIG = $CACHE->get('CONFIG');
	}
	return $CONFIG;
};
use strict 'refs';
1;
