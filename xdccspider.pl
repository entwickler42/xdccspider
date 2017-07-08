#!/usr/bin/perl

use POE qw(Component::IRC Component::Server::TCP);

require 'config.pl';

my $maintain_session;
my $control_session;
my @irc_sessions;

# nickname already in use: create alternate nickname by appending a dash
sub irc_433 {
	my ( $sender, $session, $heap ) = @_[ SENDER, SESSION, HEAP ];
	my $altnick = $heap->{'server'}{'nickname'} . "_";
	my $prefix  = "[" . $session->ID() . "/" . $heap->{'server'}{'host'} . "][INVALIDNICK]";
	debug_out("$prefix: invalid nick trying alternate nick: $altnick");
	$heap->{'irc'}->yield( nick => $altnick );
}

# welcome event: join designated channels
sub irc_001 {
	my ( $kernel, $sender, $session, $heap ) = @_[ KERNEL, SENDER, SESSION, HEAP ];
	my $prefix = "[" . $session->ID() . "/" . $heap->{'server'}{'host'} . "][IRCWELCOME]";
	debug_out("$prefix");
	$heap->{'irc'}->yield( join => $_->{'name'} ) for ( @{ $heap->{'channels'} } );
}

sub irc_join {
	my ( $kernel, $sender, $session, $heap, $user, $chan ) = @_[ KERNEL, SENDER, SESSION, HEAP, ARG0, ARG1 ];
	my $prefix = "[" . $session->ID() . "/" . $heap->{'server'}{'host'} . "][IRCJOIN]";
	if ( ( split /!/, $user )[0] eq $heap->{'irc'}->nick_name() ) {
		debug_out("$prefix: joined channel $chan");
	} else {

		#debug_out("$prefix: $user has joined channel $chan");
	}
}

sub irc_part {
	my ( $kernel, $sender, $session, $heap, $user, $chan ) = @_[ KERNEL, SENDER, SESSION, HEAP, ARG0, ARG1 ];
	my $prefix = "[" . $session->ID() . "/" . $heap->{'server'}{'host'} . "][IRCPART]";
	if ( ( split /!/, $user )[0] eq $heap->{'irc'}->nick_name() ) {
		debug_out("$prefix: parted channel $chan");
	} else {

		#debug_out("$prefix: $user has parted channel $chan");
	}
}

sub irc_invite {
	my ( $sender, $session, $heap, $who, $where ) = @_[ SENDER, SESSION, HEAP, ARG0, ARG1 ];
	my $prefix = "[" . $session->ID() . "/" . $heap->{'server'}{'host'} . "][IRCINVITE]";
	my $dbh    = get_database();
	$heap->{'irc'}->yield( join => $where )
	  if $dbh->do("INSERT INTO channel(srvid, name) VALUE($heap->{server}{id}, \'$where\') ON DUPLICATE KEY UPDATE enabled=1")
		  or debug_out("can't insert channel to database: $heap->{server}{id}, $where");
	debug_out("$prefix: invited to $where by $who");
}

sub irc_kick {
	my ( $sender, $session, $heap, $user, $where ) = @_[ SENDER, SESSION, HEAP, ARG0, ARG2 ];
	my $prefix = "[" . $session->ID() . "/" . $heap->{'server'}{'host'} . "][IRCKICK]";
	if ( ( split /!/, $user )[0] eq $heap->{'irc'}->nick_name() ) {
		my $dbh = get_database();
		$dbh->do("UPDATE channel SET enabled=0 WHERE srvid=$heap->{server}{id} AND name=\'$where\'") or warn "can't disable channel in database";
		debug_out("$prefix: kicked from $where");
	} else {

		#debug_out("$prefix: $user was kicked from $where");
	}
}

