#!/usr/bin/perl

# tests both Peep::BC and Peep::Peck

BEGIN { $Test::Harness::verbose++; $|++; print "1..3\n"; }
END {print "not ok\n", exit 1 unless $loaded;}

use Peep::Log;
use Peep::Peck;

$loaded = 1;

print "ok\n";

$Peep::Log::debug = 0;

my ($conf,$parser);

eval {

	$pecker = new Peep::Peck;

};

if ($@) {
	print "not ok:  $@\n";
	exit 1;
} else {
	print "ok\n";
}

$Test::Harness::verbose += 1;

eval { 

	print STDERR <<"eop";


If you have a Peep server running on the machine 
this client is being installed on which just so
happens to be listening to port 2001, you should
hear a sound after pressing Enter.

Please press Enter.
eop

	<STDIN>;
	@ARGV = ( '--type=0','--sound=0','--server=localhost','--port=2001','--volume=255');
	$pecker->peck();

};

if ($@) {
	print STDERR "not ok:  $@";
	exit 1;
} else {
	print "ok\n";
	exit 0;
}

