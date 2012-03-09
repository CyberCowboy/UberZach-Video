#!/usr/bin/perl
use warnings;
use strict;

# Includes
use JSON;
use Date::Parse;
use File::Temp qw/ :mktemp /;
use File::Basename;
use Fetch;

# Prototypes
sub session($);
sub fetch($);
sub getSSE($);
sub getDest($$$$);
sub delTor($);
sub guessExt($);
sub processFile($$);
sub unrar($$);
sub seriesCleanup($);
sub readDir($$);

# Parameters
my $maxAge        = 2.5 * 86400;
my $tvDir         = '/mnt/media/TV';
my $monitoredExec = '/Users/profplump/bin/video/torrentMonitored.pl';
my $host          = 'http://localhost:9091';
my $url           = $host . '/transmission/rpc';
my $content       = '{"method":"torrent-get","arguments":{"fields":["hashString","id","addedDate","comment","creator","dateCreated","isPrivate","name","totalSize","pieceCount","pieceSize","downloadedEver","error","errorString","eta","haveUnchecked","haveValid","leftUntilDone","metadataPercentComplete","peersConnected","peersGettingFromUs","peersSendingToUs","rateDownload","rateUpload","recheckProgress","sizeWhenDone","status","trackerStats","uploadedEver","uploadRatio","seedRatioLimit","seedRatioMode","downloadDir","files","fileStats"]}}';
my $delContent    = '{"method":"torrent-remove","arguments":{"ids":["#_ID_#"], "delete-local-data":"true"}';
my $RAR_MIN_FILES = 4;

# Debug
my $DEBUG = 0;
if ($ENV{'DEBUG'}) {
	$DEBUG = 1;
}

# Command-line parameters
my ($force, $maxDays) = @ARGV;

# Init
my $fetch = Fetch->new();

# Check availability of web interface
$fetch->url($host);
if ($DEBUG) {
	print STDERR "Checking for torrent web interface\n";
}
$fetch->fetch('nocheck' => 1);
if ($fetch->status_code() != 200) {
	if ($DEBUG) {
		die("Transmission web interface not available\n");
	}
	exit(0);
}

# Fetch the list of paused (i.e. completed) torrents
$fetch->url($url);
$fetch->post_content($content);
&fetch($fetch);

my $torrents = decode_json($fetch->content());
$torrents = $torrents->{'arguments'}->{'torrents'};

