package Peep::Client;

require 5.005_62;
use strict;
use warnings;
use Carp;
use Data::Dumper;
use Socket;
use Getopt::Long;
use File::Tail;
use Pod::Text;
use Peep::BC;
use Peep::Log;
use Peep::Parse;

require Exporter;

our @ISA = qw(Exporter);
our %EXPORT_TAGS = ( 'all' => [ qw( INTERVAL MAX_INTERVAL ADJUST_AFTER ) ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw( );
our $VERSION = do { my @r = (q$Revision: 1.12 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };

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

sub new {

	my $self = shift;
	my $class = ref($self) || $self;
	my $app = shift || confess "Error:  The application needs to tell the Peep library its name.  Exiting ....\n\n.";
	my $this = {};
	bless $this, $class;
	# create a configuration object to store command-line arguments
	# and configuration file information
	my $conf = new Peep::Conf;
	$conf->setApp($app);
	$this->setconf($conf);
	return $this;

} # end sub new

sub callback {

	my $self = shift;
	my $callback = shift;
	confess "Cannot register callback:  Expecting a code reference.  (Got [$callback].)" 
		unless ref($callback) eq 'CODE';
	$self->{"__CALLBACK"} = $callback;
	return 1;

} # end sub callback

sub getCallback {

	my $self = shift;
	confess "Cannot get callback:  A callback has not been set yet."
		unless exists $self->{"__CALLBACK"};
	return $self->{"__CALLBACK"};

} # end sub getCallback

sub loop {

	my $self = shift;
	if (@_) { $self->{"__LOOP"} = shift; }
	return $self->{"__LOOP"};

} # end sub loop

sub peck {

	my $self = shift;
	my $configuration = $self->getconf();

	unless (exists $self->{"__PEEP"}) {
		if ($configuration->getOptions()) {
			$self->{"__PEEP"} = Peep::BC->new( $configuration->getApp(), $configuration );
		} else {
			confess "Error:  Expecting options to have been parsed by now.";
		}
	}
	return $self->{"__PEEP"};

} # end sub peck

sub parseopts {

	my $self = shift;
	my %options = @_;

	my $conf = $self->getconf();

	my (
		$config,
		$logfile,
		$debug,
		$daemon,
		$output,
		$pidfile,
		$autodiscovery,
		$server,
		$port,
		$silent,
		$help) = ('/etc/peep.conf','',0,1,'','',1,'','',0,0);

	my %standardOptions = (
		'config=s' => \$config,
		'logfile=s' => \$logfile,
		'debug=s' => \$debug,
		'daemon!' => \$daemon,
		'output=s' => \$output,
		'pidfile=s' => \$pidfile,
		'autodiscovery!' => \$autodiscovery,
		'server=s' => \$server,
		'port=s' => \$port,
		'silent' => \$silent,
		'help' => \$help
	);

	for my $option (keys %standardOptions) {
		if (exists $options{$option}) {
			delete $standardOptions{$option};
		}
	}

	my %allOptions = (%options,%standardOptions);

	GetOptions(%allOptions);

	# set the debug level first so we can start printing debugging
	# messages
	$Peep::Log::logfile = $logfile if $logfile;
	$Peep::Log::debug = $debug if $debug;

	my $found;

	if (-f ${$allOptions{'config=s'}}) {
		$found = ${$allOptions{'config=s'}};
	} else {
		for my $dir ('/usr/local/etc','/usr','/usr/local','/opt') {
			if (-f "$dir/peep.conf") {
				$found = "$dir/peep.conf";
				last;
			}
		}
	}

	if ($found) {
		$self->logger()->debug(1,"The Peep configuration file has been identified as [$found]");
	} else {
		$self->logger()->debug(1,"No peep configuration file has been identified.");
	}

	$conf->setOption('config',$found);
	$conf->setOption('logfile',${$allOptions{'logfile=s'}}) if ${$allOptions{'logfile=s'}} ne '';
	$conf->setOption('debug',${$allOptions{'debug=s'}});
	$conf->setOption('daemon',${$allOptions{'daemon!'}});
	$conf->setOption('output',${$allOptions{'output=s'}});
	$conf->setOption('pidfile',${$allOptions{'pidfile=s'}}) if ${$allOptions{'pidfile=s'}} ne '';
	$conf->setOption('autodiscovery',${$allOptions{'autodiscovery!'}});
	$conf->setOption('server',${$allOptions{'server=s'}}) if ${$allOptions{'server=s'}} ne '';
	$conf->setOption('port',${$allOptions{'port=s'}}) if ${$allOptions{'port=s'}} ne '';
	$conf->setOption('silent',${$allOptions{'silent=s'}});
	$conf->setOption('help',${$allOptions{'help=s'}});

	$self->setconf($conf);

	return $help ? 0 : 1;

} # end sub parseopts

sub MainLoop {

	my $self = shift;
	my $sleep = shift;

	my $conf = $self->getconf() || confess "Cannot begin main loop:  Configuration object not found.";

	my $fork = $conf->getOption('daemon');

	if ($fork) {

		$self->logger()->debug(7,"Running in daemon mode.  Forking ...");

		if (fork()) {
			# If we're here, then we're the parent
			close (STDIN);
			close (STDOUT);
			close (STDERR);
			exit(0);
		}

		$self->logger()->debug(7,"\tForked.");

		# Else we're the child. Let's write out our pid
		my $pidfile = $conf->getOption('pidfile') || confess "Cannot fork:  Pidfile not found.";
		open PIDFILE, ">$pidfile" or die "Couldn't open pid file '$pidfile': $!";
		select (PIDFILE); $| = 1;  # autoflush
		select (STDERR);

		print PIDFILE "$$\n";
		close PIDFILE;

	}

	my $sub = $self->getCallback();
	if ($sleep) {
		while (1) {
			$self->logger()->debug(9,"Executing callback from within infinite loop ...");
			&$sub();
			$self->logger()->debug(9,"\tSleeping [$sleep] seconds ...");
			sleep($sleep);
		}
	} else {
		$self->logger()->debug(9,"Executing callback ...");
		&$sub();
	}

} # end sub MainLoop

sub parseconf {

	my $self = shift;
	Peep::Parse->new()->loadConfig( $self->getconf() );
	return 1;

} # end sub parseconf

sub getconf {

	my $self = shift;
	confess "Error getting configuration:  The configuration has not been set yet."
		unless exists $self->{"__CONF"};
	return $self->{"__CONF"};

} # end sub getconf

sub setconf {

	my $self = shift;
	unless (exists $self->{"__CONF"}) { $self->{"__CONF"} = shift }
	return 1;

} # end sub setconf

sub pods {

	my $self = shift;
	my $message = shift;

	print "\n$message\n\n" if $message;

	open(POD,$0) || die "Cannot print help text for $0:  $!";
	Pod::Text->new()->parse_from_filehandle(\*POD);
	close POD;

	exit 0;

} # end sub pods

# returns a logging object
sub logger {

	my $self = shift;
	if ( ! exists $self->{'__LOGGER'} ) { $self->{'__LOGGER'} = new Peep::Log }
	return $self->{'__LOGGER'};

} # end sub logger

# Remove our pidfile with garbage collection (if it exists) The client
# needs to call this function explicitly upon receipt of a signal with
# the appropriate reference.
sub shutdown {
	my $self = shift;
	print STDERR "Shutting down ...\n";
	my $configuration = $self->getconf();
	if (defined $configuration && $configuration->optionExists('pidfile') && -f $configuration->getOption('pidfile') ) {
		print STDERR "\tUnlinking pidfile ", $configuration->getOption('pidfile'), " ...\n";
		unlink $configuration->getOption('pidfile');
	}
	print STDERR "Done.\n";
}    

1;

__END__

=head1 NAME

Peep::Client - Perl extension for client application module subclasses
for Peep: The Network Auralizer.

=head1 SYNOPSIS

  use Peep::Client;
  @INC = qw{ Peep::Client };

  sub new {

      my $self = shift;
      my $class = ref($self) || $self;
      my $this = $class->SUPER::new();
      bless $this, $class;

  } # end sub new

=head1 DESCRIPTION

Provides support methods for the various Peep clients applications,
can be subclassed to create new client modules, and eases the
creation of generic Peep clients.

See the main Peep client documentation or

  perldoc Peep

for more information on usage of this module.

=head1 EXPORT

None by default.

=head1 METHODS

    new() - The constructor

    parseopts(%options) - Sets the value (using the setOption method
    of the Peep::Conf object) of all command-line options parsed by
    Getopt::Long.  Additional options may be specified using %options.
    For more information on the format of the %options hash, see
    Getopt::Long.

    parseconf() - Returns 1 if the option has been defined, 0 otherwise.

    callback($coderef) - Specifies a callback, which must be in the
    form of a code reference, to be used in the MainLoop method.

    MainLoop($sleep) - Starts the main loop.  If $sleep returns false,
    the callback is only called once; otherwise, the main loop sleeps
    $sleep seconds between each call to the callback.

    logger() - Returns a Peep::Log object

=head1 AUTHOR

Michael Gilfix <mgilfix@eecs.tufts.edu> Copyright (C) 2000

Collin Starkweather <collin.starkweather@colorado.edu>

=head1 SEE ALSO

perl(1), peepd(1), Peep::Client::Log, Peep::Client::System, Peep::BC, Peep::Log.

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

$Log: Client.pm,v $
Revision 1.12  2001/04/17 06:46:21  starky
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

Revision 1.11  2001/04/11 04:44:31  starky
Included an intelligent search for the Peep configuration file.  If no file
is specified on the command line or the file specified on the command line
is not found, peep searches the following directories for peep.conf:

  /etc
  /usr/local/etc
  /usr
  /usr/local
  /opt

Revision 1.10  2001/04/07 08:01:05  starky
Corrected some errors in and made some minor changes to the documentation.

Revision 1.9  2001/04/04 05:40:00  starky
Made a more intelligent option parser, allowing a user to more easily
override the default options.  Also moved all error messages that arise
from client options (e.g., using noautodiscovery without specifying
a port and server) from the parseopts method to being the responsibility
of each individual client.

Also made some minor and transparent changes, such as returning a true
value on success for many of the methods which have no explicit return
value.

Revision 1.8  2001/03/31 07:51:34  mgilfix


  Last major commit before the 0.4.0 release. All of the newly rewritten
clients and libraries are now working and are nicely formatted. The server
installation has been changed a bit so now peep.conf is generated from
the template file during a configure - which brings us closer to having
a work-out-of-the-box system.

Revision 1.8  2001/03/31 02:17:00  mgilfix
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

Revision 1.7  2001/03/30 18:34:12  starky
Adjusted documentation and made some modifications to Peep::BC to
handle autodiscovery differently.  This is the last commit before the
0.4.0 release.

Revision 1.6  2001/03/28 02:41:48  starky
Created a new client called 'pinger' which pings a set of hosts to check
whether they are alive.  Made some adjustments to the client modules to
accomodate the new client.

Also fixed some trivial pre-0.4.0-launch bugs.

Revision 1.5  2001/03/27 05:47:55  starky
Forgot to use Pod::Text.

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

Revision 1.1  2001/03/16 18:31:59  starky
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
