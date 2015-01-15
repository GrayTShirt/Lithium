package lithium;

use strict;
use warnings;

use Dancer;
use Dancer::Logger::Syslog;
use Plack::Handler::Starman;
use Cache::FastMmap;

use YAML::XS qw/LoadFile/;
use POSIX qw/:sys_wait_h setgid setuid/;
use Getopt::Long;
use Time::HiRes qw/time/;

use LWP::UserAgent;
use HTTP::Request::Common ();
# Add a delete function to LWP, for continuity!
no strict 'refs';
if (! defined *{"LWP::UserAgent::delete"}{CODE}) {
	*{"LWP::UserAgent::delete"} =
		sub {
			my ($self, $uri) = @_;
			$self->request(HTTP::Request::Common::DELETE($uri));
		};
}
use strict 'refs';

our $VERSION = '1.0.0';

my $agent    = LWP::UserAgent->new(agent => __PACKAGE__."-$VERSION");
$agent->default_header(Content_Type => "application/json;charset=UTF-8");
# pretty sure this violates RFC 2616, oh well
push @{$agent->requests_redirectable}, 'POST';


# Defaults
my %CONFIG = (
	log          => 'syslog',
	log_level    => 'debug',
	log_facility => 'daemon',
	workers      =>  3,
	keepalive    =>  150,
	port         =>  8910,
	gid          => 'lithium',
	uid          => 'lithium',
	pidfile      => '/var/run/lithium.pid',
	cache_file   => '/tmp/lithium-cache.tmp',
);

my %OPTIONS = (
	config  => '/etc/lithium.conf',
);

my $config_file;
if (-f $OPTIONS{config}) {
	eval { $config_file = LoadFile($OPTIONS{config}); 1 }
		or die "Failed to load $OPTIONS{config}: $@\n";
} else {
	print STDERR "No configuration file found starting|stopping with defaults\n";
}

for (keys %$config_file) {
	$CONFIG{$_} = $config_file->{$_};
	$CONFIG{$_} = $OPTIONS{$_} if exists $OPTIONS{$_};
}
for (keys %OPTIONS) {
	$CONFIG{$_} = $OPTIONS{$_} if exists $OPTIONS{$_};
}

my $CACHE = Cache::FastMmap->new(
	share_file     => $CONFIG{cache_file},
	expire_time    =>  0,
	unlink_on_exit =>  0,
	empty_on_exit  =>  0,
	page_size      => '512k', # size of perl objects to store
	num_pages      =>  4,     # num of objects
);
my $NODES    = $CACHE->get('NODES');
my $SESSIONS = $CACHE->get('NODES');
my $STATS    = $CACHE->get('STATS');

no strict 'refs';
# Build in some shim functions
*{"NODES"}         = sub { $NODES = $CACHE->get('NODES'); return $NODES };
*{"NODES::set"}    = sub { shift; $CACHE->set('NODES', scalar @_ ? @_ : $NODES) };
*{"SESSIONS"}      = sub { $SESSIONS = $CACHE->get('SESSIONS'); return $SESSIONS };
*{"SESSIONS::set"} = sub { shift; $CACHE->set('SESSIONS', scalar @_ ? @_ : $SESSIONS) };
*{"STATS"}         = sub { $STATS = $CACHE->get('STATS'); return $STATS };
*{"STATS::set"}    = sub { shift; $CACHE->set('STATS', scalar @_ ? @_ : $STATS) };
use strict 'refs';

if ($CONFIG{log} =~ m/syslog/i) {
	set syslog      => { facility => $CONFIG{log_facility}, ident => __PACKAGE__, };
}
set logger      => $CONFIG{log};
set log         => $CONFIG{log_level};
set show_errors =>  1;

set serializer   => 'JSON';
set content_type => 'application/json';


get qr|(/wd/hub)?/sessions| => sub {
	debug "Sessions hit\n";
	# ... hmmm landing page? ... docs ?
	return 'ok';
};
post '/' => sub {
	redirect '/session', 301;
};
post qr|(/wd/hub)?/session| => sub {
	my $request = from_json(request->body);
	for (keys %{&NODES}) {
		next unless scalar keys %{$NODES->{$_}{sessions}} < $NODES->{$_}{max_instances};
		next unless $request->{desiredCapabilities}{browserName} eq $NODES->{$_}{browser};
		my $res = $agent->post($NODES->{$_}{url}."/session", Content => request->body);
		if ($res->is_success) {
			$res = from_json($res->content);
			$res->{value}{node} = $NODES->{$_}{url};
			debug "session ($res->{sessionId}) created for ".request->host;

			$NODES->{$_}{sessions}{$res->{sessionId}} = time;
			&SESSIONS->{$res->{sessionId}} = $_; # Reverse hash session -> node
			&STATS->{sessions}++;
			NODES->set; STATS->set; SESSIONS->set;

			return to_json($res);
			last;
		}
	}
	redirect "/next lithium server", 301
		if $CONFIG{pair};
	status 404; return;
};
del '/session/:session_id' => sub {
	my $session_id = param('session_id');
	debug "deleting session: $session_id";

	my $node = delete &SESSIONS->{$session_id};
	SESSIONS->set;

	&NODES;
	my $res = $agent->delete("$NODES->{$node}{url}/session/$session_id");
	my $end_time = time;
	my $start_time = delete $NODES->{$node}{sessions}{$session_id};
	NODES->set;

	&STATS->{runtime} += $end_time - $start_time;
	STATS->set;

	status 204;
	return 'ok';
};
del '/wd/hub/session/:session_id' => sub {
	forward '/session/'.params->{session_id};
};