sub irc_public {
	my ( $sender, $heap, $who, $where, $what ) = @_[ SENDER, HEAP, ARG0 .. ARG2 ];
	my $nick = lc( ( split /!/, $who )[0] );
	my $channel = lc $where->[0];
	if ( $what =~ /#(\d+).+(\d+)x.+\[ *(\d+\w*) *] +(.+)/ ) {
		my ( $idx, $gets, $size, $desc ) = ( $1, $2, $3, $4 );
		my $isnew = 1;
		for my $pack ( @{ $heap->{'packages'} } ) {
			if (   $pack->{'channel'} eq $channel
				&& $pack->{'nickname'} eq $nick
				&& $pack->{'idx'} eq $idx )
			{
				$pack->{'gets'} = $gets;
				$pack->{'size'} = $size;
				$pack->{'desc'} = $desc;
				$isnew          = 0;
				last;
			}
		}
		if ($isnew) {
			push @{ $heap->{'packages'} },
			  {
				nickname => $nick,
				channel  => $channel,
				idx      => $idx,
				gets     => $gets,
				size     => $size,
				desc     => $desc
			  };
		}
	}
}

# irc session start
sub _start {
	my ( $kernel, $sender, $session, $heap ) = @_[ KERNEL, SENDER, SESSION, HEAP ];
	my $prefix = "[" . $session->ID() . "/" . $heap->{'server'}{'host'} . "][STARTSESSION]";
	$heap->{'irc'}->yield( register => 'all' );
	$heap->{'irc'}->yield( connect  => {} );
	push @irc_sessions, $session->ID();
	debug_out(
		"$prefix: port: $heap->{server}{port} username: $heap->{server}{username} realname: $heap->{server}{realname} nickname: $heap->{server}{nickname}");
}

# irc session stop
sub _stop {
	my ( $kernel, $session, $heap ) = @_[ KERNEL, SESSION, HEAP ];
	my $prefix = "[" . $session->ID() . "/" . $heap->{'server'}{'host'} . "][STOPSESSION]";
	@irc_sessions = grep( $_ ne $session->ID(), @irc_sessions );
	debug_out("$prefix: stopped");
}

sub maintain_start {
	my ( $kernel, $session, $heap ) = @_[ KERNEL, SESSION, HEAP ];
	my $prefix = "[" . $session->ID() . "][MAINTAINSTART]";
	$kernel->delay_set( 'maintain_database', $config{'maintain_database_interval'} );
	$kernel->yield('maintain_connections');
	$kernel->sig( INT  => "shutdown" );
	$kernel->sig( HUP  => "shutdown" );
	$kernel->sig( KILL => "shutdown" );
	$kernel->sig( TERM => "shutdown" );
	$kernel->sig( QUIT => "shutdown" );
	$maintain_session = $session->ID();
	debug_out("$prefix: session started");
}

sub maintain_stop {
	sub {
		my ( $kernel, $session, $heap ) = @_[ KERNEL, SESSION, HEAP ];
		my $prefix = "[" . $session->ID() . "][MAINTAINSTOP]";
		debug_out("$prefix: session stopped");
	  }
}

sub maintain_shutdown {
	my ( $kernel, $session, $heap ) = @_[ KERNEL, SESSION, HEAP ];
	my $prefix = "[" . $session->ID() . "][MAINTAINSHUTDOWN]";
	$kernel->call( $maintain_session, 'maintain_database' );
	$kernel->call( $control_session,  'shutdown' );
	$kernel->alarm_remove_all();
	$_->get_heap()->{'irc'}->yield('shutdown') for (map $kernel->alias_resolve($_), @irc_sessions);
	debug_out("$prefix: shutdown complete");
}