# Process
if ($DEBUG) {
	print STDERR "Processing torrents...\n";
}
foreach my $tor (@{$torrents}) {

	# Skip torrents that aren't yet done
	if ($tor->{'leftUntilDone'} > 0 || $tor->{'metadataPercentComplete'} < 1) {
		next;
	}

	# Only process recent files
	# Torrents created with magnet links have no dateCreated, so fake it with addedDate
	if ($tor->{'dateCreated'} < 946684800) {
		$tor->{'dateCreated'} = $tor->{'addedDate'};
	}
	if (!$force && $tor->{'dateCreated'} < time() - $maxAge) {
		my $age = (time() - $tor->{'dateCreated'}) / 86400;
		if ($DEBUG) {
			print STDERR 'Skipping old torrent: ' . $tor->{'name'} . ' (' . sprintf('%.0f', $age) . " days)\n";
		}
		next;
	}
	if ($DEBUG) {
		print STDERR 'Processing finished torrent: ' . $tor->{'name'} . "\n";
	}

	# Handle individual files and directories
	my $file     = '';
	my @newFiles = ();
	my $path     = $tor->{'downloadDir'} . '/' . $tor->{'name'};
	if (-d $path) {

		# State variables
		my $IS_RAR  = '';
		my $IS_FAKE = 0;

		# Look for RAR files
		foreach my $file (@{ $tor->{'files'} }) {
			if ($file->{'name'} =~ /\.rar$/i) {
				$IS_RAR = $tor->{'downloadDir'} . '/' . $file->{'name'};
				last;
			}
		}

		# Check for password files
		foreach my $file (@{ $tor->{'files'} }) {
			if ($file->{'name'} =~ /passw(?:or)?d/i) {
				print STDERR 'Password file detected in: ' . $tor->{'name'} . "\n";
				$IS_FAKE = 1;
				last;
			}
		}

		# Check for single-file RARs
		if ($IS_RAR && scalar(@{ $tor->{'files'} }) < $RAR_MIN_FILES) {
			print STDERR 'Single-file RAR detected in: ' . $tor->{'name'} . "\n";
			$IS_FAKE = 1;
		}

		# Find media files in valid torrents
		if (!$IS_FAKE) {

			# Unrar if necessary
			if (defined($IS_RAR) && length($IS_RAR) > 0) {
				@newFiles = &unrar($IS_RAR, $path);
			}

			# Find exactly 1 media file
			my @files = ();
			my @tmpFiles = readDir($path, '/\.(?:avi|mkv|m4v|mov|mp4|ts|wmv)$/i');
			foreach my $file (@tmpFiles) {
				if ($file =~ /sample/i) {
					next;
				}
				push(@files, $file);
			}
			if (scalar(@files) != 1) {
				print STDERR 'Unable to find a media file in: ' . $path . "\n";
				next;
			}
			$file = $files[0];
		} else {
			$file = '';
		}
	} else {
		$file = $path;
	}

	# Do all the normal file naming/copying/etc. if we found a file
	my $result = -1;
	if (defined($file) && length($file) > 0 && -r $file) {
		$result = &processFile($file, $path);
	}
	if (defined($result) && $result == 1) {
		if ($DEBUG) {
			print STDERR 'Torrent stored successfully: ' . $tor->{'name'} . "\n";
		}
	} elsif (defined($result) && $result == -1) {
		print STDERR 'Deleting bad torrent: ' . $tor->{'name'} . "\n";
	} else {
		print STDERR 'Error storing file "' . basename($file) . '" from torrent: ' . $tor->{'name'} . "\n";
		next;
	}

	# Delete any files we added
	foreach my $file (@newFiles) {
		if ($DEBUG) {
			print STDERR 'Deleting new file: ' . basename($file) . "\n";
		}
		unlink($file);
	}

	# Remove the source torrent (it's either copied or bad by this point)
	delTor($tor);
}

# Cleanup
exit(0);

# Grab the session ID
sub session($) {
	my ($fetch) = @_;
	my %headers = ();
	($headers{'X-Transmission-Session-Id'}) = $fetch->content() =~ /X\-Transmission\-Session\-Id\:\s+(\w+)/;
	$fetch->headers(\%headers);
}

sub fetch($) {
	my ($fetch) = @_;
	$fetch->fetch('nocheck' => 1);
	if ($fetch->status_code() != 200) {
		&session($fetch);
		$fetch->fetch();
		if ($fetch->status_code() != 200) {
			die('Unable to fetch: ' . $fetch->status_code() . "\n");
		}
	}
}

sub getSSE($) {
	my ($name) = @_;

	if ($DEBUG) {
		print STDERR 'Finding series/season/episode for: ' . $name . "\n";
	}

	my $season      = 0;
	my $episode     = 0;
	my $seasonBlock = '';
	if ($name =~ /(?:\b|_)(S\d{1,2}[_\s\.]?E\d{1,2})(?:\b|_)/i) {
		$seasonBlock = $1;
		($season, $episode) = $seasonBlock =~ /S(\d{1,2})[_\s\.]?E(\d{1,2})/i;
		$season = int($season);
		$episode = sprintf('%02d', int($episode));
	} elsif ($name =~ /[\[\_\.](\d{1,2}x\d{2,3})[\]\_\.]/i) {
		$seasonBlock = $1;
		($season, $episode) = $seasonBlock =~ /(\d+)x(\d+)/i;
		$season = int($season);
		$episode = sprintf('%02d', int($episode));
	} elsif ($name =~ /(?:\b|_)(20\d\d(?:\.|\-)[01]?\d(?:\.|\-)[0-3]?\d)(?:\b|_)/) {
		$seasonBlock = $1;
		my ($month, $day);
		($season, $month, $day) = $seasonBlock =~ /(20\d\d)(?:\.|\-)([01]?\d)(?:\.|\-)([0-3]?\d)/;
		$season = int($season);
		$episode = sprintf('%04d-%02d-%02d', $season, $month, $day);
	} elsif ($name =~ /(?:\b|_)([01]?\d[_\s\.]?[0-3]\d)(?:\b|_)/i) {
		$seasonBlock = $1;
		($season, $episode) = $seasonBlock =~ /(?:\b|_)([01]?\d)[_\s\.]?([0-3]\d)/i;
		$season = int($season);
		$episode = sprintf('%02d', int($episode));
	}
	if (!defined($seasonBlock) || $season < 1 || length($episode) < 1 || $episode eq '0') {
		if ($DEBUG) {
			print STDERR 'Could not find seasonBlock in: ' . $name . "\n";
		}
		return;
	}

	# Assume the series titles comes before the season/episode block
	my $series = '';
	my $sIndex = index($name, $seasonBlock);
	if ($sIndex > 0) {
		$series = substr($name, 0, $sIndex - 1);
		$series = seriesCleanup($series);
	}

	if ($DEBUG) {
		print STDERR 'Series: ' . $series . ' Season: ' . $season . ' Episode: ' . $episode . "\n";
	}
	return ($series, $season, $episode);
}

