#!/usr/bin/perl

use MIME::Parser;
use Switch;
use HTML::Parser;

my %link_hash;
my $newlink = 1;
sub foundurl {
	my($uri,$orig) = @_;
	$uri =~ s/mailto:(.*)/$1/;
	if (! $link_hash{$uri}) {
		$link_hash{$uri} = $newlink++;
	}
}
sub unfindurl {
	my($uri) = @_;
	delete($link_hash{$uri});
}
sub sanitizeuri {
	my($uri) = @_;
	my %encoding = (
		#"\!" => "%21",
		#"\*" => "%2A",
		"\'" => "%27",
		#"\(" => "%28",
		#"\)" => "%29",
		#"\;" => "%3B",
		#"\:" => "%3A",
		#"\@" => "%40",
		#"\&" => "%26",
		#"\=" => "%3D",
		#"\+" => "%2B",
		"\\\$" => "%24",
		#"\," => "%2C",
		#"\/" => "%2F",
		#"\?" => "%3F",
		#"\%" => "%25",
		#"\#" => "%23",
		#"\[" => "%5B",
		#"\]" => "%5D",
	);
	foreach $dangerchar (keys %encoding) {
		$uri =~ s/$dangerchar/$encoding{$dangerchar}/g;
	}
	return $uri;
}

my $parser = new MIME::Parser;

$parser->output_to_core(1);
$entity = $parser->parse(\*STDIN) or die "parse failed\n";

# create a hash of html tag names that may have links
my %link_attr = (
	'a' => {'href'},
	'applet' => {'archive','codebase','code'},
	'area' => {'href'},
	'blockquote' => {'cite'},
	#'body'    => {'background'},
	'embed'   => {'pluginspage', 'src'},
	'form'    => {'action'},
	'frame'   => {'src', 'longdesc'},
	'iframe'  => {'src', 'longdesc'},
	#'ilayer'  => {'background'},
	#'img' => {'src'},
	'input'   => {'src', 'usemap'},
	'ins'     => {'cite'},
	'isindex' => {'action'},
	'head'    => {'profile'},
	#'layer'   => {'background', 'src'},
	'layer'   => {'src'},
	'link'    => {'href'},
	'object'  => {'classid', 'codebase', 'data', 'archive', 'usemap'},
	'q'       => {'cite'},
	'script'  => {'src', 'for'},
	#'table'   => {'background'},
	#'td'      => {'background'},
	#'th'      => {'background'},
	#'tr'      => {'background'},
	'xmp'     => {'href'},
);

