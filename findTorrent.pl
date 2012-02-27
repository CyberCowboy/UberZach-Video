#!/usr/bin/perl
use strict;
use warnings;

my $DEBUG               = 0;
my $NO_QUALITY_CHECKS   = 0;
my $MORE_NUMBER_FORMATS = 0;

# Includes
use JSON;
use File::Temp;
use File::Basename;
use lib '/usr/local/spidering/bots/utils';
use Fetch;

# Prototypes
sub findSE($);

# Command line
my ($dir, $search) = @ARGV;
if (!defined($dir) || (!defined($search) && !-d $dir)) {
	die('Usage: ' . basename($0) . " input_directory [search_string]\n");
}
if ($ENV{'DEBUG'}) {
	$DEBUG = 1;
}
if ($ENV{'NO_QUALITY_CHECKS'}) {
	$NO_QUALITY_CHECKS = 1;
}
if ($ENV{'MORE_NUMBER_FORMATS'}) {
	$MORE_NUMBER_FORMATS = 1;
}

# Parameters
my $DELAY            = 4;
my $MIN_COUNT        = 10;
my $MIN_SIZE         = 100;
my $SIZE_BONUS       = 5;
my $SIZE_PENALTY     = $SIZE_BONUS;
my $MAX_SEED_RATIO   = .25;
my $SEED_RATIO_COUNT = 10;
my $PROTOCOL         = 'http';
my $UA               = 'Mozilla/5.0 (Macintosh; U; PPC Mac OS X 10_5_5; en-us) AppleWebKit/525.18 (KHTML, like Gecko) Version/3.1.2 Safari/525.20.1';

# Search sources
my %SOURCES = ();
{
	my %tmp = (
		'search_url'    => 'thepiratebay.se/search/',
		'search_suffix' => '/0/7/0',
		'weight'        => 1.5,
		'quote'         => '0'
	);
	$SOURCES{'TPB'} = \%tmp;
}
{
	my %tmp = (
		'search_url'    => 'isohunt.com/js/json.php?rows=10&start=1&ihq=',
		'search_suffix' => '',
		'weight'        => 0.30,
		'quote'         => 1
	);

	#$SOURCES{'ISO'} = \%tmp;
}

# Environment
#if ($DEBUG) {
#	print STDERR `printenv` . "\n";
#}

# New fetch object
my $cookies = mktemp('/tmp/findTorrent.cookies.XXXXXXXX');
my $fetch   = Fetch->new(
	'cookiefile' => $cookies,
	'uas'        => $UA
);