sub getDest($$$$) {
	my ($series, $season, $episode, $ext) = @_;
	if ($DEBUG) {
		print STDERR 'Finding destintion for: ' . $series . ' S' . $season . 'E' . $episode . "\n";
	}

	# Find all our existing TV series
	my @shows    = ();
	my %showsCan = ();
	open(SHOWS, '-|', $monitoredExec, 'STORE')
	  or die("Unable to fork: ${!}\n");
	while (<SHOWS>) {
		chomp;
		my $orig  = $_;
		my $clean = seriesCleanup($_);
		push(@shows, $clean);
		$showsCan{$clean} = $orig;
	}
	close SHOWS or die("Unable to read monitored series list: ${!} ${?}\n");

	# See if we can find a unique series name match
	my $sClean = seriesCleanup($series);
	my $sMatch = '\b' . $sClean . '\b';
	$series = '';

	foreach my $show (@shows) {

		if ($show =~ /${sMatch}/i) {

			# Enforce any secondary matching rules (for ambiguous titles)
			my $detail_match = 1;
			{
				my @lines;
				my $file = $tvDir . '/' . $showsCan{$show} . '/must_match';
				if (-e $file) {
					if ($DEBUG) {
						print STDERR 'Reading must_match file: ' . $file . "\n";
					}
					local ($/, *FH);
					open(FH, $file)
					  or die('Unable to read must_match file: ' . $file . "\n");
					my @tmp = <FH>;
					close(FH);
					push(@lines, @tmp);
				}
				foreach my $line (@lines) {
					chomp($line);
					if (!eval('$sClean =~ m' . $line)) {
						if ($DEBUG) {
							print STDERR 'Skipping ' . $show . ' due to must_match failure for: ' . $line . "\n";
						}
						$detail_match = 0;
						last;
					}
				}
			}
			if (!$detail_match) {
				next;
			}

			# Bail if we find more than one matching series
			if (length($series) > 0) {
				print STDERR 'Matched both ' . $series . ' and ' . $show . "\n";
				return;
			}

			# If we're still around this is the first series title match
			$series = $show;
		}
	}
	if (length($series) < 1) {
		if ($DEBUG) {
			print STDERR 'No series match for: ' . $sMatch . "\n";
		}
		return;
	}

	# Lookup the canonical name from the matched name
	$series = $showsCan{$series};

	# Make sure we have the right season folder
	my $seriesDir = $tvDir . '/' . $series;
	my $seasonDir = $seriesDir . '/' . 'Season ' . $season;
	if (!-d $seasonDir) {
		print STDERR 'No season folder for: ' . $series . ' S' . $season . "\n";
		return;
	}

	# Bail if we already have this episode
	my @episodes = readDir($seasonDir, '/^\s*[\d\-]+\s*\-\s*/');
	foreach my $ep (@episodes) {
		$ep = basename($ep);
		my ($epNum) = $ep =~ /^\s*([\d\-]+)\s*\-\s*/;
		$epNum   =~ s/^0+//;
		$episode =~ s/^0+//;
		if ($epNum eq $episode) {
			print STDERR 'Existing episode for: ' . $series . ' S' . $season . 'E' . $episode . "\n";
			return;
		}
	}

	# Construct the final path
	if (!defined($ext) || length($ext) < 1) {
		$ext = 'avi';
	}
	if ($episode =~ /^\d+$/) {
		$episode = sprintf('%02d', $episode);
	}
	my $dest = sprintf('%s/%s - NoName.%s', $seasonDir, $episode, $ext);

	if ($DEBUG) {
		print STDERR 'Destination: ' . $dest . "\n";
	}
	return $dest;
}