sub extract_url_from_text {
	my($text) = @_;
	# The idea here is to eliminate duplicate URLs - I want the
	# %link_hash to be full of URLs. My regex (in the else statement)
	# is decent, but imperfect. URI::Find is better.
	my $fancyfind=1;
	eval "use URI::Find::Schemeless";
	$fancyfind=0 if ($@);
	if ($fancyfind == 1) {
		my $finder = URI::Find::Schemeless->new(\&foundurl);
		$finder->find(\$text);
	} else {
		$text =~ s{(((mms|ftp|http|https)://|news:)[][A-Za-z0-9_.~!*'();:@&=+$,/?%#-]+[^](,.'">;[:space:]]|(mailto:)?[-a-zA-Z_0-9.+]+@[-a-zA-Z_0-9.]+)}{
			&foundurl($1,"");
		}eg;
	}
}

sub find_urls_rec
{
	my($ent) = @_;
	if ($ent->parts > 1) {
		for ($i=0;$i<$ent->parts;$i++) {
			find_urls_rec($ent->parts($i));
		}
	} else {
		#print "type: " . $ent->mime_type . "\n";
		switch ($ent->mime_type) {
			case "text/html" {
				my $parser = HTML::Parser->new(api_version=>3);
				$parser->handler(start => sub {
						my($tagname,$pos,$text) = @_;
						if (my $link_attr = $link_attr{$tagname}) {
							while (4 <= @$pos) {
								my($k_offset, $k_len, $v_offset, $v_len) = splice(@$pos,-4);
								my $attrname = lc(substr($text, $k_offset, $k_len));
								next unless exists($link_attr->{$attrname});
								next unless $v_offset; # 0 v_offset means no value
								my $v = substr($text, $v_offset, $v_len);
								$v =~ s/^([\'\"])(.*)\1$/$2/;
								&foundurl($v,"");
							}
						}
					},
					"tagname, tokenpos, text");
				$parser->parse($ent->bodyhandle->as_string);
			}
			case qr/text\/.*/ {
				$ent->head->unfold;
				switch ($ent->head->get('Content-type')) {
					case qr/format=flowed/ {
						my @lines = $ent->bodyhandle->as_lines;
						chomp(@lines);
						my $body = "";
						if ($ent->head->get('Content-type') =~ /delsp=yes/) {
							#print "delsp=yes!\n";
							$delsp=1;
						} else {
							#print "delsp=no!\n";
							$delsp=0;
						}
						for ($i=0;$i<@lines;$i++) {
							my $col = 0;
							my $quotetext = "";
							while (substr($lines[$i],$col,1) eq ">") {
								$quotetext .= ">";
								$col++;
							}
							if ($col > 0) { $body .= "$quotetext "; }
							while ($lines[$i] =~ / $/ && $lines[$i] =~ /^$quotetext[^>]/ && $lines[$i+1] =~ /^$quotetext[^>]/) {
								if ($delsp) {
									$line = substr($lines[$i],$col,length($lines[$i])-$col-1);
								} else {
									$line = substr($lines[$i],$col);
								}
								$line =~ s/ *(.*)/$1/;
								$body .= $line;
								$i++;
							}
							if ($lines[$i] =~ /^$quotetext[^>]/) {
								$line = substr($lines[$i],$col);
								$line =~ s/ *(.*)/$1/;
								$body .= $line."\n";
							}
						}
						&extract_url_from_text($body);
					}
					else {
						&extract_url_from_text($ent->bodyhandle->as_string);
					}
				}
			}
		}
	}
}

sub urlwrap {
	my($subseq,$text,$linelen,$breaker) = @_;
	my $len = length($text);
	my $i = 0;
	my $output = "";
	if (length($breaker) == 0) { $breaker = "\n"; }
	while ($len > $linelen) {
		if ($i > 0) { $output .= $subseq; }
		my $breakpoint = -1;
		my $chunk = substr($text,$i,$linelen);
		my @chars = ("!","*","'","(",")",";",":","@","&","=","+",",","/","?","%","#","[","]");
		foreach $chr ( @chars ) {
			my $pt = rindex($chunk,$chr);
			if ($breakpoint < $pt) { $breakpoint = $pt; }
		}
		if ($breakpoint == -1) { $breakpoint = $linelen; }
		else { $breakpoint += 1; }
		$output .= substr($text,$i,$breakpoint) . $breaker;
		if ($i == 0) { $linelen -= length($subseq); }
		$len -= $breakpoint;
		$i += $breakpoint;
	}
	if ($i > 0) { $output .= $subseq; }
	$output .= substr($text,$i);
	return $output;
}

&find_urls_rec($entity);

sub isOutputScreen {
	use POSIX;
	return 0 if POSIX::isatty( \*STDOUT) eq "" ; # pipe
	return 1; # screen
} # end of isOutputScreen

my $fancymenu = 1;
if (&isOutputScreen) {
	eval "use Curses::UI";
	$fancymenu = 0 if ($@);
} else {
	$fancymenu = 0;
}

if ($fancymenu == 1) {
	#use strict;
	# Curses support really REALLY wants to own STDIN
	close(STDIN);
	open(STDIN,"/dev/tty"); # looks like a hack, smells like a hack...

	# find out the URLVIEW command
	my $urlviewcommand="";
	my $shortcut = 0; # means open it without checking if theres only 1 URL
	my $noreview = 0; # means don't display overly-long URLs to be checked before opening
	my $persist  = 0; # means don't exit after viewing a URL (ignored if $shortcut == 0)
	if (open(PREFFILE,'<',$ENV{'HOME'}."/.extract_urlview")) {
		while (<PREFFILE>) {
			if (/^SHORTCUT$/) {
				$shortcut = 1;
			} elsif (/^COMMAND (.*)/) {
				$urlviewcommand=$1;
				chomp $urlviewcommand;
			} elsif (/^NOREVIEW$/) {
				$noreview = 1;
			} elsif (/^PERSISTENT$/) {
				$persist = 1;
			}
		}
		close PREFFILE;
	} elsif (open(URLVIEW,'<',$ENV{'HOME'}."/.urlview")) {
		while (<URLVIEW>) {
			if (/^COMMAND (.*)/) {
				$urlviewcommand=$1;
				chomp $urlviewcommand;
				last;
			}
		}
		close URLVIEW;
	}
	if ($urlviewcommand eq "") {
		$urlviewcommand = "open";
	}

	if ($shortcut == 1 && 1 == scalar keys %link_hash) {
		my ($url) = each %link_hash;
		$url = &sanitizeuri($url);
		if ($urlviewcommand =~ m/%s/) {
			$urlviewcommand =~ s/%s/'$url'/g;
		} else {
			$urlviewcommand .= " $url";
		}
		system $urlviewcommand;
		exit 0;
	}


	my $cui = new Curses::UI(
		-color_support => 1,
		-clear_on_exit => 1
	);
	my $wrapwidth = $cui->width() - 2;
	my %listhash;
	my @listvals;
	foreach $url (sort {$link_hash{$a} <=> $link_hash{$b} } keys(%link_hash)) {
		push(@listvals,$link_hash{$url});
		$listhash{$link_hash{$url}} = $url;
	}

	my @menu = (
		{ -label => 'Press q or Ctrl-C to quit! Press m to access menu.', 
			-submenu => [
			{ -label => 'About', -value => \&about },
			{ -label => 'Show Command', -value => \&show_command },
			{ -label => 'Exit      ^Q', -value => \&exit_dialog  }
			],
		},
	);
	my $menu = $cui->add(
                'menu','Menubar', 
                -menu => \@menu,
        );
	my $win1 = $cui->add(
			'win1', 'Window',
			-border => 1,
			-y    => 1,
			-bfg  => 'red',
		);
	sub about()
	{
		$cui->dialog(
			-message => "The extract_url Program, version 1.1"
		);
	}
	sub show_command()
	{
		# This extra sprintf work is to ensure that the title
		# is fully displayed even if $urlviewcommand is short
		my $title = "The configured URL viewing command is:";
		my $len = length($title);
		my $cmd = sprintf("%-${len}s",$urlviewcommand);
		$cui->dialog(
			-title => "The configured URL viewing command is:",
			-message => $cmd,
		);
	}
	sub exit_dialog()
	{
		my $return = $cui->dialog(
			-message   => "Do you really want to quit?",
			-buttons   => ['yes', 'no'],
		);
		exit(0) if $return;
	}

	my $listbox = $win1->add(
		'mylistbox', 'Listbox',
		-values    => \@listvals,
		-labels    => \%listhash,
		);
	$cui->set_binding(sub {$menu->focus()}, "\cX");
	$cui->set_binding(sub {$menu->focus()}, "m");
	$cui->set_binding( sub{exit}, "q" );
	$cui->set_binding( \&exit_dialog , "\cQ");
	$cui->set_binding( sub{exit} , "\cc");
	$listbox->set_binding( 'option-last', "g");
	$listbox->set_binding( 'option-first', "G");
	sub madeselection {
		my $url = &sanitizeuri($listhash{$listbox->get_active_value()});
		my $command = $urlviewcommand;
		if ($command =~ m/%s/) {
			$command =~ s/%s/'$url'/g;
		} else {
			$command .= " $url";
		}
		my $return = 1;
		if ($noreview != 1 && length($url) > ($cui->width()-2)) {
			$return = $cui->dialog(
				-message => &urlwrap("  ",$url,$cui->width()-7),
				-title => "Your Choice",
				-buttons => ['ok', 'cancel'],
			);
		}
		if ($return) {
			system $command;
			exit 0 if ($persist == 0);
		}
	}
	$cui->set_binding( \&madeselection, " ");
	$listbox->set_routine('option-select',\&madeselection);

	$listbox->focus();
	$cui->mainloop();
} else {
	# using this as a pass-thru to URLVIEW
	foreach my $value (sort {$link_hash{$a} <=> $link_hash{$b} } keys %link_hash)
	{
		print "$value\n";
	}
}