# Get the season name
my $show          = '';
my @urls          = ();
my $CUSTOM_SEARCH = 0;
my $season        = 0;
my @need          = ();
my %need          = ();
if (defined($search) && length($search) > 0) {

	# Note the custom search string
	$CUSTOM_SEARCH = 1;

	# Create the relevent search strings
	foreach my $key (keys(%SOURCES)) {
		my $source = $SOURCES{$key};
		push(@urls, $PROTOCOL . '://' . $source->{'search_url'} . $search . $source->{'search_suffix'});
	}

	# Get and clean the show name (for post-search matching)
	$show = $dir;
	$show =~ s/[\'\"]//g;
} else {

	# Read the input directory
	if ($DEBUG) {
		print STDERR 'Checking directory: ' . $dir . "\n";
	}

	# Allow quality checks to be disabled
	if (-e dirname($dir) . '/no_quality_checks') {
		$NO_QUALITY_CHECKS = 1;
	}

	# Allow use of more number formats
	if (-e dirname($dir) . '/more_number_formats') {
		$MORE_NUMBER_FORMATS = 1;
	}

	# Get and clean the show name
	$show = basename(dirname($dir));
	$show =~ s/[\'\"]//g;

	# Allow the show name to be overriden
	{
		my $search_name = dirname($dir) . '/search_name';
		if (-e $search_name) {
			local ($/, *FH);
			open(FH, $search_name)
			  or die('Unable to read search_name for show: ' . $show . ': ' . $! . "\n");
			my $text = <FH>;
			close(FH);
			if ($text =~ /^\s*(\S.*\S)\s*$/) {
				$show = $1;
			} else {
				print STDERR 'Skipping invalid search_name for show: ' . $show . ': ' . $text . "\n";
			}
		}
	}
	if ($DEBUG) {
		print STDERR 'Searching with series title: ' . $show . "\n";
	}

	# Get the season number
	my $name = basename($dir);
	if ($name =~ /^\s*Season\s+(\d+)\s*$/i) {
		$season = $1;
	}
	if (!defined($season) || $season < 1 || $season > 2000) {
		if (defined($season)) {
			if ($DEBUG) {
				print STDERR 'Skipping season ' . $season . "\n";
			}
			exit 0;
		}
		die('Invalid season number: ' . $show . ' => ' . $name . "\n");
	}

	# Get the last episode number
	my $no_next  = 0;
	my %episodes = ();
	my $highest  = 0;
	opendir(SEASON, $dir)
	  or die("Unable to open season directory: ${!}\n");
	while (my $file = readdir(SEASON)) {

		# Skip support files
		if ($file =~ /\.(?:png|xml|jpg|gif|tbn|txt|nfo|torrent)\s*$/i) {
			next;
		}

		# Check for a season_done file
		if ($file eq 'season_done') {
			$no_next = 1;
			next;
		}

		# Extract the episode number
		my ($num) = $file =~ /^\s*\.?(\d+)\s*\-\s*/i;
		if (defined($num)) {
			$num = int($num);
			if ($DEBUG) {
				print STDERR 'Found episode number: ' . $num . ' in file: ' . $file . "\n";
			}

			# Record it
			$episodes{$num} = 1;

			# Track the highest episode number
			if ($num > $highest) {
				$highest = $num;
			}
		}
	}
	close(SEASON);

	# Assume we need the next 2 episodes, unless no_next is set (i.e. season_done)
	if (!$no_next) {
		@need = ($highest + 1, $highest + 2);
	}

	# Find any missing episodes
	for (my $i = 1 ; $i <= $highest ; $i++) {
		if (!$episodes{$i}) {
			push(@need, $i);
		}
	}
	if ($DEBUG) {
		print STDERR 'Needed episodes: ' . join(', ', @need) . "\n";
	}

	# Reverse the array for later matching
	foreach my $episode (@need) {
		$need{$episode} = 1;
	}

	# Check for URL files
	if (-e "${dir}/url") {
		open(URL, "${dir}/url")
		  or die("Unable to open URLs file: ${!}\n");
		while (<URL>) {
			if (/^\s*[a-z]+(\:\S+)\s*$/) {
				push(@urls, $PROTOCOL . $1);
			}
		}
		close(URL);
	}

	# Construct a URL-friendly show name
	my $safeShow = $show;
	$safeShow =~ s/\s+\&\s+/ and /i;
	$safeShow =~ s/^\s*The\b//i;
	$safeShow =~ s/[\W_]+/ /g;
	$safeShow =~ s/^\s+//;
	$safeShow =~ s/\s+$//;
	$safeShow =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
	$safeShow =~ s/\%20/\+/g;

	# Calculate possible name variations
	my @urlShowVarients = ();
	{

		# Default name
		push(@urlShowVarients, $safeShow);

		# Search for both "and" and "&"
		if ($safeShow =~ /\+and\+/i) {
			my $tmp = $safeShow;
			$tmp =~ s/\+and\+/\+%26\+/;
			push(@urlShowVarients, $tmp);
		}
	}

	# Construct the URL for each title varient of each needed episode
	foreach my $urlShow (@urlShowVarients) {
		foreach my $episode (@need) {
			my $episode_long = sprintf('%02d', $episode);
			my $season_long  = sprintf('%02d', $season);
			foreach my $source (values(%SOURCES)) {
				my $quote = '%22';
				if (!$source->{'quote'}) {
					$quote = '';
				}

				# SXXEYY
				my $url = $PROTOCOL . '://' . $source->{'search_url'} . $quote . $urlShow . $quote . '+s' . $season_long . 'e' . $episode_long;
				if ($source->{'search_suffix'}) {
					$url .= $source->{'search_suffix'};
				}
				push(@urls, $url);

				# Extra searches for shows that have lazy/non-standard number formats
				if ($MORE_NUMBER_FORMATS) {

					# SXEY
					if ($season_long ne $season || $episode_long ne $episode) {
						$url = $PROTOCOL . '://' . $source->{'search_url'} . $quote . $urlShow . $quote . '+s' . $season . 'e' . $episode;
						if ($source->{'search_suffix'}) {
							$url .= $source->{'search_suffix'};
						}
					}
					push(@urls, $url);

					# SXX EYY
					$url = $PROTOCOL . '://' . $source->{'search_url'} . $quote . $urlShow . $quote . '+s' . $season_long . '+e' . $episode_long;
					if ($source->{'search_suffix'}) {
						$url .= $source->{'search_suffix'};
					}
					push(@urls, $url);

					# Season XX Episode YY
					$url = $PROTOCOL . '://' . $source->{'search_url'} . $quote . $urlShow . $quote . '+season+' . $season_long . '+episode+' . $episode_long;
					if ($source->{'search_suffix'}) {
						$url .= $source->{'search_suffix'};
					}
					push(@urls, $url);

					# SxEE
					$url = $PROTOCOL . '://' . $source->{'search_url'} . $quote . $urlShow . $quote . '+' . $season . 'x' . $episode_long;
					if ($source->{'search_suffix'}) {
						$url .= $source->{'search_suffix'};
					}
					push(@urls, $url);

				}
			}
		}
	}
}

my $content      = '';
my @json_content = ();
foreach my $url (@urls) {

	# Fetch the page
	if ($DEBUG) {
		print STDERR 'Searching with URL: ' . $url . "\n";
		$fetch->file('/tmp/findTorrent-lastPage.html');
	}
	sleep($DELAY * (rand(2) + 0.5));
	$fetch->url($url);
	$fetch->fetch();

	# Check for errors
	if ($fetch->status_code() != 200) {
		print STDERR 'Error fetching URL: ' . $url . "\n";
	}

	# Save and compact the content
	if ($DEBUG) {
		print STDERR 'Fetched ' . length($fetch->content()) . " bytes\n";
	}
	if ($fetch->content() =~ /^\s*{/) {
		my $json = eval { decode_json($fetch->content()); };
		if (defined($json) && ref($json)) {
			push(@json_content, \@{ $json->{'items'}->{'list'} });
		} elsif ($DEBUG) {
			print STDERR 'JSON parsing failure on: ' . $fetch->content() . "\n";
		}
	} else {
		$content .= ' ' . $fetch->content();
		$content =~ s/\s+/ /g;
	}
}

# Find each TR element in TPB content
my @tors = ();
my @trs = split(/\<tr(?:\s+[^\>]*)?\>/i, $content);
if ($DEBUG) {
	print STDERR 'TR count: ' . scalar(@trs) . "\n";
}
foreach my $tr (@trs) {

	# Trim trailing tags
	if (!($tr =~ s/\<\/tr\>.*$//is)) {

		# Skip things that aren't compelete TRs
		if ($DEBUG > 1) {
			print STDERR 'Skipping non-TR line: ' . $tr . "\n\n";
		}
		next;
	}

	# Find the show title
	my ($title) = $tr =~ /title\=\"Details\s+for\s+([^\"]*)\"/i;
	if (!defined($title) || length($title) < 1) {
		if ($DEBUG) {
			print STDERR "Unable to find show title in TR\n";
		}
		next;
	}
	$title =~ s/^\s+//;

	# Extract the season and episode numbers
	my ($fileSeason, $episode) = findSE($title);

	# Extract the URL
	my ($url) = $tr =~ /\<a\s+href\=\"(magnet\:\?[^\"]+)\"/i;
	if (!defined($url) || length($url) < 1) {
		if ($DEBUG) {
			print STDERR "Skipping TR with no magnet URL\n";
		}
		next;
	}

	# Count the sum of seeders and leachers
	my $seeds   = 0;
	my $leaches = 0;
	if ($tr =~ /\<td(?:\s+[^\>]*)?\>(\d+)\<\/td\>\s*\<td(?:\s+[^\>]*)?\>(\d+)\<\/td\>\s*$/i) {
		$seeds   = $1;
		$leaches = $2;
	}

	# Extract the size
	my $size = 0;
	my $unit = 'M';
	if ($tr =~ m/ Size (\d+\.\d+)\&nbsp\;(G|M)iB/) {
		$size = $1;
		$unit = $2;
		if ($unit eq 'G') {
			$size *= 1024;
		}
	}
	$size = int($size);

	if ($DEBUG) {
		print STDERR 'Found file (' . $title . '): ' . $url . "\n";
	}

	# Save the extracted data
	my %tor = (
		'title'   => $title,
		'season'  => $fileSeason,
		'episode' => $episode,
		'seeds'   => $seeds,
		'leaches' => $leaches,
		'size'    => $size,
		'url'     => $url,
		'source'  => 'TPB'
	);
	push(@tors, \%tor);
}

# Find each discrete torrent from ISOhunt
foreach my $json (@json_content) {
	foreach my $tor (@{$json}) {

		# Extract the title
		my $title = $tor->{'title'};
		$title =~ s/\<\/?b\>//gi;
		$title =~ s/^\s+//;

		# Extract the season and episode numbers
		my ($fileSeason, $episode) = findSE($tor->{'title'});

		# Count the sum of seeders and leachers
		my $seeds   = 0;
		my $leaches = 0;
		if (defined($tor->{'Seeds'}) && length($tor->{'Seeds'}) > 0) {
			$seeds = $tor->{'Seeds'};
		}
		if (defined($tor->{'leechers'}) && length($tor->{'leechers'}) > 0) {
			$leaches = $tor->{'leechers'};
		}

		# Extract the size
		my $size = 0;
		if (defined($tor->{'length'}) && length($tor->{'length'}) > 0) {
			$size = int($tor->{'length'} / 1048576);
		}

		if ($DEBUG) {
			print STDERR 'Found file (' . $title . '): ' . $tor->{'enclosure_url'} . "\n";
		}

		# Save the extracted data
		my %tmp = (
			'title'   => $title,
			'season'  => $fileSeason,
			'episode' => $episode,
			'seeds'   => $seeds,
			'leaches' => $leaches,
			'size'    => $size,
			'url'     => $tor->{'enclosure_url'},
			'source'  => 'ISO'
		);
		push(@tors, \%tmp);
	}
}

# Filter for size/count/etc.
my %tors      = ();
my $showRegex = $show;
$showRegex =~ s/[\W_]+/\[\\W_\].*/g;
foreach my $tor (@tors) {

	# Skip files that don't start with our show title
	if (!($tor->{'title'} =~ /^${showRegex}\b/i)) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title does not match (' . $showRegex . '): ' . $tor->{'url'} . "\n";
		}
		next;

		# Skip pre-air files
	} elsif ($tor->{'title'} =~ /preair/i) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains "preair": ' . $tor->{'url'} . "\n";
		}
		next;

		# Skip SWESUB files
	} elsif ($tor->{'title'} =~ /swesub/i) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains "SWESUB": ' . $tor->{'url'} . "\n";
		}
		next;

		# Skip .rus. files
	} elsif ($tor->{'title'} =~ /\.rus\./i) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains ".rus.": ' . $tor->{'url'} . "\n";
		}
		next;

		# Skip german files
	} elsif ($tor->{'title'} =~ /german/i) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Title contains "german": ' . $tor->{'url'} . "\n";
		}
		next;

		# Skip torrents that are too small
	} elsif ($tor->{'size'} < $MIN_SIZE) {
		if ($DEBUG) {
			print STDERR 'Skipping file: Insufficient size (' . $tor->{'size'} . ' MiB): ' . $tor->{'url'} . "\n";
		}
		next;
	}

	# Only apply season and episode number matches if CUSTOM_SEARCH is not in effect
	if (!$CUSTOM_SEARCH) {

		# Skip files that don't contain the right season number
		if (!defined($tor->{'season'}) || $tor->{'season'} != $season) {
			if ($DEBUG) {
				print STDERR 'Skipping file: No match for season number (' . $season . '): ' . $tor->{'url'} . "\n";
			}
			next;

			# Skip files that don't contain the episode number
		} elsif ((!defined($tor->{'episode'}) || !$need{ $tor->{'episode'} })) {
			if ($DEBUG) {
				print STDERR 'Skipping file: No match for episode number (' . $tor->{'episode'} . '): ' . $tor->{'url'} . "\n";
			}
			next;
		}
	}

	# Only apply the quality rules if NO_QUALITY_CHECKS is not in effect
	if (!$NO_QUALITY_CHECKS) {

		# Skip torrents with too few seeders/leachers
		if (($tor->{'seeds'} + $tor->{'leaches'}) * $SOURCES{ $tor->{'source'} }->{'weight'} < $MIN_COUNT) {
			if ($DEBUG) {
				print STDERR 'Skipping file: Insufficient seeder/leacher count (' . $tor->{'seeds'} . '/' . $tor->{'leaches'} . '): ' . $tor->{'url'} . "\n";
			}
			next;

			# Skip torrents with unusual seed/leach ratios
		} elsif ($tor->{'seeds'} > 1
			&& $tor->{'seeds'} < $SEED_RATIO_COUNT
			&& $tor->{'seeds'} > $tor->{'leaches'} * $MAX_SEED_RATIO)
		{
			if ($DEBUG) {
				print STDERR 'Skipping file: Unusual seeder/leacher ratio (' . $tor->{'seeds'} . '/' . $tor->{'leaches'} . '): ' . $tor->{'url'} . "\n";
			}
			next;

		}
	}

	# Save good torrents
	push(@{ $tors{ $tor->{'episode'} } }, $tor);
	if ($DEBUG) {
		print STDERR 'Possible URL (' . $tor->{'seeds'} . '/' . $tor->{'leaches'} . ' seeds/leaches, ' . $tor->{'size'} . ' MiB): ' . $tor->{'url'} . "\n";
	}
}

