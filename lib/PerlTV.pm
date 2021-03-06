package PerlTV;
use Dancer2;

our $VERSION = '0.01';
use Cwd qw(abs_path);
use Path::Tiny ();
use JSON::Tiny ();
use Data::Dumper qw(Dumper);
use List::Util qw(min);

use PerlTV::Tools qw(read_file);

hook before => sub {
	my $appdir = abs_path config->{appdir};
	my $json = JSON::Tiny->new;
	set channels => $json->decode( Path::Tiny::path("$appdir/channels.json")->slurp_utf8 );
	set tags => $json->decode( Path::Tiny::path("$appdir/tags.json")->slurp_utf8 );
	set modules => $json->decode( Path::Tiny::path("$appdir/modules.json")->slurp_utf8 );
	my $featured = $json->decode( Path::Tiny::path("$appdir/featured.json")->slurp_utf8 );
	set featured => [ sort {$b->{date} cmp $a->{date} }  @$featured ];
	my $data;
	eval {
		$data = $json->decode( Path::Tiny::path("$appdir/videos.json")->slurp_utf8 );
	};
	if ($@) {
		set error => 'Could not load videos.json, have you generated it?';
		warn $@;
	} elsif (defined $data) {
		set data => $data;
	} else {
		set error => $json->error;
		warn $json->error;
	}
};

hook before_template => sub {
	my $t = shift;
	$t->{channels} = setting('channels');
	if (not $t->{title} or request->path eq '/') {
		$t->{title} = 'Perl TV';
	}

	$t->{social} = 1;
	$t->{request} = request;
	my $featured = setting('featured');
	my $end = min(4, @$featured-1);
	$t->{featured} = [ @{$featured}[1 .. $end] ];
	
	return;
};

get '/legal' => sub {
	template 'legal';
};

#	my $error = setting('error');
#	if ($error) {
#		warn $error;
#		return template 'error';
#	}

get '/all' => sub {
	my $data = setting('data');
	template 'list', { videos => $data->{videos} };
};

get '/tag/:tag' => sub {
	my $tags = setting('tags');
	my $tag = params->{tag};
	pass if not $tags->{$tag};
	template 'list', { videos => $tags->{$tag}, tag => $tag };
};

get '/module/:name' => sub {
	my $modules = setting('modules');
	my $name = params->{name};
#die $name;
#die Dumper $modules;
	pass if not $modules->{$name};
	template 'list', { videos => $modules->{$name}, module => $name };
};


get '/' => sub {
	# show the currently featured item
	my $featured = setting('featured');
	_show('index', $featured->[0]{path});
};

get '/v/:path' => sub {
	my $path = params->{path};
	if ($path =~ /^[A-Za-z_-]+$/) {
		return _show('page', $path, {show_tags => 1});
	} else {
		warn "Could not find '$path'";
		return template 'error';
	}
};

get '/daily.atom' => sub {
	my $featured = setting('featured');
	my $appdir = abs_path config->{appdir};

	my $URL = request->base;
	$URL =~ s{/$}{};
	my $title = 'PerlTV daily';
	my $ts = $featured->[0]{date};

	my $xml = '';
	$xml .= qq{<?xml version="1.0" encoding="utf-8"?>\n};
	$xml .= qq{<feed xmlns="http://www.w3.org/2005/Atom">\n};
	$xml .= qq{<link href="$URL/daily.atom" rel="self" />\n};
	$xml .= qq{<title>$title</title>\n};
	$xml .= qq{<id>$URL/</id>\n};
	$xml .= qq{<updated>${ts}Z</updated>\n};
	foreach my $entry (@$featured) {

		my $data = read_file( "$appdir/data/$entry->{path}" );

		$xml .= qq{<entry>\n};

		$xml .= qq{  <title>$data->{title}</title>\n};
		$xml .= qq{  <summary type="html"><![CDATA[$data->{description}]]></summary>\n};
		$xml .= qq{  <updated>$entry->{date}Z</updated>\n};
		my $url = "$URL/v/$entry->{path}";
		$xml .= qq{  <link rel="alternate" type="text/html" href="$url" />};
		$xml .= qq{  <id>$entry->{path}</id>\n};
		$xml .= qq{  <content type="html"><![CDATA[$data->{description}]]></content>\n};
		$xml .= qq{</entry>\n};
	}
	$xml .= qq{</feed>\n};

	content_type 'application/atom+xml';
	return $xml;
};

get '/sitemap.xml' => sub {
	my $data = setting('data');
	my $url = request->base;
	$url =~ s{/$}{};
	content_type 'application/xml';

	my $xml = qq{<?xml version="1.0" encoding="UTF-8"?>\n};
	$xml .= qq{<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n};
	$xml .= qq{  <url>\n};
	$xml .= qq{    <loc>$url/</loc>\n};
	$xml .= qq{  </url>\n};
	foreach my $p (@{ $data->{videos} }) {
		$xml .= qq{  <url>\n};
		$xml .= qq{    <loc>$url/v/$p->{path}</loc>\n};
		#$xml .= qq{    <changefreq>monthly</changefreq>\n};
		#$xml .= qq{    <priority>0.8</priority>\n};
		$xml .= qq{  </url>\n};
	}
	$xml .= qq{</urlset>\n};
	return $xml;
};

sub _show {
	my ($template, $path, $params) = @_;

	$params ||= {};

	my $appdir = abs_path config->{appdir};
	my $data;
	eval {
		$data = read_file( "$appdir/data/$path" );
	};
	if ($@) {
		#warn $@;
		return template 'error';
	}

	$data->{path} = $path;
	template $template, { 
		video => $data,
		title => $data->{title},
		%$params,
	};
};


true;

