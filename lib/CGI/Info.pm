package CGI::Info;

# TODO: When not running as CGI, allow --robot, --tablet, --search and --phone
#	to be given to test those environments
# TODO: remove the expect argument

use warnings;
use strict;
use Carp;
use File::Spec;
use Socket;	# For AF_INET

=head1 NAME

CGI::Info - Information about the CGI environment

=head1 VERSION

Version 0.49

=cut

our $VERSION = '0.49';

=head1 SYNOPSIS

All too often Perl programs have information such as the script's name
hard-coded into their source.
Generally speaking, hard-coding is bad style since it can make programs
difficult to read and it reduces readability and portability.
CGI::Info attempts to remove that.

Furthermore, to aid script debugging, CGI::Info attempts to do sensible
things when you're not running the program in a CGI environment.

    use CGI::Info;
    my $info = CGI::Info->new();
    # ...

=head1 SUBROUTINES/METHODS

=head2 new

Creates a CGI::Info object.

It takes four optional arguments allow, logger, expect and upload_dir,
which are documented in the params() method.

Takes an optional boolean parameter syslog, to log messages to
L<Sys::Syslog>.

Takes optional parameter logger, an object which is used for warnings

Takes optional parameter cache, an object which is used to cache IP lookups.
This cache object is an object that understands get() and set() messages,
such as a L<CHI> object.
=cut

our $stdin_data;	# Class variable storing STDIN in case the class
			# is instantiated more than once

sub new {
	my $proto = shift;

	my $class = ref($proto) || $proto;
	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	return bless {
		# _script_name => undef,
		# _script_path => undef,
		# _site => undef,
		# _cgi_site => undef,
		# _domain => undef,
		# _paramref => undef,
		_allow => $args{allow} ? $args{allow} : undef,
		_expect => $args{expect} ? $args{expect} : undef,
		_upload_dir => $args{upload_dir} ? $args{upload_dir} : undef,
		_logger => $args{logger},
		_syslog => $args{syslog},
		_cache => $args{cache},	# e.g. CHI
	}, $class;
}

=head2 script_name

Returns the name of the CGI script.
This is useful for POSTing, thus avoiding putting hardcoded paths into forms

	use CGI::Info;

	my $info = CGI::Info->new();
	my $script_name = $info->script_name();
	# ...
	print "<form method=\"POST\" action=$script_name name=\"my_form\">\n";

=cut

sub script_name {
	my $self = shift;

	unless($self->{_script_name}) {
		$self->_find_paths();
	}
	return $self->{_script_name};
}

sub _find_paths {
        my $self = shift;

	require File::Basename;
	File::Basename->import();

        if($ENV{'SCRIPT_NAME'}) {
                $self->{_script_name} = File::Basename::basename($ENV{'SCRIPT_NAME'});
        } else {
                $self->{_script_name} = File::Basename::basename($0);
        }
	$self->{_script_name} = $self->_untaint_filename({
		filename => $self->{_script_name}
	});

        if($ENV{'SCRIPT_FILENAME'}) {
                $self->{_script_path} = $ENV{'SCRIPT_FILENAME'};
        } elsif($ENV{'SCRIPT_NAME'} && $ENV{'DOCUMENT_ROOT'}) {
                my $script_name = $ENV{'SCRIPT_NAME'};
                if(substr($script_name, 0, 1) eq '/') {
                        # It's usually the case, e.g. /cgi-bin/foo.pl
                        $script_name = substr($script_name, 1);
                }
                $self->{_script_path} = File::Spec->catfile($ENV{'DOCUMENT_ROOT' }, $script_name);
        } elsif($ENV{'SCRIPT_NAME'} && !$ENV{'DOCUMENT_ROOT'}) {
                if(File::Spec->file_name_is_absolute($ENV{'SCRIPT_NAME'}) &&
                   (-r $ENV{'SCRIPT_NAME'})) {
                        # Called from a command line with a full path
                        $self->{_script_path} = $ENV{'SCRIPT_NAME'};
                } else {
                        require Cwd;
                        Cwd->import;

                        my $script_name = $ENV{'SCRIPT_NAME'};
                        if(substr($script_name, 0, 1) eq '/') {
                                # It's usually the case, e.g. /cgi-bin/foo.pl
                                $script_name = substr($script_name, 1);
                        }

                        $self->{_script_path} = File::Spec->catfile(Cwd::abs_path(), $script_name);
                }
        } else {
                my $script_path = $ENV{'SCRIPT_NAME'} ? $ENV{'SCRIPT_NAME'} : $0;
                if(File::Spec->file_name_is_absolute($script_path)) {
                        # Called from a command line with a full path
                        $self->{_script_path} = $script_path;
                } else {
                        $self->{_script_path} = File::Spec->rel2abs($script_path);
                }
        }

	$self->{_script_path} = $self->_untaint_filename({
		filename => $self->{_script_path}
	});
}