# Find the average torrent size for each episode
my %avg = ();
foreach my $episode (keys(%tors)) {
	my $count = 0;
	$avg{$episode} = 0.001;
	foreach my $tor (@{ $tors{$episode} }) {
		$avg{$episode} += $tor->{'size'};
		$count++;
	}
	if ($count > 0) {
		$avg{$episode} /= $count;
	}
	if ($DEBUG) {
		print STDERR 'Episode ' . $episode . ' average size: ' . int($avg{$episode}) . " MiB\n";
	}
}

# Calculate an adjusted count based on the original count and the relative file size
foreach my $episode (keys(%tors)) {
	foreach my $tor (@{ $tors{$episode} }) {
		my $count = $tor->{'seeds'} + $tor->{'leaches'};
		if ($tor->{'size'} >= $avg{$episode}) {
			$tor->{'adj_count'} = int($count * ($SIZE_BONUS * ($tor->{'size'} / $avg{$episode})));
		} else {
			$tor->{'adj_count'} = int($count * ((1 / $SIZE_PENALTY) * ($tor->{'size'} / $avg{$episode})));
		}
		if ($DEBUG) {
			print STDERR 'Possible URL (' . $tor->{'adj_count'} . ' size-adjusted sources): ' . $tor->{'url'} . "\n";
		}
	}
}