sub delTor($) {
	my ($tor) = @_;
	if ($DEBUG) {
		print STDERR 'Deleting torrent: ' . $tor->{'name'} . "\n";
	}

	# Construct the content
	my $id      = $tor->{'hashString'};
	my $content = $delContent;
	$content =~ s/\#_ID_\#/${id}/;

	# Send the command
	&session($fetch);
	$fetch->post_content($content);
	&fetch($fetch);
}

sub guessExt($) {
	my ($file) = @_;
	if ($DEBUG) {
		print STDERR 'Guessing extension for: ' . basename($file) . "\n";
	}

	# Believe most non-avi file extensions without checking
	# It's mostly "avi" that lies, and the checks are expensive
	my $ext = '';
	{
		my $orig_ext = basename($file);
		$orig_ext =~ s/^.*\.(\w{2,3})$/$1/;
		$orig_ext = lc($orig_ext);
		if ($orig_ext eq 'mkv' || $orig_ext eq 'ts') {
			$ext = $orig_ext;
			if ($DEBUG) {
				print STDERR 'Accepting declared file extension: ' . $ext . "\n";
			}
		}
	}

	# Ask movInfo.pl about the demuxer
	if (!$ext) {
		my $demux = '';
		open(INFO, '-|', $ENV{'HOME'} . '/bin/video/movInfo.pl', $file, 'DEMUXER');
		while (<INFO>) {
			$demux .= $_;
		}
		close(INFO);
		$demux =~ s/^\s+//;
		$demux =~ s/\s+$//;

		# Grab a MIME type from file(1)
		my $mime = '';
		open(FILE, '-|', 'file', '-b', $file);
		while (<FILE>) {
			$mime .= $_;
		}
		close(FILE);
		$mime =~ s/^\s+//;
		$mime =~ s/\s+$//;
		$mime =~ s/\;.*$//;
		$mime =~ s/^video\///i;

		# Try to pick an extension we understand
		$ext = 'avi';
		if ($demux =~ /mkv/i || $mime =~ /Matroska/i) {
			$ext = 'mkv';
		} elsif ($demux =~ /asf/i || $mime =~ /\bASF\b/i) {
			$ext = 'wmv';
		} elsif ($mime =~ /\bZIP/i) {
			$ext = 'zip';
		} elsif ($mime =~ /\bAVI\b/i) {
			$ext = 'avi';
		} elsif ($demux =~ /mpegts/i) {
			$ext = 'ts';
		}
	}

	if ($DEBUG) {
		print STDERR 'File extension: ' . $ext . "\n";
	}
	return $ext;
}