=head2 script_path

Finds the full path name of the script.

	use CGI::Info;

	my $info = CGI::Info->new();
	my $fullname = $info->script_path();
	my @statb = stat($fullname);

	if(@statb) {
		my $mtime = localtime $statb[9];
		print "Last-Modified: $mtime\n";
		# TODO: only for HTTP/1.1 connections
		# $etag = Digest::MD5::md5_hex($html);
		printf "ETag: \"%x\"\n", $statb[9];
	}
=cut

sub script_path {
	my $self = shift;

	unless($self->{_script_path}) {
		$self->_find_paths();
	}
	return $self->{_script_path};
}

=head2 script_dir

Returns the file system directory containing the script.

	use CGI::Info;
	use File::Spec;

	my $info = CGI::Info->new();

	print 'HTML files are normally stored in ' .  $info->script_dir() . '/' . File::Spec->updir() . "\n";

=cut

sub script_dir {
	my $self = shift;

	unless($self->{_script_path}) {
		$self->_find_paths();
	}

	# Don't use File::Spec->splitpath() since that can leave in the trailing
	# slash
	if($^O eq 'MSWin32') {
		if($self->{_script_path} =~ /(.+)\\.+?$/) {
			return $1;
		}
	} else {
		if($self->{_script_path} =~ /(.+)\/.+?$/) {
			return $1;
		}
	}
	return $self->{_script_path};
}

=head2 host_name

Return the host-name of the current web server, according to CGI.
If the name can't be determined from the web server, the system's host-name
is used as a fall back.
This may not be the same as the machine that the CGI script is running on,
some ISPs and other sites run scripts on different machines from those
delivering static content.
There is a good chance that this will be domain_name() prepended with either
'www' or 'cgi'.

	use CGI::Info;

	my $info = CGI::Info->new();
	my $host_name = $info->host_name();
	my $protocol = $info->protocol();
	# ...
	print "Thank you for visiting our <A HREF=\"$protocol://$host_name\">Website!</A>";

=cut

sub host_name {
	my $self = shift;

	unless($self->{_site}) {
		$self->_find_site_details();
	}

	return $self->{_site};
}

sub _find_site_details {
	my $self = shift;

	if($self->{_site} && $self->{_cgi_site}) {
		return;
	}

	require URI::Heuristic;
	URI::Heuristic->import;

	if($ENV{'HTTP_HOST'}) {
		$self->{_cgi_site} = URI::Heuristic::uf_uristr($ENV{'HTTP_HOST'});
		# Remove trailing dots from the name.  They are legal in URLs
		# and some sites link using them to avoid spoofing (nice)
		if($self->{_cgi_site} =~ /(.*)\.+$/) {
			$self->{_cgi_site} = $1;
		}

	} elsif($ENV{'SERVER_NAME'}) {
		$self->{_cgi_site} = URI::Heuristic::uf_uristr($ENV{'SERVER_NAME'});
	} else {
		require Sys::Hostname;
		Sys::Hostname->import;

		$self->{_cgi_site} = Sys::Hostname->hostname;
	}

	unless($self->{_site}) {
		$self->{_site} = $self->{_cgi_site};
	}
	if($self->{_site} =~ /^http:\/\/(.+)/) {
		$self->{_site} = $1;
	}
	unless($self->{_cgi_site} =~ /^https?:\/\//) {
		my $protocol = $self->protocol();

		unless($protocol) {
			$protocol = 'http';
		}
		$self->{_cgi_site} = "$protocol://" . $self->{_cgi_site};
	}
	unless($self->{_site} && $self->{_cgi_site}) {
		$self->_warn({
			warning => 'Could not determine site name'
		});
	}
}

=head2 domain_name

Domain_name is the name of the controlling domain for this website.
Usually it will be similar to host_name, but will lack the http:// prefix.

=cut

sub domain_name {
	my $self = shift;

	if($self->{_domain}) {
		return $self->{_domain};
	}
	$self->_find_site_details();

	if($self->{_site}) {
		$self->{_domain} = $self->{_site};
		if($self->{_domain} =~ /^www\.(.+)/) {
			$self->{_domain} = $1;
		}
	}

	return $self->{_domain};
}

=head2 cgi_host_url

Return the URL of the machine running the CGI script.

=cut