sub maintain_database {
	my ( $kernel, $session ) = @_[ KERNEL, SESSION ];
	my $prefix = "[" . $session->ID() . "][MAINTAINDATABASE]";
	debug_out("$prefix: starting database update");

	my $dbh = get_database()
	  or debug_out("$prefix: failed to get database handle")
	  and return;

	for my $ircses ( map $kernel->alias_resolve($_), @irc_sessions ) {
		my @tuple_status;
		my $heap = $ircses->get_heap();
		my $sth;

		debug_out( "$prefix: updating session " . $ircses->ID() . " $heap->{server}{host}" );

		# fetch fresh list of channels and filter bots by available channels
		my $channels = $dbh->selectall_arrayref( "SELECT * FROM channel WHERE enabled=1 AND srvid=$heap->{server}{id}", { Slice => {} } );
		my ( @chanids, @nicks );
		for my $chan ( @{$channels} ) {
			my %bots;
			for my $pkg ( @{ $heap->{'packages'} } ) {

				# debug_out("checking $chan->{name} eq $pkg->{channel}");
				if ( lc $chan->{'name'} eq lc $pkg->{'channel'} ) {
					next if $bots{'id'}{ $pkg->{'nickname'} };
					$bots{ $chan->{'id'} }{ $pkg->{'nickname'} } = 1;
					push @chanids, $chan->{'id'};
					push @nicks,   $pkg->{'nickname'};
				}
			}
		}
		my $c_pkg = @{ $heap->{'packages'} };
		my $c_aff = @chanids;
		my $c_ign = $c_pkg - $c_aff;
		debug_out("$prefix packages: $c_pkg \t affected: $c_aff \t ignored: $c_ign");

		# schedule next run and return if no package was affected
		next if @chanids == 0;

		# insert/update bots to database
		$sth = $dbh->prepare(
			qq(
		INSERT INTO bot(chanid, nickname, lastseen) 
		VALUES(?,?,now())
		ON DUPLICATE KEY UPDATE lastseen=now();
		)
		);
		$sth->bind_param_array( 1, \@chanids );
		$sth->bind_param_array( 2, \@nicks );
		$sth->execute_array( { ArrayTupleStatus => \@tuple_status } );

		# fetch bot information
		my $bots = $dbh->selectall_arrayref(
"SELECT bot.nickname, bot.id, channel.name AS channelname FROM bot LEFT JOIN channel ON channel.id=bot.chanid AND channel.enabled=1 AND channel.srvid=$heap->{server}{id} AND channel.id in "
			  . "("
			  . join( ',', @chanids ) . ")",
			{ Slice => {} }
		);
		my ( @botids, @idxs, @gets, @sizes, @desc );
		for my $pack ( @{ $heap->{'packages'} } ) {
			for my $bot ( @{$bots} ) {
				if (    $pack->{'nickname'} eq $bot->{'nickname'}
					and $pack->{'channel'} eq $bot->{'channelname'} )
				{
					push @botids, $bot->{'id'};
					push @idxs,   $pack->{'idx'};
					push @gets,   $pack->{'gets'};
					push @sizes,  $pack->{'size'};
					push @desc,   $pack->{'desc'};
				}
			}
		}
		$sth = $dbh->prepare(
			qq(
		INSERT INTO package(botid, idx, gets, size, description, lastseen)
		VALUES(?, ?, ?, ?, ?, now())
		ON DUPLICATE KEY UPDATE gets=?, size=?, description=?, lastseen=now()
		)
		);
		$sth->bind_param_array( 1, \@botids );
		$sth->bind_param_array( 2, \@idxs );
		$sth->bind_param_array( 3, \@gets );
		$sth->bind_param_array( 4, \@sizes );
		$sth->bind_param_array( 5, \@desc );
		$sth->bind_param_array( 6, \@gets );
		$sth->bind_param_array( 7, \@sizes );
		$sth->bind_param_array( 8, \@desc );
		$sth->execute_array( { ArrayTupleStatus => \@tuple_status } );

		# clear local package list
		delete $heap->{'packages'};
	}
	$kernel->delay_set( 'maintain_database', $config{'maintain_database_interval'} );
	debug_out("$prefix: database update finished");
}

