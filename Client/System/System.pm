package Peep::Client::System;

require 5.005_62;
use strict;
use warnings;
use Carp;
use Peep::Client;

require Exporter;

our @ISA = qw( Exporter Peep::Client );
our %EXPORT_TAGS = ( 'all' => [ qw( ) ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw( );
our $VERSION = do { my @r = (q$Revision: 1.5 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };

use constant DEFAULT_PID_FILE => "/var/run/sysmonitor.pid";

sub new {

	my $self = shift;
	my $class = ref($self) || $self;
	my $this = $class->SUPER::new('sysmonitor');
	bless $this, $class;

} # end sub new

sub Start {

	my $self = shift;

	# command-line options

	my $loadsound = '';
	my $userssound = '';
	my $loadloc = '';
	my $usersloc = '';
	my $sleep = 60;
	my $maxload = 2.0;
	my $maxusers = 5;

	my %options = (
		'loadsound=s' => \$loadsound,       # the load sound
		'userssound=s' => \$userssound,     # The users sound
		'loadloc=s' => \$loadloc,           # The location of the load sound
		'usersloc=s' => \$usersloc,         # The location of the users sound
		'sleep=s' => \$sleep,               # sleep time
		'maxload=s' => \$maxload,           # What to consider a high load
		'maxusers=s' => \$maxusers,         # What to consider a high number of users
	);

	# let the client know what command-line options to expect
	# and ask the client to parse the command-line
	$self->parseopts(%options);

	# have the client parse the configuration file
	$self->parseconf();

	# get the configuration object which should be populated with the
	# standard command-line options and configuration information
	my $conf = $self->getconf();

	unless ($conf->getOption('autodiscovery')) {
		$self->pods("Error:  Without autodiscovery you must provide a server and port option.")
			unless $conf->optionExists('server') && $conf->optionExists('port') &&
			       $conf->getOption('server') && $conf->getOption('port');
	}

	# Check whether the pidfile option was set. If not, use the default
	unless ($conf->optionExists('pidfile')) {
		$self->logger()->debug(3,"No pid file specified. Using default [" . DEFAULT_PID_FILE . "]");
		$conf->setOption('pidfile', DEFAULT_PID_FILE);
	}

	# use the options defined in the configuration file if they were
	# not explicitly defined from the command-line
	$loadsound = $conf->getOption('loadsound') if ! $loadsound && $conf->optionExists('loadsound');
	$userssound = $conf->getOption('userssound') if ! $userssound && $conf->optionExists('userssound');
	$loadloc = $conf->getOption('loadloc') if ! $loadloc && $conf->optionExists('loadloc');
	$usersloc = $conf->getOption('usersloc') if ! $usersloc && $conf->optionExists('usersloc');
	$sleep = $conf->getOption('sleep') if ! $sleep && $conf->optionExists('sleep');
	$maxload = $conf->getOption('maxload') if ! $maxload && $conf->optionExists('maxload');
	$maxusers = $conf->getOption('maxusers') if ! $maxusers && $conf->optionExists('maxusers');

	$self->logger()->debug(9,"loadsound=[$loadsound] userssound=[$userssound] loadloc=[$loadloc] usersloc=[$usersloc] sleep=[$sleep] maxload=[$maxload] maxusers=[$maxusers] ...");

	$self->logger()->debug(9,"Registering callback ...");
	$self->callback(sub { $self->loop($conf,$loadsound,$userssound,$loadloc,$usersloc,$sleep,$maxload,$maxusers); });
	$self->logger()->debug(9,"\tCallback registered ...");
	$self->MainLoop($sleep);

	return 1;

} # end sub Start

sub loop {

	my $self = shift;
	my $conf = shift || confess "Cannot execute loop:  Configuration object not found.";
	my ($loadsound,$userssound,$loadloc,$usersloc,$sleep,$maxload,$maxusers) = @_;

	confess "Error:  You didn't define the sleep time [$sleep], load sound [$loadsound], user sound [$userssound], max load [$maxload], or max users [$maxusers] properly.\n".
		"        You may want to check peep.conf.\n"
		unless $sleep > 0 and $loadsound and $userssound and $maxload and $maxusers;

	my ($in, $avg, $users, $uptime);
	confess "Error:  Can't find uptime: $!" unless $uptime = `which uptime`;
	chomp($uptime);
	confess "Error:  $uptime returned no output: $!" unless $in = `$uptime`;

	$self->logger()->debug(3,"$uptime: $in");

	$users = $1 if $in =~ /(\d+) users/; 
	$avg = $1   if $in =~ /load average. ([\d\.]+)/;

	# Scale relative to maximum value with max volume being 255
	my $load = $maxload < $avg ? 255.0 : int(255.0 * $avg / $maxload);
	if ($maxload > 0) {
		$self->peck()->send('type' => 1,
			'sound'    => $loadsound,
			'location' => $loadloc,
			'volume'   => $load,
		);
	}

	my $userload = $maxusers < $users ? 255.0 : int(255.0 * $users / $maxusers);
	if ($maxusers > 0) {
		$self->peck()->send('type' => 1,
			'sound'    => $userssound,
			'location' => $usersloc,
			'volume'   => $userload,
		);
	}

} # end sub loop


1;

__END__

=head1 NAME

Peep::Client::System - Perl extension for a client to monitor system statistics.

=head1 SYNOPSIS

  use Peep::Client::System;
  my $system = new Peep::Client::System;

=head1 DESCRIPTION

Monitors uptime, load, and user statistics.

Note that this section is somewhat incomplete.  More
documentation will come soon.

=head2 EXPORT

None by default.

=head1 METHODS

Note that this section is somewhat incomplete.  More
documentation will come soon.

    new() - The constructor

    Start() - Begins monitoring system events.  Terminates by entering
    the Peep::Client->MainLoop() method.

=head1 AUTHOR

Michael Gilfix <mgilfix@eecs.tufts.edu> Copyright (C) 2001

Collin Starkweather <collin.starkweather@colorado.edu>

=head1 SEE ALSO

perl(1), peepd(1), Peep::BC, Peep::Log, Peep::Parse, Peep::Client, sysmonitor.

http://peep.sourceforge.net

=head1 TERMS AND CONDITIONS

You should have received a file COPYING containing license terms
along with this program; if not, write to Michael Gilfix
(mgilfix@eecs.tufts.edu) for a copy.

This version of Peep is open source; you can redistribute it and/or
modify it under the terms listed in the file COPYING.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=head1 CHANGE LOG

$Log: System.pm,v $
Revision 1.5  2001/04/07 08:01:05  starky
Corrected some errors in and made some minor changes to the documentation.

Revision 1.4  2001/04/04 05:40:00  starky
Made a more intelligent option parser, allowing a user to more easily
override the default options.  Also moved all error messages that arise
from client options (e.g., using noautodiscovery without specifying
a port and server) from the parseopts method to being the responsibility
of each individual client.

Also made some minor and transparent changes, such as returning a true
value on success for many of the methods which have no explicit return
value.

Revision 1.3  2001/03/31 07:51:35  mgilfix


  Last major commit before the 0.4.0 release. All of the newly rewritten
clients and libraries are now working and are nicely formatted. The server
installation has been changed a bit so now peep.conf is generated from
the template file during a configure - which brings us closer to having
a work-out-of-the-box system.

Revision 1.3  2001/03/31 02:17:00  mgilfix
Made the final adjustments to for the 0.4.0 release so everything
now works. Lots of changes here: autodiscovery works in every
situation now (client up, server starts & vice-versa), clients
now shutdown elegantly with a SIGTERM or SIGINT and remove their
pidfiles upon exit, broadcast and server definitions in the class
definitions is now parsed correctly, the client libraries now
parse the events so they can translate from names to internal
numbers. There's probably some other changes in there but many
were made :) Also reformatted all of the code, so it uses
consistent indentation.

=cut