sub cgi_host_url {
	my $self = shift;

	unless($self->{_cgi_site}) {
		$self->_find_site_details();
	}

	return $self->{_cgi_site};
}

=head2 params

Returns a reference to a hash list of the CGI arguments.

CGI::Info helps you to test your script prior to deployment on a website:
if it is not in a CGI environment (e.g. the script is being tested from the
command line), the program's command line arguments (a list of key=value pairs)
are used, if there are no command line arguments then they are read from stdin
as a list of key=value lines.

Returns undef if the parameters can't be determined.

If an argument is given twice or more, then the values are put in a comma
separated string.

The returned hash value can be passed into L<CGI::Untaint>.

Takes four optional parameters: allow, expect, logger and upload_dir.
The parameters are passed in a hash, or a reference to a hash.
The latter is more efficient since it puts less on the stack.

Allow is a reference to a hash list of CGI parameters that you will allow.
The value for each entry is a regular expression of permitted values for
the key.
A undef value means that any value will be allowed.
Arguments not in the list are silently ignored.
This is useful to help to block attacks on your site.

Expect is a reference to a list of arguments that you expect to see and pass on.
Arguments not in the list are silently ignored.
This is useful to help to block attacks on your site.
It's use is deprecated, use allow instead.
Expect will be removed in a later version.

Upload_dir is a string containing a directory where files being uploaded are to
be stored.

Takes optional parameter logger, an object which is used for warnings and
traces.
This logger object is an object that understands warn() and trace() messages,
such as a L<Log::Log4perl> object.

The allow, expect, logger and upload_dir arguments can also be passed to the
constructor.

	use CGI::Info;
	use CGI::Untaint;
	# ...
	my $info = CGI::Info->new();
	my %params;
	if($info->params()) {
		%params = %{$info->params()};
	}
	# ...
	foreach(keys %params) {
		print "$_ => $params{$_}\n";
	}
	my $u = CGI::Untaint->new(%params);

	use CGI::Info;
	use CGI::IDS;
	# ...
	my $info = CGI::Info->new();
	my $allowed = {
		'foo' => qr(\d+),
		'bar' => undef
	};
	my $paramsref = $info->params(allow => $allowed);
	# or
	my @expected = ('foo', 'bar');
	my $paramsref = $info->params({
		expect => \@expected,
		upload_dir = $info->tmpdir()
	});
	if(defined($paramsref)) {
		my $ids = CGI::IDS->new();
		$ids->set_scan_keys(scan_keys => 1);
		if($ids->detect_attacks(request => $paramsref) > 0) {
			die 'horribly';
		}
	}

If the request is an XML request, CGI::Info will put the request into
the params element 'XML', thus:

	use CGI::Info;
	...
	my $info = CGI::Info->new();
	my $paramsref = $info->params();
	my $xml = $$paramsref{'XML'};
	# ... parse and process the XML request in $xml

=cut