post '/grid/register' => sub {
	my $node = from_json(request->body);
	debug "Registering new node ($node->{capabilities}[0]{browserName}"
		." at $node->{configuration}{url},"
		." available sessions: $node->{capabilities}[0]{maxInstances})";

	&NODES->{"$node->{configuration}{url}_$node->{capabilities}[0]{browserName}"} =
		{
			url           => $node->{configuration}{url},
			max_instances => $node->{capabilities}[0]{maxInstances},
			browser       => $node->{capabilities}[0]{browserName},
			sessions      => {},
		};
	NODES->set;

	&STATS->{nodes}++; STATS->set;

	return "ok";
};

get qr|(/lithium)?(/v\d)?/health| => sub {
	header 'Content-Type' => "text/plain";
	return to_yaml {
		name    => __PACKAGE__,
		version => $VERSION,
		checks  => {
			test1 => {
				status  => 'OK',
				message => 'Test OK'
			}
		}
	};
};
get qr|(/lithium)?/stats| => sub {
	return to_json &STATS;
};

sub _check_nodes
{
	&STATS;
	for (keys %{&NODES}) {
		my $res = $agent->get("$NODES->{$_}{url}/status");
		next if $res->is_success;
		my $old_node = delete $NODES->{$_};
		$STATS->{nodes}--;
		NODES->set; STATS->set;
	}
}

sub app
{
	my $request = Dancer::Request->new(env => shift);
	Dancer->dance($request);
}

sub run
{
	my $pid = fork;
	my $pidfile = $CONFIG{pidfile};
	exit 1 if $pid < 0;
	if ($pid == 0) {
		exit if fork;
		my $fh;
		if (-f $pidfile) {
			open my $fh, "<", $pidfile or die "Failed to read $pidfile: $!\n";
			my $found_pid = <$fh>;
			close $fh;
			if (kill "ZERO", $found_pid) {
				warning __PACKAGE__." already running";
				return 1;
			} else {
				unlink $pidfile;
			}
		}
		open $fh, ">", $pidfile and do {
			print $fh "$$";
			close $fh;
		};
		$) = getgrnam($CONFIG{gid}) or die "Unable to set group to $CONFIG{gid}: $!";
		$> = getpwnam($CONFIG{uid}) or die "Unable to set user to $CONFIG{uid}: $!";
		open STDOUT, ">/dev/null";
		open STDERR, ">/dev/null";
		open STDIN,  "</dev/null";
		debug "clearing cache file '$CONFIG{cache_file}'";
		$CACHE->empty;
		$CACHE->set('STATS', { nodes => 0, runtime => 0, sessions => 0 });
		$CACHE->set('NODES', {});
		$CACHE->set('SESSIONS', {});
		my $server = Plack::Handler::Starman->new(
				port              => $CONFIG{port},
				workers           => $CONFIG{workers},
				keepalive_timeout => $CONFIG{keepalive},
				argv              => ['lithium'],
			);
		info "starting ".__PACKAGE__;
		$server->run(\&app);
		exit 2;
	}

	waitpid($pid, 0);
	return $? == 0;
}

sub stop
{
	my $pidfile = $CONFIG{pidfile};
	return unless -f $pidfile;
	info "stopping ".__PACKAGE__;
	my $fh;
	open $fh, "<", $pidfile or die "Failed to read $pidfile: $!\n";
	my $pid = <$fh>;
	close $fh;

	kill "TERM", $pid;
	for (1 .. 2 ) {
		if (waitpid($pid, WNOHANG)) {
			unlink $pidfile;
			return;
		}
		sleep 1;
	}

	kill "KILL", $pid;
	waitpid($pid, 0);
	unlink $pidfile;
	return;

}

=head1 NAME

lithium - The great new lithium!

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 FUNCTIONS

=head2 function1

=head1 AUTHOR

Dan Molik, C<< <dmolik at synacor.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2014 Synacor Inc.

All rights reserved.

=cut

1;