sub maintain_connections {
	my ( $kernel, $session, $heap ) = @_[ KERNEL, SESSION, HEAP ];
	my $prefix = "[" . $session->ID() . "][MAINTAINCONNECTIONS]";
	debug_out("$prefix: maintaining connections");

	# fetch server list from database
	my $dbh = get_database()
	  or debug_out("$prefix: failed to get database handle")
	  and return;
	my $srvdat = $dbh->selectall_arrayref( "SELECT * FROM server WHERE enabled", { Slice => {} } );
	for my $session ( map $kernel->alias_resolve($_), @irc_sessions ) {
		my $heap = $session->get_heap();
		if ( not grep $_->{'host'} eq $heap->{'server'}{'host'}, @$srvdat ) {

			# shutdown vanished irc sessions
			$heap->{'irc'}->yield('shutdown');
		} else {

			# join/part channels according to database
			my $channels = $dbh->selectall_arrayref( "SELECT * FROM channel WHERE srvid=$heap->{server}{id}", { Slice => {} } );
			for my $chan (@$channels) {
				$heap->{'irc'}->yield( join => $chan->{'name'} )
				  unless ( grep $chan->{'name'} eq $_->{'name'}, ( @{ $heap->{'channels'} } ) );
			}
			for my $chan ( @{ $heap->{'channels'} } ) {
				$heap->{'irc'}->yield( part => $chan->{'name'} )
				  unless ( grep $chan->{'name'} eq $_->{'name'}, (@$channels) );
			}
			$heap->{'channels'} = $channels;

			# reconnect disconnected irc sessions
			if ( !$heap->{'irc'}->connected() ) {
				$heap->{'irc'}->yield('connect');
			}
		}
	}

	# create missing irc sessions
	for my $srv (@$srvdat) {
		unless ( grep $kernel->alias_resolve($_)->get_heap()->{'server'}{'host'} eq $srv->{'host'}, @irc_sessions ) {
			my $channels = $dbh->selectall_arrayref( "SELECT * FROM channel WHERE enabled=1 AND srvid=$srv->{'id'}", { Slice => {} } );

			# default to random credentials*
			$srv->{'realname'} = get_random_name(5)
			  unless $srv->{'realname'};
			$srv->{'username'} = get_random_name(5)
			  unless $srv->{'username'};
			$srv->{'nickname'} = get_random_name(5)
			  unless $srv->{'nickname'};
			my $irc = POE::Component::IRC->spawn(
				server   => $srv->{'host'},
				port     => $srv->{'port'},
				ircname  => $srv->{'realname'},
				username => $srv->{'username'},
				nick     => $srv->{'nickname'},
				debug    => 0
			  )
			  or debug_out("$prefix: irc spawn for $srv->{'host'} failed")
			  and next;
			POE::Session->create(
				package_states => [ main => [qw(_start _stop irc_001 irc_433 irc_join irc_part irc_invite irc_kick irc_public)] ],
				heap           => {
					irc      => $irc,
					server   => { %{$srv} },
					channels => $channels,
					packages => []
				}
			);
		}
	}
	$kernel->delay_set( 'maintain_connections', $config{'maintain_connections_interval'} );
	debug_out("$prefix: finished maintaining connections");
}

sub control_session_started {
	$control_session = $_[SESSION]->ID;
}

sub control_client_connected {
	my ( $kernel, $session, $sender, $heap ) = @_[ KERNEL, SESSION, SENDER, HEAP ];
	my $prefix = "[" . $session->ID() . "][CLIENTCONNECTED]";
	$heap->{'client'}->put("welcome to xdccspider 1.0.0");
	debug_out("$prefix: client connected to tcp control socket");
}

sub control_client_input {
	my ( $kernel, $session, $sender, $heap ) = @_[ KERNEL, SESSION, SENDER, HEAP ];
	my $prefix = "[" . $session->ID() . "][CLIENTINPUT]";
	my $data   = $_[ARG0];
	if ( $data =~ /SHUTDOWN/i ) {
		$heap->{'client'}->put("OK SHUTDOWN");
		$kernel->yield('shutdown');
		$kernel->post( $maintain_session, 'shutdown' );
		debug_out("$prefix: shutdown command received");
	} elsif ( $data =~ /QUIT/i ) {
		$heap->{'client'}->put("OK EXIT");
		$kernel->yield('shutdown');
		debug_out("$prefix: client exit");
	} elsif ( $data =~ /MTD/i ) {
		$heap->{'client'}->put("OK MTD");
		$kernel->post( $maintain_session, "maintain_database" );
	} elsif ( $data =~ /MTC/i ) {
		$heap->{'client'}->put("OK MTC");
		$kernel->post( $maintain_session, "maintain_connections" );
	} else {
		$heap->{'client'}->put("UNKNOWN COMMAND");
		debug_out("$prefix: unknown command received");
	}
}

# create maintenance session
POE::Session->create(
	inline_states => {
		_start               => \&maintain_start,
		_stop                => \&maintain_stop,
		shutdown             => \&maintain_shutdown,
		maintain_database    => \&maintain_database,
		maintain_connections => \&maintain_connections
	}
);

# listen for control commands on tcp port 4711
POE::Component::Server::TCP->new(
	Port            => 4711,
	Started         => \&control_session_started,
	ClientConnected => \&control_client_connected,
	ClientInput     => \&control_client_input
);

# start event processing
$poe_kernel->run();
debug_out("EXIT");