sub params {
	my $self = shift;

	if(defined($self->{_paramref})) {
		return $self->{_paramref};
	}

	my %args = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	if(defined($args{allow})) {
		$self->{_allow} = $args{allow};
	}
	if(defined($args{expect})) {
		$self->{_expect} = $args{expect};
	}
	if(defined($args{upload_dir})) {
		$self->{_upload_dir} = $args{upload_dir};
	}
	if(defined($args{logger})) {
		$self->{_logger} = $args{logger};
	}

	my @pairs;
	my $content_type = $ENV{'CONTENT_TYPE'};
	my %FORM;

	if((!$ENV{'GATEWAY_INTERFACE'}) || (!$ENV{'REQUEST_METHOD'})) {
		if(@ARGV) {
			@pairs = @ARGV;
		} elsif($stdin_data) {
			@pairs = split(/\n/, $stdin_data);
		} elsif(!$self->{_args_read}) {
			my $oldfh = select(STDOUT);
			print "Entering debug mode\n";
			print "Enter key=value pairs - end with quit\n";
			select($oldfh);

			while(<STDIN>) {
				chop(my $line = $_);
				$line =~ s/[\r\n]//g;
				last if $line eq 'quit';
				push(@pairs, $line);
				$stdin_data .= $line . "\n";
			}
			# Avoid prompting for the arguments more than once
			# if just 'quit' is entered
			$self->{_args_read} = 1;
		}
	} elsif(($ENV{'REQUEST_METHOD'} eq 'GET') || ($ENV{'REQUEST_METHOD'} eq 'HEAD')) {
		unless($ENV{'QUERY_STRING'}) {
			return;
		}
		if((defined($content_type)) && ($content_type =~ /multipart\/form-data/i)) {
			$self->_warn({
				warning => 'Multipart/formdata not supported for GET'
			});
		}
		@pairs = split(/&/, $ENV{'QUERY_STRING'});
	} elsif($ENV{'REQUEST_METHOD'} eq 'POST') {
		if(!defined($ENV{'CONTENT_LENGTH'})) {
			return;
		}
		my $content_length = $ENV{'CONTENT_LENGTH'};

		if((!defined($content_type)) || ($content_type =~ /application\/x-www-form-urlencoded/)) {
			my $buffer;
			if($stdin_data) {
				$buffer = $stdin_data;
			} else {
				if(read(STDIN, $buffer, $content_length) != $content_length) {
					croak 'POST failed: something else may have read STDIN';
				}
				$stdin_data = $buffer;
			}
			@pairs = split(/&/, $buffer);

			if($ENV{'QUERY_STRING'}) {
				my @getpairs = split(/&/, $ENV{'QUERY_STRING'});
				push(@pairs, @getpairs);
			}
		} elsif($content_type =~ /multipart\/form-data/i) {
			if(!defined($self->{_upload_dir})) {
				croak 'Attempt to upload a file when upload_dir has not been set';
			}
			if(!File::Spec->file_name_is_absolute($self->{_upload_dir})) {
				croak '_upload_dir must be a full pathname';
			}
			if(!-d $self->{_upload_dir}) {
				croak '_upload_dir isn\'t a directory';
			}
			if(!-w $self->{_upload_dir}) {
				delete $self->{_paramref};
				croak '_upload_dir isn\'t writeable';
			}
			if($content_type =~ /boundary=(\S+)$/) {
				@pairs = $self->_multipart_data({
					length => $content_length,
					boundary => $1
				});
			}
		} elsif($content_type =~ /text\/xml/i) {
			my $buffer;
			if($stdin_data) {
				$buffer = $stdin_data;
			} else {
				read(STDIN, $buffer, $content_length);
				$stdin_data = $buffer;
			}

			$FORM{XML} = $buffer;

			$self->{_paramref} = \%FORM;

			return \%FORM;
		} else {
			$self->_warn({
				warning => "POST: Invalid or unsupported content type: $content_type",
			});
		}
	} elsif($ENV{'REQUEST_METHOD'} eq 'OPTIONS') {
		return;
	} else {
		$self->_warn({
			warning => 'Use POST, GET or HEAD'
		});
	}

	# Can go when expect has been removed
	if($self->{_expect}) {
		require List::Member;
		List::Member->import();
	}
	require String::Clean::XSS;
	require String::EscapeCage;
	String::Clean::XSS->import();
	String::EscapeCage->import();

	foreach(@pairs) {
		my($key, $value) = split(/=/, $_);

		next unless($key);

		$key =~ tr/+/ /;
		$key =~ s/%([a-fA-F\d][a-fA-F\d])/pack("C", hex($1))/eg;
		unless($value) {
			$value = '';
		}
		$value =~ tr/+/ /;
		$value =~ s/%([a-fA-F\d][a-fA-F\d])/pack("C", hex($1))/eg;

		$key = $self->_sanitise_input($key);

		if($self->{_allow}) {
			# Is this a permitted argument?
			if(!exists($self->{_allow}->{$key})) {
				next;
			}

			# Do we allow any value, or must it be validated?
			if(defined($self->{_allow}->{$key})) {
				if($value !~ $self->{_allow}->{$key}) {
					next;
				}
			}
		}

		if($self->{_expect} && (member($key, @{$self->{_expect}}) == nota_member())) {
			next;
		}
		$value = $self->_sanitise_input($value);

		if(length($value) > 0) {
			if($FORM{$key}) {
				$FORM{$key} .= ",$value";
			} else {
				$FORM{$key} = $value;
			}
		}
	}

	$self->{_paramref} = \%FORM;

	if($self->{_logger}) {
		while(my ($key,$value) = each %FORM) {
			$self->{_logger}->debug("$key=$value");
		}
	}
	return \%FORM;
}

=head2 param

Get a single parameter.
Takes an optional single string parameter which is the argument to return. If
that parameter is given param() is a wrapper to params() with no arguments.

	use CGI::Info;
	# ...
	my $info = CGI::Info->new();
	my $bar = $info->param('foo');

If the requested parameter isn't in the allowed list, an error message will
be thrown:

	use CGI::Info;
	my $allowed = {
		'foo' => qr(\d+),
	};
	my $bar = $info->param('bar');  # Gives an error message

=cut

