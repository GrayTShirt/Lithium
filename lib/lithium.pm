package lithium;

use strict;
use warnings;

use Dancer;
use LWP::UserAgent;
use Data::Dumper;
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

our $VERSION = '0.1';

my $NODES    = {};
my %CONFIG   = ();
my $agent    = LWP::UserAgent->new(agent => __PACKAGE__);
$agent->default_header(Content_Type => "application/json;charset=UTF-8");
# pretty sure this violates RFC 2616, oh well
push @{$agent->requests_redirectable}, 'POST';


set serializer => 'JSON';
set port       => $CONFIG{port} || 3000;
set logger     => 'console';
set log        => 'debug';
set show_errors => 1;


get '/sessions' => sub {
	debug "Sessions hit\n";
	# ... hmmm landing page? ... docs ?
	return 'ok';
};
get '/wd/hub/sessions' => sub {
	redirect "/sessions";
};
post '/' => sub {
	redirect '/session', 301;
};
post '/session' => sub {
	debug "client is requesting a new session (/session)";
	my $request = from_json(request->body);
	debug(Dumper($request));
	for (keys %$NODES) {
		next unless scalar @{$NODES->{$_}{sessions}} < $NODES->{$_}{max_instances};
		next unless $request->{desiredCapabilities}{browserName} eq $NODES->{$_}{browser};
		my $res = $agent->post("$NODES->{$_}{url}/session", Content => request->body);
		if ($res->is_success) {
			$res = from_json($res->content);
			$res->{value}{node} = $NODES->{$_}{url};
			push @{$NODES->{$_}{sessions}}, $res->{sessionId};
			return to_json($res);
			last;
		}
	}
	redirect "/next lithium server", 301;
};
del '/session/:session_id' => sub {
	return 'ok';
};
post '/wd/hub/session' => sub {
	debug "client is requesting a new session (/wd/hub/session)";
	redirect "/session", 301;
};

post '/grid/register' => sub {
	my $node = from_json(request->body);
	debug "Registering new node ($node->{capabilities}[0]{browserName}"
		." at $node->{configuration}{url},"
		." available sessions: $node->{capabilities}[0]{maxInstances})";

	$NODES->{"$node->{configuration}{url}_$node->{capabilities}[0]{browserName}"} =
		{
			url           => $node->{configuration}{url},
			max_instances => $node->{capabilities}[0]{maxInstances},
			browser       => $node->{capabilities}[0]{browserName},
			sessions      => [],
		};

	return "ok";
};

get qr|/lithium(/v\d)?/health| => sub {

};
get '/lithium/stats' => sub {

};

dance;

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
