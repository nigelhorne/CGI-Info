#!/usr/bin/env perl

use strict;
use warnings;

use JSON::MaybeXS;
use File::Glob ':glob';
use File::Slurp;
use POSIX qw(strftime);
use File::stat;

my $cover_db = 'cover_db/cover.json';
my $output = 'cover_html/index.html';

# Read and decode coverage data
my $json_text = read_file($cover_db);
my $data = decode_json($json_text);

my $coverage_pct = 0;
my $badge_color = 'red';

if(my $total_info = $data->{summary}{Total}) {
	$coverage_pct = int($total_info->{total}{percentage} // 0);
	$badge_color = $coverage_pct > 80 ? 'brightgreen' : $coverage_pct > 50 ? 'yellow' : 'red';
}

my $coverage_badge_url = "https://img.shields.io/badge/coverage-${coverage_pct}%25-${badge_color}";

# Start HTML
my $html = <<"HTML";
<!DOCTYPE html>
<html>
	<head>
	<title>CGI::Info Coverage Report</title>
	<style>
		body { font-family: sans-serif; }
		table { border-collapse: collapse; width: 100%; }
		th, td { border: 1px solid #ccc; padding: 8px; text-align: left; }
		th { background-color: #f2f2f2; }
		.low { background-color: #fdd; }
		.med { background-color: #ffd; }
		.high { background-color: #dfd; }
		.badges img { margin-right: 10px; }
		.disabled-icon {
			opacity: 0.4;
			cursor: default;
		}
		.icon-link {
			text-decoration: none;
		}
		.icon-link:hover {
			opacity: 0.7;
			cursor: pointer;
		}
		.coverage-badge {
			padding: 2px 6px;
			border-radius: 4px;
			font-weight: bold;
			color: white;
			font-size: 0.9em;
		}
		.badge-good { background-color: #4CAF50; }
		.badge-warn { background-color: #FFC107; }
		.badge-bad { background-color: #F44336; }
		.summary-row {
			font-weight: bold;
			background-color: #f0f0f0;
		}
		td.positive { color: green; font-weight: bold; }
		td.negative { color: red; font-weight: bold; }
		td.neutral { color: gray; }
	</style>
</head>
<body>
<div class="badges">
	<a href="https://github.com/nigelhorne/CGI-Info">
		<img src="https://img.shields.io/github/stars/nigelhorne/CGI-Info?style=social" alt="GitHub stars">
	</a>
	<img src="$coverage_badge_url" alt="Coverage badge">
</div>
<h1>CGI::Info</h1><h2>Coverage Report</h2>
<table>
<tr><th>File</th><th>Stmt</th><th>Branch</th><th>Cond</th><th>Sub</th><th>Total</th><th>&Delta;</th></tr>
HTML

# Load previous snapshot for delta comparison
my @history = sort { $a cmp $b } bsd_glob("coverage_history/*.json");
my $prev_data;

if (@history >= 1) {
	my $prev_file = $history[-1];	# Most recent before current
	eval {
		$prev_data = decode_json(read_file($prev_file));
	};
}
my %deltas;
if ($prev_data) {
	for my $file (keys %{$data->{summary}}) {
		next if $file eq 'Total';
		my $curr = $data->{summary}{$file}{total}{percentage} // 0;
		my $prev = $prev_data->{summary}{$file}{total}{percentage} // 0;
		my $delta = sprintf('%.1f', $curr - $prev);
		$deltas{$file} = $delta;
	}
}

my $commit_sha = `git rev-parse HEAD`;
chomp $commit_sha;
my $github_base = "https://github.com/nigelhorne/CGI-Info/blob/$commit_sha/";

# Add rows
my ($total_files, $total_coverage, $low_coverage_count) = (0, 0, 0);

for my $file (sort keys %{$data->{summary}}) {
	next if $file eq 'Total';

	my $info = $data->{summary}{$file};
	my $html_file = $file;
	$html_file =~ s|/|-|g;
	$html_file =~ s|\.pm$|-pm|;
	$html_file =~ s|\.pl$|-pl|;
	$html_file .= '.html';

	my $total = $info->{total}{percentage} // 0;
	$total_files++;
	$total_coverage += $total;
	$low_coverage_count++ if $total < 70;

	my $badge_class = $total >= 90 ? 'badge-good'
					: $total >= 70 ? 'badge-warn'
					: 'badge-bad';

	my $tooltip = $total >= 90 ? 'Excellent coverage'
				 : $total >= 70 ? 'Moderate coverage'
				 : 'Needs improvement';

	my $row_class = $total >= 90 ? 'high'
			: $total >= 70 ? 'med'
			: 'low';

	my $badge_html = sprintf(
		'<span class="coverage-badge %s" title="%s">%.1f%%</span>',
		$badge_class, $tooltip, $total
	);

my $delta_html = '';
if (exists $deltas{$file}) {
	my $delta = $deltas{$file};
	my $delta_class = $delta > 0 ? 'positive' : $delta < 0 ? 'negative' : 'neutral';
	my $delta_icon = $delta > 0 ? '&#9650;' : $delta < 0 ? '&#9660;' : '&#9679;';
	my $prev_pct = $prev_data->{summary}{$file}{total}{percentage} // 0;

	$delta_html = sprintf(
		'<td class="%s" title="Previous: %.1f%%">%s %.1f%%</td>',
		$delta_class, $prev_pct, $delta_icon, abs($delta)
	);
} else {
	$delta_html = '<td class="neutral" title="No previous data">&#9679;</td>';
}

	my $source_url = $github_base . $file;
	my $has_coverage = (
		defined $info->{statement}{percentage} ||
		defined $info->{branch}{percentage} ||
		defined $info->{condition}{percentage} ||
		defined $info->{subroutine}{percentage}
	);

	my $source_link = $has_coverage
		? sprintf('<a href="%s" class="icon-link" title="View source on GitHub">&#128269;</a>', $source_url)
		: '<span class="disabled-icon" title="No coverage data">&#128269;</span>';

	$html .= sprintf(
		qq{<tr class="%s"><td><a href="%s" title="View coverage line by line">%s</a> %s</td><td>%.1f</td><td>%.1f</td><td>%.1f</td><td>%.1f</td><td>%s</td>%s</tr>\n},
		$row_class, $html_file, $file, $source_link,
		$info->{statement}{percentage} // 0,
		$info->{branch}{percentage} // 0,
		$info->{condition}{percentage} // 0,
		$info->{subroutine}{percentage} // 0,
		$badge_html,
		$delta_html
	);
}

# Summary row
my $avg_coverage = $total_files ? int($total_coverage / $total_files) : 0;

$html .= sprintf(
	qq{<tr class="summary-row"><td colspan="2"><strong>Summary</strong></td><td colspan="2">%d files</td><td colspan="3">Avg: %d%%, Low: %d</td></tr>\n},
	$total_files, $avg_coverage, $low_coverage_count
);

# Add totals row
if (my $total_info = $data->{summary}{Total}) {
	my $total_pct = $total_info->{total}{percentage} // 0;
	my $class = $total_pct > 80 ? 'high' : $total_pct > 50 ? 'med' : 'low';

	$html .= sprintf(
		qq{<tr class="%s"><td><strong>Total</strong></td><td>%.1f</td><td>%.1f</td><td>%.1f</td><td>%.1f</td><td colspan="2"><strong>%.1f</strong></td></tr>\n},
		$class,
		$total_info->{statement}{percentage} // 0,
		$total_info->{branch}{percentage} // 0,
		$total_info->{condition}{percentage} // 0,
		$total_info->{subroutine}{percentage} // 0,
		$total_pct
	);
}

my $timestamp = 'Unknown';
if (my $stat = stat($cover_db)) {
	$timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime($stat->mtime));
}

my $commit_url = "https://github.com/nigelhorne/CGI-Info/commit/$commit_sha";
my $short_sha = substr($commit_sha, 0, 7);

$html .= <<"HTML";
</table>
HTML

# Parse historical snapshots
my @history_files = bsd_glob("coverage_history/*.json");
my @trend_points;

foreach my $file (sort @history_files) {
	my $json = eval { decode_json(read_file($file)) };
	next unless $json && $json->{summary}{Total};

	my $pct = $json->{summary}{Total}{total}{percentage} // 0;
	my ($date) = $file =~ /(\d{4}-\d{2}-\d{2})/;
	push @trend_points, { date => $date, coverage => sprintf('%.1f', $pct) };
}

# Inject chart if we have data
# if (@trend_points >= 2) {
if(0) {
	my $labels = join(',', map { qq{"$_->{date}"} } @trend_points);
	my $values = join(',', map { $_->{coverage} } @trend_points);

	$html .= <<"HTML";

<h2>Coverage Trend</h2>
<canvas id="coverageTrend" width="600" height="300"></canvas>
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<script>
const ctx = document.getElementById('coverageTrend').getContext('2d');
const chart = new Chart(ctx, {
	type: 'line',
	data: {
		labels: [$labels],
		datasets: [{
			label: 'Total Coverage (%)',
			data: [$values],
			borderColor: 'green',
			backgroundColor: 'rgba(0,128,0,0.1)',
			fill: true,
			tension: 0.3,
			pointRadius: 3
		}]
	}, options: {
		scales: {
			y: {
				beginAtZero: true,
				max: 100
			}
		}
	}
});
</script>
HTML
}

my %commit_times;
open(my $log, '-|', 'git log --all --pretty=format:"%H %h %ci"') or die "Can't run git log: $!";
while (<$log>) {
	chomp;
	my ($full_sha, $short_sha, $datetime) = split ' ', $_, 3;
	$commit_times{$short_sha} = $datetime;
}

my @data_points;
foreach my $file (sort @history_files) {
	my $json = eval { decode_json(read_file($file)) };
	next unless $json && $json->{summary}{Total};

	my ($sha) = $file =~ /-(\w{7})\.json$/;

	my $timestamp = $commit_times{$sha};
	unless ($timestamp) {
		warn "SHA $sha not found in git log — using file mtime";
		$timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime((stat($file))->mtime));
	}
	# Original format: "2025-08-30 09:26:58 -0400"
	$timestamp =~ s/^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}) ([+-]\d{4})$/$1T$2$3/;
	$timestamp =~ s/([+-]\d{2})(\d{2})$/$1:$2/;

	my $pct = $json->{summary}{Total}{total}{percentage} // 0;
	# my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime((stat($file))->mtime));
	# my $timestamp = `git show -s --format=%ci $sha`;
	# chomp $timestamp;
	$timestamp =~ s/ /T/;	# Optional: convert to ISO format

	my $url = "https://github.com/nigelhorne/CGI-Info/commit/$sha";

	push @data_points, qq{{ x: "$timestamp", y: $pct, url: "$url", label: "$timestamp" }};

	print "$sha => $timestamp => $pct\n";
}

my $js_data = join(",\n", @data_points);

$html .= <<"HTML";
	<canvas id="coverageTrend" width="600" height="300"></canvas>
	<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
	<script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns"></script>
	<script>
	const dataPoints = [
	$js_data
	];
HTML

$html .= <<'HTML';
const ctx = document.getElementById('coverageTrend').getContext('2d');
const chart = new Chart(ctx, {
  type: 'line',
  data: {
    datasets: [{
      label: 'Total Coverage (%)',
      data: dataPoints,
      borderColor: 'green',
      backgroundColor: 'rgba(0,128,0,0.1)',
      pointRadius: 5,
      pointHoverRadius: 7,
      pointStyle: 'circle',
      fill: false,
      tension: 0.3
    }]
  },
  options: {
scales: {
  x: {
    type: 'time',
time: {
  tooltipFormat: 'MMM d, yyyy HH:mm:ss',
  unit: 'minute'
},
    title: { display: true, text: 'Timestamp' }
  },
      y: { beginAtZero: true, max: 100, title: { display: true, text: 'Coverage (%)' } }
    },
    plugins: {
      tooltip: {
        callbacks: {
          label: function(context) {
            return `${context.raw.label}: ${context.raw.y}%`;
          }
        }
      }
    },
    onClick: (e) => {
      const points = chart.getElementsAtEventForMode(e, 'nearest', { intersect: true }, true);
      if (points.length) {
        const url = chart.data.datasets[0].data[points[0].index].url;
        window.open(url, '_blank');
      }
    }
  }
});
</script>
HTML

$html .= <<"HTML";
<footer>
	<p>Project: <a href="https://github.com/nigelhorne/CGI-Info">CGI-Info</a></p>
	<p><em>Last updated: $timestamp - <a href="$commit_url">commit <code>$short_sha</code></a></em></p>
</footer>
</body>
</html>
HTML

# Write to index.html
write_file($output, $html);
