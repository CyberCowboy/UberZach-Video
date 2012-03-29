#!/usr/bin/perl
use strict;
use warnings;
use Time::HiRes qw( usleep );
use File::Temp qw( tempfile );

# Prototypes
sub mtime($);

# User config
my %DIM = (
	'OFF'   => { 'value' => 0,   'time' => 10000 },
	'PLAY'  => { 'value' => 64,  'time' => 250 },
	'PAUSE' => { 'value' => 192, 'time' => 1000 }
);
my $TIMEOUT = 600;    # Seconds

# App config
my $TEMP_DIR = `getconf DARWIN_USER_TEMP_DIR`;
chomp($TEMP_DIR);
my $DATA_DIR = $TEMP_DIR . '/plexMonitor';
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

# Command-line arguments
my ($DELAY) = @ARGV;
if (!$DELAY) {
	$DELAY = 0.5;
}
$DELAY *= 1000000;    # Microseconds;

# Sanity check
if (!-d $EXEC_DIR || !-d $DATA_DIR) {
	die("Bad config\n");
}

# Always force lights out at launch
system($EXEC_DIR . '/setChannels.py', 0);

# State
my $state      = 'INIT';
my $stateLast  = $state;
my $playing    = 0;
my $projector  = 0;
my $updateLast = 0;
my $valueLast  = $DIM{'OFF'}{'value'};

# Loop forever
while (1) {

	# Monitor the PLAY_STATUS file for changes and state
	{
		my $mtime = mtime($DATA_DIR . '/PLAY_STATUS');
		if ($mtime > $updateLast) {
			$updateLast = $mtime;
		}

		# Grab the PLAY_STATUS value
		$playing = 0;
		my $fh;
		open($fh, $DATA_DIR . '/PLAY_STATUS')
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
		my $mtime = mtime($DATA_DIR . '/PROJECTOR');
		if ($mtime > $updateLast) {
			$updateLast = $mtime;
		}

		# Grab the PROJECTOR value
		$projector = 0;
		my $fh;
		open($fh, $DATA_DIR . '/PROJECTOR')
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

	# Monitor the GUI and PLAYING files for changes only
	{
		my $mtime = mtime($DATA_DIR . '/PLAYING');
		if ($mtime > $updateLast) {
			$updateLast = $mtime;
		}
		$mtime = mtime($DATA_DIR . '/GUI');
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
			$state = 'PAUSE';
		}
	}
	if ($state eq 'INIT') {
		$state = 'OFF';
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
		my ($fh, $tmp) = tempfile($DATA_DIR . '/ROPE.XXXXXXXX', 'UNLINK' => 0);
		print $fh 'State: ' . $state . "\nValue: " . $valueLast . "\n";
		close($fh);
		rename($tmp, $DATA_DIR . '/ROPE');
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