sub processFile($$) {
	my ($file, $path) = @_;
	if ($DEBUG) {
		print STDERR 'Attempting to process file: ' . basename($file) . "\n";
	}

	# Guess a file extension
	my $ext = &guessExt($file);

	# Delete WMV files -- mostly viruses
	if ($ext =~ /wmv/i) {
		print STDERR 'Declining to save WMV file: ' . basename($file) . "\n";
		return -1;
	}

	# Delete ZIP files -- mostly fake
	if ($ext =~ /zip/i) {
		print STDERR 'Declining to save ZIP file: ' . basename($file) . "\n";
		return -1;
	}

	# Allow multiple guesses at the series/season/episode
	my $dest     = '';
	my $filename = basename($file);
	LOOP: {

		# Determine the series, season, and episode number
		my ($series, $season, $episode) = &getSSE($filename);
		if (   defined($series)
			&& length($series) > 0
			&& defined($season)
			&& $season > 0
			&& defined($episode)
			&& length($episode) > 0
			&& $episode ne '0')
		{

			# Find the proper destination for this torrent, if any
			$dest = &getDest($series, $season, $episode, $ext);
		}

		# Sanity/loop check
		if (!defined($dest) || length($dest) < 1) {

			# If there is no match but the torrent is a folder
			# retry the guess using the torrent path
			if ($file ne $path) {
				my $newName = basename($path);
				if ($newName ne $filename) {
					$filename = basename($path);
					redo LOOP;
				}
			}

			# Otherwise we just fail
			print STDERR 'No destination for: ' . basename($file) . "\n";
			return;
		}
	}

	# Copy with system tools
	if ($DEBUG) {
		print STDERR 'Copying file: ' . basename($file) . "\n";
	}
	my $tmp = mktemp($dest . '.XXXXXXXX');
	Run::runAndCheck(('cp', $file, $tmp));
	rename($tmp, $dest);

	# Return success
	return 1;
}

sub unrar($$) {
	my ($file, $path) = @_;
	if ($DEBUG) {
		print STDERR 'UnRARing: ' . basename($file) . "\n";
	}

	# Keep a list of old files, so we can find/delete the output
	my @beforeFiles = readDir($path, undef());

	# Run the unrar utility
	my $pid = fork();
	if (!defined($pid)) {
		print STDERR "Unable to fork for RAR\n";
		return;
	} elsif ($pid == 0) {

		# Child
		close(STDOUT);
		close(STDERR);
		chdir($path);
		my @args = ('unrar', 'e', '-p-', '-y', $file);
		exec { $args[0] } @args;
	}

	# Wait for the child
	waitpid($pid, 0);

	# Compare the old file list to the new one
	my @newFiles = ();
	my @afterFiles = readDir($path, undef());
	foreach my $file (@afterFiles) {
		my $found = 0;
		foreach my $file2 (@beforeFiles) {
			if ($file eq $file2) {
				$found = 1;
				last;
			}
		}
		if (!$found) {
			push(@newFiles, $file);
		}
	}

	# Return the list of added files
	return @newFiles;
}

sub seriesCleanup($) {
	my ($name) = @_;
	$name =~ s/\b(?:and|\&)\b/ /ig;
	$name =~ s/^\s*The\b//ig;
	$name =~ s/\bUS\b?\s*$//ig;
	$name =~ s/\[[^\]]*\]//g;
	$name =~ s/\([^\)]*\)//g;
	$name =~ s/\{[^\}]*\}//g;
	$name =~ s/[\(\)]//g;
	$name =~ s/[\'\"]//g;
	$name =~ s/[^\w\s]+/ /g;
	$name =~ s/\b20[01][0-9]\s*$//;
	$name =~ s/_+/ /g;
	$name =~ s/\s+/ /g;
	$name =~ s/^\s*//;
	$name =~ s/\s*$//;
	return $name;
}

sub readDir($$) {
	my ($indir, $regex) = @_;

	# Allow optional use of a matching regex
	my $useRegex = 1;
	if (!defined($regex) || length($regex) < 1) {
		$useRegex = 0;
	}

	# Clean up the input directory
	$indir =~ s/\/+$//;

	my @files = ();
	if (!opendir(DIR, $indir)) {
		warn('readDir: Unable to read directory: ' . $indir . ': ' . $! . "\n");
		return;
	}
	foreach my $file (readdir(DIR)) {
		my $keep = 0;

		# Regex filter (if active)
		if (!$useRegex) {
			$keep = 1;
		} elsif (eval('$file =~ m' . $regex)) {
			$keep = 1;
		}

		# Construct a complete file path
		$file = $indir . '/' . $file;

		# Ignore directories
		if (-d $file) {
			$keep = 0;
		}

		# Save matching files
		if ($keep) {
			push(@files, $file);
		}
	}
	closedir(DIR);

	# Sorts the files before returning to the caller
	my @orderedFiles = ();
	@orderedFiles = sort(@files);

	# Return the file list
	return (@orderedFiles);
}
