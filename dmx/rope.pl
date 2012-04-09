#!/usr/bin/perl
use strict;
use warnings;
use IO::Socket;
use Time::HiRes qw( usleep );
use File::Temp qw( tempfile );

# Prototypes
sub mtime($);
sub dim($$$);

# User config
my %DIM = (
	'OFF'    => [ { 'value' => 0,   'time' => 60000 }, { 'value' => 0,   'time' => 60000 } ],
	'PLAY'   => [ { 'value' => 64,  'time' => 500 },   { 'value' => 32,  'time' => 500 } ],
	'PAUSE'  => [ { 'value' => 255, 'time' => 1000 },  { 'value' => 192, 'time' => 10000 } ],
	'MOTION' => [ { 'value' => 255, 'time' => 1000 },  { 'value' => 192, 'time' => 1000 } ],
);
my $TIMEOUT      = 300;    # Seconds
my $NUM_CHANNELS = 2;

# App config
my $SOCK_TIMEOUT = 5;
my $TEMP_DIR     = `getconf DARWIN_USER_TEMP_DIR`;
chomp($TEMP_DIR);
my $DATA_DIR = $TEMP_DIR . 'plexMonitor/';
my $CMD_FILE = $DATA_DIR . 'DMX.socket';

# Debug
my $DEBUG = 0;
if ($ENV{'DEBUG'}) {
	$DEBUG = 1;
}

# Command-line arguments
my ($DELAY) = @ARGV;
if (!$DELAY) {
	$DELAY = 0.5;
}
$DELAY *= 1000000;    # Microseconds;

# Sanity check
if (!-d $DATA_DIR || !-S $CMD_FILE) {
	die("Bad config\n");
}

# Socket init
my $sock = IO::Socket::UNIX->new(
	'Peer'    => $CMD_FILE,
	'Type'    => SOCK_DGRAM,
	'Timeout' => $SOCK_TIMEOUT
) or die('Unable to open socket: ' . $CMD_FILE . ": ${@}\n");

# State
my $state      = 'INIT';
my $stateLast  = $state;
my $playing    = 0;
my $projector  = 0;
my $updateLast = 0;

# Always force lights out at launch
dim(0, 0, 0);

# Loop forever
while (1) {

	# Monitor the PLAY_STATUS file for changes and state
	{
		my $mtime = mtime($DATA_DIR . 'PLAY_STATUS');
		if ($mtime > $updateLast) {
			$updateLast = $mtime;
		}

		# Grab the PLAY_STATUS value
		$playing = 0;
		my $fh;
		open($fh, $DATA_DIR . 'PLAY_STATUS')
		  or die("Unable to open PLAY_STATUS\n");
		my $text = <$fh>;
		close($fh);
		if ($text =~ /1/) {
			$playing = 1;
		}
		if ($DEBUG) {
			print STDERR 'Playing: ' . $playing . "\n";
		}
	}

	# Monitor the PROJECTOR file for changes and state
	{
		my $mtime = mtime($DATA_DIR . 'PROJECTOR');
		if ($mtime > $updateLast) {
			$updateLast = $mtime;
		}

		# Grab the PROJECTOR value
		$projector = 0;
		my $fh;
		open($fh, $DATA_DIR . 'PROJECTOR')
		  or die("Unable to open PROJECTOR\n");
		my $text = <$fh>;
		close($fh);
		if ($text =~ /1/) {
			$projector = 1;
		}
		if ($DEBUG) {
			print STDERR 'Projector: ' . $projector . "\n";
		}
	}

	# Monitor the GUI, PLAYING, and MOTION files for changes only
	{
		my $mtime = mtime($DATA_DIR . 'PLAYING');
		if ($mtime > $updateLast) {
			$updateLast = $mtime;
		}
		$mtime = mtime($DATA_DIR . 'GUI');
		if ($mtime > $updateLast) {
			$updateLast = $mtime;
		}
		$mtime = mtime($DATA_DIR . 'MOTION');
		if ($mtime > $updateLast) {
			$updateLast = $mtime;
		}
	}

	# Calculate the new state
	$stateLast = $state;
	if ($projector) {

		# We are always either playing or paused if the projector is on
		if ($playing) {
			$state = 'PLAY';
		} else {
			$state = 'PAUSE';
		}

	} else {

		# If the projector is off, check the timeouts
		my $timeSinceUpdate = time() - $updateLast;
		if ($state ne 'OFF' && $timeSinceUpdate > $TIMEOUT) {
			$state = 'OFF';
		} elsif ($state eq 'OFF' && $timeSinceUpdate < $TIMEOUT) {
			$state = 'MOTION';
		}
	}
	if ($state eq 'INIT') {
		$state = 'OFF';
	}

	# Update the lighting state
	if ($stateLast ne $state) {
		if ($DEBUG) {
			print STDERR 'State: ' . $stateLast . ' => ' . $state . "\n";
			for (my $i = 0 ; $i < $NUM_CHANNELS ; $i++) {
				print STDERR 'Channel ' . ($i + 1) . ': ' . $DIM{$state}[$i]{'value'} . '@' . $DIM{$state}[$i]{'time'} . "\n";
			}
		}

		# Send the dim command
		my @values = ();
		for (my $i = 0 ; $i < $NUM_CHANNELS ; $i++) {
			dim($i + 1, $DIM{$state}[$i]{'time'}, $DIM{$state}[$i]{'value'});
			push(@values, $DIM{$state}[$i]{'value'});
		}

		# Save the state and value to disk
		my ($fh, $tmp) = tempfile($DATA_DIR . 'ROPE.XXXXXXXX', 'UNLINK' => 0);
		print $fh 'State: ' . $state . "\nValue: " . join(',', @values) . "\n";
		close($fh);
		rename($tmp, $DATA_DIR . 'ROPE');
	}

	# Wait and loop
	usleep($DELAY);
}

sub mtime($) {
	my ($file) = @_;
	my $mtime = 0;
	if (-r $file) {
		(undef(), undef(), undef(), undef(), undef(), undef(), undef(), undef(), undef(), $mtime, undef(), undef(), undef()) = stat($file);
	}
	return $mtime;
}

# Send the command
sub dim($$$) {
	my ($channel, $duration, $intensity) = @_;
	my $cmd = join(':', $channel, $duration, $intensity);
	$sock->send($cmd)
	  or die('Unable to write command to socket: ' . $CMD_FILE . ': ' . $cmd . ": ${!}\n");
}
