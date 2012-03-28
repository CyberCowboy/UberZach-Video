#!/usr/bin/perl
use strict;
use warnings;
use Time::HiRes qw( usleep );

# Prototypes
sub mtime($);

# User config
my %DIM = (
	'OFF'   => { 'value' => 0,   'time' => 10000 },
	'PLAY'  => { 'value' => 64,  'time' => 250 },
	'PAUSE' => { 'value' => 192, 'time' => 1000 }
);
my $TIMEOUT = 600;              # Seconds
my $DELAY   = 0.5 * 1000000;    # Microseconds

# App config
my $TEMP_DIR = `getconf DARWIN_USER_TEMP_DIR`;
chomp($TEMP_DIR);
$TEMP_DIR = $TEMP_DIR . '/plexMonitor';
my $EXEC_DIR = $ENV{'HOME'} . '/bin/video/dmx';

# Ensure python can find its OLA imports
my $PYTHON_PATH = "/opt/local/lib/python2.7/site-packages:/opt/local/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/site-packages";
if ($ENV{'PYTHONPATH'}) {
	$PYTHON_PATH = $ENV{'PYTHONPATH'} . ':' . $PYTHON_PATH;
}
$ENV{'PYTHONPATH'} = $PYTHON_PATH;

# Debug
my $DEBUG = 0;
if ($ENV{'DEBUG'}) {
	$DEBUG = 1;
}

# Sanity check
if (!-d $EXEC_DIR || !-d $TEMP_DIR) {
	die("Bad config\n");
}

# Always force lights out at launch
system($EXEC_DIR . '/setChannels.py', 0);

# State
my $state       = 'INIT';
my $stateLast   = $state;
my $playing     = 0;
my $playingLast = $playing;
my $valueLast   = $DIM{'OFF'}{'value'};
my $updateLast  = 0;

# Loop forever
while (1) {

	# Monitor the PLAY_STATUS file for changes and state
	$playingLast = $playing;
	{
		my $mtime = mtime($TEMP_DIR . '/PLAY_STATUS');
		if ($mtime > $updateLast) {
			$updateLast = $mtime;

			# Grab the PLAY_STATUS value
			$playing = 0;
			my $fh;
			open($fh, $TEMP_DIR . '/PLAY_STATUS')
			  or die("Unable to open PLAY_STATUS\n");
			my $text = <$fh>;
			close($fh);
			if ($text =~ /1/) {
				$playing = 1;
			}
		}
	}

	# Monitor the GUI and PLAYING files for changes only
	{
		my $mtime = mtime($TEMP_DIR . '/PLAYING');
		if ($mtime > $updateLast) {
			$updateLast = $mtime;
		}
		$mtime = mtime($TEMP_DIR . '/GUI');
		if ($mtime > $updateLast) {
			$updateLast = $mtime;
		}
	}

	# Calculate the new state
	$stateLast = $state;
	if ($playing != $playingLast) {
		if ($DEBUG) {
			print STDERR "Play state changed\n";
		}

		# We always need to update when the play state changes
		if ($playing) {
			$state = 'PLAY';
		} else {
			$state = 'PAUSE';
		}

	} elsif (!$playing) {

		# If we're not playing, check the timeout
		my $timeSinceUpdate = time() - $updateLast;
		if ($state ne 'OFF' && $timeSinceUpdate > $TIMEOUT) {
			$state = 'OFF';
		} elsif ($state eq 'OFF' && $timeSinceUpdate < $TIMEOUT) {
			$state = 'PAUSE';
		}
	}

	# Update the lighting state
	if ($stateLast ne $state) {
		if ($DEBUG) {
			print STDERR 'New state: ' . $state . "\n";
			print STDERR "\tTime: " . $DIM{$state}{'time'} . "\n";
			print STDERR "\tFrom: " . $valueLast . "\n";
			print STDERR "\tTo: " . $DIM{$state}{'value'} . "\n";
		}
		if ($valueLast != $DIM{$state}{'value'}) {
			system($EXEC_DIR . '/dimChannels.py', $DIM{$state}{'time'}, $valueLast, $DIM{$state}{'value'});
		} elsif ($DEBUG) {
			print STDERR "Skipping noop dim request\n";
		}
		$valueLast = $DIM{$state}{'value'};

		# Save the state and value to disk
		my $fh;
		open($fh, '>', $TEMP_DIR . '/ROPE')
		  or die("Unable to open ROPE");
		print $fh 'State: ' . $state . "\nValue: " . $valueLast . "\n";
		close($fh);
		open($fh, '>', $TEMP_DIR . '/ROPE.lastUpdate')
		  or die("Unable to open ROPE");
		print $fh time() . "\n";
		close($fh);
	}

	# Wait and loop
	usleep($DELAY);
}

sub mtime($) {
	my ($file) = @_;
	my (undef(), undef(), undef(), undef(), undef(), undef(), undef(), undef(), undef(), $mtime, undef(), undef(), undef()) = stat($file);
	return $mtime;
}