# Pick the best-adjusted-count torrent for each episode
my %urls = ();
foreach my $episode (keys(%tors)) {
	my $max = undef();
	foreach my $tor (@{ $tors{$episode} }) {
		if (!defined($max) || $tor->{'adj_count'} > $max) {
			$urls{$episode} = $tor->{'url'};
			$max = $tor->{'adj_count'};
			if ($DEBUG) {
				print STDERR 'New semi-final URL (adjusted count: ' . $tor->{'adj_count'} . '): ' . $tor->{'url'} . "\n";
			}
		} elsif ($DEBUG) {
			print STDERR 'Skipping for non-max adjusted count (' . $tor->{'adj_count'} . '): ' . $tor->{'url'} . "\n";
		}
	}
}

# Output
foreach my $episode (keys(%tors)) {
	if (defined($urls{$episode})) {
		print $urls{$episode} . "\n";
		if ($DEBUG) {
			print STDERR 'Final URL: ' . $urls{$episode} . "\n";
		}
	} elsif ($DEBUG) {
		print STDERR 'No URL found for URL: ' . $episode . "\n";
	}
}

# Cleanup
unlink($cookies);
exit(0);

# Extract season
sub findSE($) {
	my ($title) = @_;
	my $season  = 0;
	my $episode = 0;

	if ($title =~ /s(?:eason)?\s*(\d+)/i) {
		$season = $1;
	} elsif ($title =~ /\b(\d+)x(\d+)\b/i) {
		$season  = $1;
		$episode = $2;
	}

	if (!$episode && $title =~ /e(?:ipsode)?\s*(\d+)/i) {
		$episode = $1;
	}

	$season  = int($season);
	$episode = int($episode);
	return ($season, $episode);
}
