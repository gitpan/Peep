package Peep::Client::Log;

require 5.005_62;
use strict;
use warnings;
use Carp;
use File::Tail;
use Peep::Client;
use Peep::BC;

require Exporter;

our @ISA = qw(Exporter Peep::Client);
our %EXPORT_TAGS = ( 'all' => [ qw( INTERVAL MAX_INTERVAL ADJUST_AFTER ) ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw( );
our $VERSION = do { my @r = (q$Revision: 1.9 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };

# These are in seconds and are the parameters for File::Tail

# File Tail uses the idea of intervals and predictions to try to keep
# blocking time at a maximum. These three parameters are the ones that
# people will want to tune for performance vs. load. The smaller the
# interval, the higher the load but faster events are picked up.

# The interval that File::Tail waits before checking the log
use constant INTERVAL => 0.1;
# The maximum interval that File::Tail will wait before checking the
# log
use constant MAX_INTERVAL => 1;
# The time after which File::Tail adjusts its predictions
use constant ADJUST_AFTER => 2;

use constant DEFAULT_PID_FILE => "/var/run/logparser.pid";

sub new {

	my $self = shift;
	my $class = ref($self) || $self;
	my $this = $class->SUPER::new('logparser');
	bless $this, $class;

} # end sub new

sub getLogFiles {

	my $self = shift;
	my $logfiles = $self->getconf()->getOption('logfile');
	my @logfiles = split ',\s*', $logfiles;
	return wantarray ? @logfiles : [@logfiles];

} # sub getLogFiles

sub getLogFileTails {

	my $self = shift;
	if ( ! exists $self->{"__LOGFILETAILS"} ) {

	my @logfiles = $self->getLogFiles();
	my @tailfiles;
	for my $logfile (@logfiles) {
		if (-e $logfile) {
			my $tail;
			eval { $tail =
				File::Tail->new(
						name => $logfile,
						interval => INTERVAL,
						maxinterval => MAX_INTERVAL,
						adjustafter => ADJUST_AFTER
						);
			};
			if ($@) {
				chomp $@;
				$self->logger()->log("Warning:  Error creating tail of logfile '$logfile':  $@");
			} else {
				push @tailfiles, $tail;
			}
		} else {
			$self->logger()->log("Warning:  Can't tail the log file '$logfile':  It doesn't exist.");
		}
	}

	$self->{"__LOGFILETAILS"} = \@tailfiles;

	}

	return wantarray ? @{$self->{"__LOGFILETAILS"}} : $self->{"__LOGFILETAILS"};

} # sub getLogFileTails

sub Start {

	my $self = shift;

	my $events = '';

	my %options = ( 'events=s' => \$events );

	$self->parseopts(%options);

	$self->parseconf();

	my $conf = $self->getconf();

	unless ($conf->getOption('autodiscovery')) {
		$self->pods("Error:  Without autodiscovery you must provide a server and port option.")
			unless $conf->optionExists('server') && $conf->optionExists('port') &&
			       $conf->getOption('server') && $conf->getOption('port');
	}

	$events = $conf->getOption('events') if ! $events && $conf->optionExists('events');

	# Check whether the pidfile option was set. If not, use the default
	unless ($conf->optionExists('pidfile')) {
		$self->logger()->debug(3,"No pid file specified. Using default [" . DEFAULT_PID_FILE . "]");
		$conf->setOption('pidfile', DEFAULT_PID_FILE);
	}

	$self->logger()->log("Scanning logs:");

	for my $logfile ($self->getLogFiles()) {
		$self->logger()->log("\t$logfile");
	}

	$self->logger()->debug(9,"Registering callback ...");

	$self->callback(sub { $self->loop($events); });

	$self->logger()->debug(9,"\tCallback registered ...");

	$self->MainLoop();

	return 1;

} # end sub Start

sub loop {

	my $self = shift;
	my $events = shift || confess "Error:  No events specified.  What's the point?";

	select(STDOUT);

	$| = 1; # autoflush

	my $nfound;

	my @logFileTails = $self->getLogFileTails();

	# call the peck method which, the first time it is called, will
	# instantiate a Peep::BC object as necessary

	$self->peck();

	while (1) {

		$nfound = File::Tail::select(undef,undef,undef,60,@logFileTails);
		# hmmm ... don't quite understand what interval does ... [collin]
		unless ($nfound) {
			for my $filetail (@logFileTails) {
				$filetail->interval;
			}
		}

		for my $filetail (@logFileTails) {
			$self->parse($filetail->read) unless $filetail->predict;
		}
	}

	return 1;

} # end sub loop

sub peck {

	my $self = shift;

	my $configuration = $self->getconf();

	unless (exists $self->{"__PEEP"}) {
		if ($configuration->getOptions()) {
			$self->{"__PEEP"} = Peep::BC->new( 'logparser', $configuration );
		} else {
			confess "Error:  Expecting options to have been parsed by now.";
		}
	}

	return $self->{"__PEEP"};

} # end sub peck

sub parse {

	my $self = shift;
	my $line = shift;

	chomp $line;

	$self->logger()->debug(9,"Checking [$line] ...");

	my $configuration = $self->getconf();

	for my $event ($configuration->getClientEvents('logparser')) {

		# FIXIT: Build the pecking object creation tomorrow (see the
		# top of logparser)

		my $name = $event->{'name'};
		my $regex = $event->{'regex'};

		$self->logger()->debug(9,"\tTrying to match regex [$regex] for event [$name]");

		if ($line =~ /$regex/) {

			$self->logger()->debug(5,"$name:  $line");

			$self->peck()->send(
				'type'       => 0,
				'sound'      => $event->{'name'},
				'location'   => $event->{'location'},
				'priority'   => $event->{'priority'},
				'volume'     => 255
				);
		}

	}

	return 1;

} # end sub parse

1;

__END__

=head1 NAME

Peep::Client::Log - Perl extension for the logparser, the event generator
for Peep.

=head1 SYNOPSIS

  use Peep::Client::Log;
  my $parser = new Peep::Client::Log;

=head1 DESCRIPTION

Provides support methods and utilities for logparser, the event
generator for Peep.  Inherits Peep::Client.

=head2 EXPORT

None by default.

=head1 METHODS

Note that this section is somewhat incomplete.  More
documentation will come soon.

    new() - The constructor

    Start() - Begins tailing log files and signaling events.
    Terminates by entering the Peep::Client->MainLoop() method.

=head1 AUTHOR

Michael Gilfix <mgilfix@eecs.tufts.edu> Copyright (C) 2001

=head1 SEE ALSO

perl(1), peepd(1), Peep::BC, Peep::Log, Peep::Parse, Peep::Client, logparser.

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

$Log: Log.pm,v $
Revision 1.9  2001/04/17 06:46:21  starky
Hopefully the last commit before submission of the Peep client library
to the CPAN.  Among the changes:

o The clients have been modified somewhat to more elagantly
  clean up pidfiles in response to sigint and sigterm signals.
o Minor changes have been made to the documentation.
o The Peep::Client module searches through a host of directories in
  order to find peep.conf if it is not immediately found in /etc or
  provided on the command line.
o The make test script conf.t was modified to provide output during
  the testing process.
o Changes files and test.pl files were added to prevent specious
  complaints during the make process.

Revision 1.8  2001/04/04 05:40:00  starky
Made a more intelligent option parser, allowing a user to more easily
override the default options.  Also moved all error messages that arise
from client options (e.g., using noautodiscovery without specifying
a port and server) from the parseopts method to being the responsibility
of each individual client.

Also made some minor and transparent changes, such as returning a true
value on success for many of the methods which have no explicit return
value.

Revision 1.7  2001/03/31 07:51:34  mgilfix


  Last major commit before the 0.4.0 release. All of the newly rewritten
clients and libraries are now working and are nicely formatted. The server
installation has been changed a bit so now peep.conf is generated from
the template file during a configure - which brings us closer to having
a work-out-of-the-box system.

Revision 1.7  2001/03/31 02:17:00  mgilfix
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

Revision 1.6  2001/03/30 18:34:12  starky
Adjusted documentation and made some modifications to Peep::BC to
handle autodiscovery differently.  This is the last commit before the
0.4.0 release.

Revision 1.5  2001/03/28 02:41:48  starky
Created a new client called 'pinger' which pings a set of hosts to check
whether they are alive.  Made some adjustments to the client modules to
accomodate the new client.

Also fixed some trivial pre-0.4.0-launch bugs.

Revision 1.4  2001/03/27 00:44:19  starky
Completed work on rearchitecting the Peep client API, modified client code
to be consistent with the new API, and added and tested the sysmonitor
client, which replaces the uptime client.

This is the last major commit prior to launching the new client code,
though the API or architecture may undergo some initial changes following
launch in response to comments or suggestions from the user and developer
base.

Revision 1.3  2001/03/19 07:47:37  starky
Fixed bugs in autodiscovery/noautodiscovery.  Now both are supported by
Peep::BC and both look relatively bug free.  Wahoo!

Revision 1.2  2001/03/18 17:17:46  starky
Finally got LogParser (now called logparser) running smoothly.

Revision 1.1  2001/03/16 21:26:12  starky
Initial commit of some very broken code which will eventually comprise
a rearchitecting of the Peep client libraries; most importantly, the
Perl modules.

A detailed e-mail regarding this commit will be posted to the Peep
develop list (peep-develop@lists.sourceforge.net).

Contact me (Collin Starkweather) at

  collin.starkweather@colorado.edu

or

  collin.starkweather@collinstarkweather.com

with any questions.


=cut