sub param {
	my ($self, $field) = @_;

	my $params = $self->params();
	if(!defined($field)) {
		return $params;
	}
	# Is this a permitted argument?
	if($self->{_allow} && (!exists($self->{_allow}->{$field}))) {
		$self->_warn({
			warning => "param: $field isn't in the allow list"
		});
		return;
	}

	if(!defined($params)) {
		return;
	}

	return $params->{$field};
}

# Emit a warning message somewhere
sub _warn {
	my ($self, $params) = @_;

	my $warning = $$params{'warning'};

	return unless($warning);

	if($self->{_syslog}) {
		require Sys::Syslog;

		Sys::Syslog->import();
		openlog($self->script_name(), 'cons,pid', 'user');
		syslog('warning', $warning);
		closelog();
	}

	if($self->{_logger}) {
		$self->{_logger}->warn($warning);
	} elsif(!defined($self->{_syslog})) {
		carp($warning);
	}
}

sub _sanitise_input {
	my $self = shift;
	my $arg = shift;

	# Remove hacking attempts and spaces
	$arg =~ s/[\r\n]//g;
	$arg =~ s/\s+$//;
	$arg =~ s/^\s//;

	$arg =~ s/<!--.*-->//g;
	# Allow :
	# $arg =~ s/[;<>\*|`&\$!?#\(\)\[\]\{\}'"\\\r]//g;

	# return $arg;
	return String::EscapeCage->new(convert_XSS($arg))->escapecstring();
}

sub _multipart_data {
	my ($self, $args) = @_;

	my $total_bytes = $$args{length};

	if($total_bytes == 0) {
		return;
	}

	my $boundary = $$args{boundary};

	my @pairs;
	my $writing_file = 0;
	my $key;
	my $value;
	my $in_header = 0;
	my $fout;

	unless($stdin_data) {
		while(<STDIN>) {
			chop(my $line = $_);
			$line =~ s/[\r\n]//g;
			$stdin_data .= $line . "\n";
		}
	}
	foreach my $line(split(/\n/, $stdin_data)) {
		if($line =~ /^--\Q$boundary\E--$/) {
			last;
		}
		if($line =~ /^--\Q$boundary\E$/) {
			if($writing_file) {
				close $fout;
				$writing_file = 0;
			} elsif(defined($key)) {
				push(@pairs, "$key=$value");
				$value = undef;
			}
			$in_header = 1;
		} elsif($in_header) {
			if(length($line) == 0) {
				$in_header = 0;
			} elsif($line =~ /^Content-Disposition: (.+)/i) {
				my $field = $1;
				if($field =~ /name="(.+?)"/) {
					$key = $1;
				}
				if($field =~ /filename="(.+)?"/) {
					my $filename = $1;
					unless(defined($filename)) {
						$self->_warn({
							warning => 'No upload filename given'
						});
					} elsif($filename =~ /[\\\/\|]/) {
						$self->_warn({
							warning => "Disallowing invalid filename: $filename"
						});
					} else {
						$filename = $self->_create_file_name({
							filename => $filename
						});

						my $full_path = File::Spec->catfile($self->{_upload_dir}, $filename);
						unless(open($fout, '>', $full_path)) {
							$self->_warn({
								warning => "Can't open $full_path"
							});
						}
						$writing_file = 1;
						push(@pairs, "$key=$filename");
					}
				}
			}
			# TODO: handle Content-Type: text/plain, etc.
		} else {
			if($writing_file) {
				print $fout "$line\n";
			} else {
				$value .= $line;
			}
		}
	}

	if($writing_file) {
		close $fout;
	}

	return @pairs;
}

sub _create_file_name
{
	my ($self, $args) = @_;

	return $$args{filename} . '_' . time;
}

