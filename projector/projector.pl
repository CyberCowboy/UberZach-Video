#!/usr/bin/perl
use strict;
use warnings;
use Device::SerialPort;
use File::Temp qw( tempfile );

# Prototypes
sub sendQuery($$);
sub collectUntil($$);

# Serial parameters
my $PORT = '/dev/tty.Projector-DevB';

# Protocol parameters
my $CRLF      = "\r\n";
my $DELIMITER = ':';

# App config
my $BYTE_TIMEOUT    = 500;
my $SILENCE_TIMEOUT = $BYTE_TIMEOUT * 10;
my $TEMP_DIR        = `getconf DARWIN_USER_TEMP_DIR`;
chomp($TEMP_DIR);
my $DATA_DIR = $TEMP_DIR . '/plexMonitor';
my $CMD_FILE = $DATA_DIR . '/PROJECTOR_CMD';

# Debug
my $DEBUG = 0;
if ($ENV{'DEBUG'}) {
	$DEBUG = 1;
}

# Command-line arguments
my ($DELAY) = @ARGV;
if (!$DELAY) {
	$DELAY = 15;
}

# Sanity check
if (!-r $PORT || !-d $DATA_DIR) {
	die("Bad config\n");
}

# Port init
my $port = new Device::SerialPort($PORT)
  or die("Unable to open projector serial connection\n");
$port->read_const_time($BYTE_TIMEOUT);
$port->lookclear();

# Projector init (clear any previous state)
sendQuery($port, '');

# Track the projector power state
my $power     = -1;
my $powerLast = $power;
while (1) {

	# Check for queued commands
	my $cmd = undef();
	if (-r $CMD_FILE) {
		if ($DEBUG) {
			print STDERR "Found projector command file\n";
		}

		# Open and immediately unlink the file (to de-queue the command)
		my $fh;
		open($fh, $CMD_FILE);
		unlink($CMD_FILE);

		# If we got the file open before it disappeared
		if ($fh) {
			my $text = <$fh>;
			chomp($text);
			close($fh);
			if ($DEBUG) {
				print STDERR 'Got raw command: ' . $text . "\n";
			}

			# Check for known commands
			if ($text =~ /OFF/i) {
				$cmd = 'OFF';
			} elsif ($text =~ /ON/i) {
				$cmd = 'ON';
			}
			if ($DEBUG) {
				print STDERR 'Found command: ' . $cmd . "\n";
			}
		}

		# If we got a command, validate it
		if ($cmd) {
			if ($cmd eq 'ON' && $power) {
				$cmd = undef();
			} elsif ($cmd eq 'OFF' && !$power) {
				$cmd = undef();
			}
		}

		# Send the command
		if ($cmd) {
			if ($DEBUG) {
				print STDERR 'Sending command: ' . $cmd . "\n";
			}
			my $result = undef();
			if ($cmd eq 'OFF') {
				$result = sendQuery($port, 'PWR OFF');
			} elsif ($cmd eq 'ON') {
				$result = sendQuery($port, 'PWR ON');
			}
		}
	}

	# Check the power state
	$powerLast = $power;
	$power     = 0;
	my $result = sendQuery($port, 'PWR?');
	if ($result =~ /PWR\=(\d+)/) {
		if ($1 > 0) {
			$power = 1;
		}
	}

	# If something has changed, save the state to disk
	if ($powerLast != $power) {
		if ($DEBUG) {
			print STDERR 'New projector power state: ' . $power . "\n";
		}
		my ($fh, $tmp) = tempfile($DATA_DIR . '/PROJECTOR.XXXXXXXX', 'UNLINK' => 0);
		print $fh $power . "\n";
		close($fh);
		rename($tmp, $DATA_DIR . '/PROJECTOR');
	}

	# Delay and loop
	sleep($DELAY);
}

# Cleanup
$port->close();
undef($port);
exit(0);

sub sendQuery($$) {
	my ($port, $query) = @_;
	$port->lookclear();
	my $bytes = $port->write($query . $CRLF);
	if ($DEBUG) {
		print STDERR "\tWrote (" . $bytes . '): ' . $query . "\n";
	}
	my $data = collectUntil($port, $DELIMITER);
	return $data;
}

sub collectUntil($$) {
	my ($port, $char) = @_;
	if (length($char) != 1) {
		die('Invalid collection delimiter: ' . $char . "\n");
	}

	# This byte-by-byte reading is not efficient, but it's safe
	# Allow reading forever as long as we don't exceed the silence timeout
	my $count  = 0;
	my $string = '';
	while ($count < $SILENCE_TIMEOUT / $BYTE_TIMEOUT) {
		my $byte = $port->read(1);
		if ($byte) {
			$count = 0;
			$string .= $byte;

			if ($DEBUG) {
				print STDERR "\tRead: " . $byte . "\n";
			}

			if ($byte eq $char) {
				last;
			}
		} else {
			$count++;
		}
	}

	# Return undef if there was no data (as opposed to just a delimiter and/or whitespace)
	if (length($string) < 1) {
		if ($DEBUG) {
			print STDERR "Read: <NO DATA>\n";
		}
		return undef();
	}

	# Strip leading or trailing whitespace
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;

	# Strip the trailing delimiter
	$string =~ s/${char}$//;

	# Return our clean string
	if ($DEBUG) {
		print STDERR 'Read: ' . $string . "\n";
	}
	return $string;
}