# Untaint a filename. Regex from CGI::Untaint::Filenames
sub _untaint_filename
{
	my ($self, $args) = @_;

	my $filename = $$args{filename};
	if($filename =~ /(^[\w\+_\040\#\(\)\{\}\[\]\/\-\^,\.:;&%@\\~]+\$?$)/) {
		return $1;
	}
	# return undef;
}

=head2 is_mobile

Returns a boolean if the website is being viewed on a mobile
device such as a smart-phone.
All tablets are mobile, but not all mobile devices are tablets.

=cut

sub is_mobile {
        my $self = shift;

	if($self->is_tablet()) {
		return 1;
	}

	if($ENV{'HTTP_X_WAP_PROFILE'}) {
		# E.g. Blackberry
		# TODO: Check the sanity of this variable
		return 1;
	}

	if($ENV{'HTTP_USER_AGENT'}) {
		my $agent = $ENV{'HTTP_USER_AGENT'};
		# if($agent =~ /.+iPhone.+/) {
			# return 1;
		# }
		# if($agent =~ /.+Android.+/) {
			# return 1;
		# }
		if($agent =~ /(?^:.+(?:Android|iPhone).+)/) {
			return 1;
		}

		my $remote = $ENV{'REMOTE_ADDR'};
		if(defined($remote) && $self->{_cache}) {
			my $is_mobile = $self->{_cache}->get("is_mobile/$remote/$agent");
			if(defined($is_mobile)) {
				return $is_mobile;
			}
		}

		unless($self->{_browser_detect}) {
			if(eval { require HTTP::BrowserDetect; }) {
				HTTP::BrowserDetect->import();
				$self->{_browser_detect} = HTTP::BrowserDetect->new($agent);
			}
		}
		if($self->{_browser_detect}) {
			my $device = $self->{_browser_detect}->device();
			my $is_mobile = (defined($device) && ($device =~ /blackberry|webos|iphone|ipod|ipad|android/i));
			if($self->{_cache}) {
				$self->{_cache}->set("is_mobile/$remote/$agent", $is_mobile, '1 day');
			}
			return $is_mobile;
		}
	}

	return 0;
}

=head2 is_tablet

Returns a boolean if the website is being viewed on a tablet such as an iPad.

=cut

sub is_tablet {
        if($ENV{'HTTP_USER_AGENT'} && ($ENV{'HTTP_USER_AGENT'} =~ /.+(iPad|TabletPC).+/)) {
		# TODO: add others when I see some nice user_agents
		return 1;
        }

        return 0;
}

=head2 as_string

Returns the parameters as a string, which is useful for debugging or
generating keys for a cache.

=cut

sub as_string {
	my $self = shift;

	unless($self->params()) {
		return '';
	}

	my %f = %{$self->params()};

	my $rc;

	foreach (sort keys %f) {
		my $value = $f{$_};
		$value =~ s/\\/\\\\/g;
		$value =~ s/(;|=)/\\$1/g;
		if(defined($rc)) {
			$rc .= ";$_=$value";
		} else {
			$rc = "$_=$value";
		}
	}

	return defined($rc) ? $rc : '';
}

=head2 protocol

Returns the connection protocol, presumably 'http' or 'https', or undef if
it can't be determined.

This can be run as a class or object method.

=cut

sub protocol {
	if($ENV{'SCRIPT_URI'} && ($ENV{'SCRIPT_URI'} =~ /^(.+):\/\/.+/)) {
		return $1;
	}

	my $port = $ENV{'SERVER_PORT'};
	if(defined($port)) {
		if($port == 80) {
			return 'http';
		} elsif($port == 443) {
			return 'https';
		}
	}

	if($ENV{'SERVER_PROTOCOL'} && ($ENV{'SERVER_PROTOCOL'} =~ /^HTTP\//)) {
		return 'http';
	}
	return;
}

=head2 tmpdir

Returns the name of a directory that you can use to create temporary files
in.

The routine is preferable to L<File::Spec/tmpdir> since CGI programs are
often running on shared servers.  Having said that, tmpdir will fall back
to File::Spec->tmpdir() if it can't find somewhere better.

If the parameter 'default' is given, then use that directory as a
fall-back rather than the value in File::Spec->tmpdir().
No sanity tests are done, so if you give the default value of
'/non-existant', that will be returned.

Tmpdir allows a reference of the options to be passed.

	use CGI::Info;

	my $info = CGI::Info->new();
	my $dir = $info->tmpdir(default => '/var/tmp');
	my $dir = $info->tmpdir({ default => '/var/tmp' });

	# or

	my $dir = CGI::Info->tmpdir();
=cut

sub tmpdir {
	my $self = shift;
	my %params = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	my $name = 'tmp';
	if($^O eq 'MSWin32') {
		$name = 'temp';
	}

	my $dir;

	if($ENV{'C_DOCUMENT_ROOT'} && (-d $ENV{'C_DOCUMENT_ROOT'})) {
		$dir = "$ENV{'C_DOCUMENT_ROOT'}/$name";
		if((-d $dir) && (-w $dir)) {
			return $self->_untaint_filename({ filename => $dir });
		}
		$dir = $ENV{'C_DOCUMENT_ROOT'};
		if((-d $dir) && (-w $dir)) {
			return $self->_untaint_filename({ filename => $dir });
		}
	}
	if($ENV{'DOCUMENT_ROOT'} && (-d $ENV{'DOCUMENT_ROOT'})) {
		$dir = File::Spec->catdir($ENV{'DOCUMENT_ROOT'}, File::Spec->updir(), $name);
		if((-d $dir) && (-w $dir)) {
			return $self->_untaint_filename({ filename => $dir });
		}
	}
	return $params{default} ? $params{default} : File::Spec->tmpdir();
}

=head2 rootdir

Returns the document root.  This is preferable to looking at DOCUMENT_ROOT
in the environment because it will also work when we're not running as a CGI
script, which is useful for script debugging.

This can be run as a class or object method.

	use CGI::Info;

	print CGI::Info->rootdir();

=cut

sub rootdir {
	if($ENV{'C_DOCUMENT_ROOT'} && (-d $ENV{'C_DOCUMENT_ROOT'})) {
		return $ENV{'C_DOCUMENT_ROOT'};
	} elsif($ENV{'DOCUMENT_ROOT'} && (-d $ENV{'DOCUMENT_ROOT'})) {
		return $ENV{'DOCUMENT_ROOT'};
	}
	my $script_name = $0;

	unless(File::Spec->file_name_is_absolute($script_name)) {
		$script_name = File::Spec->rel2abs($script_name);
	}
	if($script_name =~ /.cgi\-bin.*/) {	# kludge for outside CGI environment
		$script_name =~ s/.cgi\-bin.*//;
	}
	if(-f $script_name) {	# More kludge
		if($^O eq 'MSWin32') {
			if($script_name =~ /(.+)\\.+?$/) {
				return $1;
			}
		} else {
			if($script_name =~ /(.+)\/.+?$/) {
				return $1;
			}
		}
	}
	return $script_name;
}

=head2 is_robot

Is the visitor a real person or a robot?

	use CGI::Info;

	my $info = CGI::Info->new();
	unless($info->is_robot()) {
	  # update site visitor statistics
	}

=cut

sub is_robot {
	my $self = shift;

	unless($ENV{'REMOTE_ADDR'} && $ENV{'HTTP_USER_AGENT'}) {
		# Probably not running in CGI - assume real person
		return 0;
	}

	if(defined($self->{_is_robot})) {
		return $self->{_is_robot};
	}

	my $remote = $ENV{'REMOTE_ADDR'};
	my $agent = $ENV{'HTTP_USER_AGENT'};
	if($agent =~ /.+bot|msnptc|is_archiver|backstreet|spider|scoutjet|gingersoftware|heritrix|dodnetdotcom|yandex|nutch|ezooms|plukkie/i) {
		return 1;
	}

	if($self->{_cache}) {
		my $is_robot = $self->{_cache}->get("is_robot/$remote/$agent");
		if(defined($is_robot)) {
			$self->{_is_robot} = $is_robot;
			return $is_robot;
		}
	}

	# TODO: DNS lookup, not gethostbyaddr - though that will be slow
	my $hostname = gethostbyaddr(inet_aton($remote), AF_INET) || $remote;
	if($hostname =~ /google|msnbot|bingbot/) {
		if($self->{_cache}) {
			$self->{_cache}->set("is_robot/$remote/$agent", 1, '1 day');
		}
		$self->{_is_robot} = 1;
		return 1;
	}

	unless($self->{_browser_detect}) {
		if(eval { require HTTP::BrowserDetect; }) {
			HTTP::BrowserDetect->import();
			$self->{_browser_detect} = HTTP::BrowserDetect->new($agent);
		}
	}
	if($self->{_browser_detect}) {
		my $is_robot = $self->{_browser_detect}->robot();
		if($self->{_cache}) {
			$self->{_cache}->set("is_robot/$remote/$agent", $is_robot, '1 day');
		}
		$self->{_is_robot} = $is_robot;
		return $is_robot;
	}

	if($self->{_cache}) {
		$self->{_cache}->set("is_robot/$remote/$agent", 0, '1 day');
	}
	$self->{_is_robot} = 0;
	return 0;
}

=head2 is_search_engine

Is the visitor a search engine?

	use CGI::Info;

	my $info = CGI::Info->new();
	if($info->is_search_engine()) {
	  # display generic information about yourself
	} else {
	  # allow the user to pick and choose something to display
	}

=cut

sub is_search_engine {
	my $self = shift;

	unless($ENV{'REMOTE_ADDR'} && $ENV{'HTTP_USER_AGENT'}) {
		# Probably not running in CGI - assume not a search engine
		return 0;
	}

	my $remote = $ENV{'REMOTE_ADDR'};
	my $agent = $ENV{'HTTP_USER_AGENT'};

	if(defined($self->{_is_search_engine})) {
		return $self->{_is_search_engine};
	}

	if($self->{_cache}) {
		my $is_search = $self->{_cache}->get("is_search/$remote/$agent");
		if(defined($is_search)) {
			$self->{_is_search_engine} = $is_search;
			return $is_search;
		}
	}

	# Don't use HTTP_USER_AGENT to detect more than we really have to since
	# that is easily spoofed
	if($agent =~ /www\.majestic12\.co\.uk/) {
		if($self->{_cache}) {
			$self->{_cache}->set("is_search/$remote/$agent", 1, '1 day');
		}
		return 1;
	}

	# TODO: DNS lookup, not gethostbyaddr - though that will be slow
	my $hostname = gethostbyaddr(inet_aton($remote), AF_INET) || $remote;
	if($hostname =~ /google\.|msnbot/) {
		if($self->{_cache}) {
			$self->{_cache}->set("is_search/$remote/$agent", 1, '1 day');
		}
		$self->{_is_search_engine} = 1;
		return 1;
	}
	unless($self->{_browser_detect}) {
		if(eval { require HTTP::BrowserDetect; }) {
			HTTP::BrowserDetect->import();
			$self->{_browser_detect} = HTTP::BrowserDetect->new($agent);
		}
	}
	if($self->{_browser_detect}) {
		my $browser = $self->{_browser_detect};
		my $is_search = ($browser->google() || $browser->msn() || $browser->baidu() || $browser->altavista() || $browser->yahoo());
		if($self->{_cache}) {
			$self->{_cache}->set("is_search/$remote/$agent", $is_search, '1 day');
		}
		$self->{_is_search_engine} = $is_search;
		return $is_search;
	}

	if($self->{_cache}) {
		$self->{_cache}->set("is_search/$remote/$agent", 0, '1 day');
	}
	$self->{_is_search_engine} = 0;
	return 0;
}

=head2 browser_type

Returns one of 'web', 'robot' and 'mobile'.

    # Code to display a different web page for a browser, search engine and
    # smartphone
    use Template;
    use CGI::Info;

    my $info = CGI::Info->new();
    my $dir = $info->rootdir() . '/templates/' . $info->browser_type();

    my $filename = ref($self);
    $filename =~ s/::/\//g;
    $filename = "$dir/$filename.tmpl";

    if((!-f $filename) || (!-r $filename)) {
	die "Can't open $filename";
    }
    $template->process($filename, {}) || die $template->error();

=cut

sub browser_type {
	my $self = shift;

	if($self->is_mobile()) {
		return 'mobile';
	}
	if($self->is_search_engine() || $self->is_robot()) {
		return 'robot';
	}
	return 'web';
}

=head2 get_cookie

Returns a cookie's value, or undef if no name is given, or the requested
cookie isn't in the jar.

	use CGI::Info;

	my $info = CGI::Info->new();
	my $name = $info->get_cookie(cookie_name => 'name');
	print "Your name is $name\n";
=cut

sub get_cookie {
	my $self = shift;
	my %params = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;

	if(!defined($params{'cookie_name'})) {
		$self->_warn({
			warning => 'cookie_name argument not given'
		});
		return;
	}

	my $jar = $self->{_jar};

	unless($jar) {
		unless(defined($ENV{'HTTP_COOKIE'})) {
			return;
		}
		my @cookies = split(/; /, $ENV{'HTTP_COOKIE'});

		foreach my $cookie(@cookies) {
			my ($name, $value) = split(/=/, $cookie);
			$jar->{$name} = $value;
		}
	}

	if(exists($jar->{$params{'cookie_name'}})) {
		return $jar->{$params{'cookie_name'}};
	}
	return;	# Return undef
}

=head2 reset

Class method to reset the class.
You should never call this.

=cut

sub reset {
	my $class = shift;

	unless($class eq __PACKAGE__) {
		carp 'Reset is a class method';
		return;
	}

	$stdin_data = undef;
}

=head1 AUTHOR

Nigel Horne, C<< <njh at bandsman.co.uk> >>

=head1 BUGS

is_tablet() only currently detects the iPad and Windows PCs. Android strings
don't differ between tablets and smart-phones.

Please report any bugs or feature requests to C<bug-cgi-info at rt.cpan.org>,
or through the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=CGI-Info>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SEE ALSO

HTTP::BrowserDetect

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc CGI::Info


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=CGI-Info>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/CGI-Info>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/CGI-Info>

=item * Search CPAN

L<http://search.cpan.org/dist/CGI-Info/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2010-2014 Nigel Horne.

This program is released under the following licence: GPL


=cut

1; # End of CGI::Info
