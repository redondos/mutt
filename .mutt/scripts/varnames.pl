#!/usr/bin/perl -w
###
# written 08 Aug 2006 by Rado S
#
# This script must be applied MANUALLY to all used config files:
### those separated by version as well as split up to be sourced from main file.
### it doesn't scan for "source" cmds to auto-convert them, but you can give 2 dirs, auto-convert all files.
### target-dir must exist for either dir or file as destination.
#
# This is a SIMPLE translation script that matches "set(SPC+varname)+" till EOL,
# its primary goal is to help stable users, but tries to please dev-users with $ expansion too, so it CAN FAIL when:
### you use varnames in (extremly) exotic ways (rare, see below, or $var expansion outside of "set" cmd).
### "alternates" is not 1st var in set cmd.
### it processes "#" comments, so "set ..." there is changed, too, possibly false positives.
### comments on same line like "set ... # comment" are optionally processed: specify any 3rd arg.
### ==> you MUST re-check your config after execution for those cases and fix manually.
#
# You MAY try to apply it to SHELL-scripts which PRODUCE muttrc config, BUT this is NOT 100% SAFE:
### This means SHELL-scripts called before mutt to prepare config, or from within mutt in `` substitutions or "source ...|".
### It works only with complete muttrc "set" cmds, it fails if only parts of "set" args are `` subst'ed.
#
# It has SIMPLE string skipping code, but it's no 100% safe muttrc parser:
### it might fail or produce false positives for string values with many varying quotes per assignment (rare).

use strict;

my $CONVFILE= 'manual-vars';    ### location of conversion source file, originally copied from /List
my $LINECONT= ':LINECONT:';     ### place-holder for \\\n line-continuation, must NOT appear naturally in muttrc,
                                ### must NOT contain muttrc special chars like #=;\n or quote-chars
my $PATCHFILE='/dev/null';      ### where the conversion list will be saved to be used with /Test script to patch init.h.

my ($hits, $total, $changed) = (0,0, 0);
my %trans;
my $STOPCOMMENTS= (@ARGV < 3);

sub replace($) {
my ($match) = @_;
my @tokens = split(/\b/,$match);
my ($prev,$value);
($prev,$value) =('','');

ITEM:
        foreach $match (@tokens) {
        if ($match =~ /\W/) {
                if ($value =~ /=(["'`])/ ) {
                my $quote=$1 ;
                        if ( $match =~ /$quote/ ) {
                                $value=$match;
### necessary to avoid values being treated as keywords, remember it's RHS by keeping "=" when string not closed
                                if ($STOPCOMMENTS && ($match =~ /$quote.*#/ )) { last ITEM; }
### necessary to avoid comments after "set" being treated as keywords
                        }
                } else {
                        $value=$match;
                        if ($STOPCOMMENTS && ($match =~ /^[^=]*#/ )) { last ITEM; }
### necessary to avoid comments after "set" being treated as keywords, but ignore in strings
                }

        } elsif ((($value !~ /=/ ) && ($prev !~ /;/)) || ($prev =~ /\$$/ )) {
                $match =~ /^(no|inv)*(.*)$/;
                my ($ctrl,$stripped) = ($1,$2);
                if (exists($trans{$stripped})) {
                        $hits++; if (!defined($ctrl)) { $ctrl='';}
                        $match = $ctrl . $trans{$stripped};
                }
        } # if
                $prev=$match;
        } # foreach
        $match = join('',@tokens);
        return $match;
} # sub

### read whole files as single line
undef $/;

### setup conversion table
open(CONVLIST, "<$CONVFILE") || die("Can't open conversion file $CONVFILE.");
my $TABLE = <CONVLIST>;
close(CONVLIST);

my $prefix='';

### for the patch
open(TRANSLIST,">$PATCHFILE") || die "Can't open file $PATCHFILE to save translation list for init.h patch";
print TRANSLIST "====== unchanged vars ======\n";

### construct trans-table
my $line;
LINE:
foreach $line (split(/\n+/,$TABLE)) {
        if ($line =~ /^(\S+)/) { $prefix = $1; next LINE; }
        my (@pair) = split(/[\s(,)]+/, $line);  ### drop meta chars like () from new name
        my ($src,$dst) = @pair[1..2];
        if (!defined($dst)) { $dst='';}
if ($dst =~ /-/) { $dst=''; }   ### print STDERR "$src has only comment\n";
        if (!$dst) { $dst = $src; }
        $dst =~ s,^(${prefix}_)+,,;     ### no multi prefix
        $dst=$prefix.'_'.$dst;
        if ($dst ne $src) { $trans{$src}=$dst; }
### for the patch
else { print TRANSLIST "$src\n";}
}

### for the patch
print TRANSLIST "\n====== now the conversions ======\n";
foreach my $item (sort keys %trans) { print TRANSLIST "$item : $trans{$item}\n"; }
close(TRANSLIST);

### HERE BEGINS THE ACTUAL WORK ###

if (@ARGV < 2) { die("Need destination file, will not replace files."); }

my @SOURCES;
my ($SRCFILE, $NEWFILE);
my ($SRCDIR,$NEWDIR) = @ARGV;
if (-d $SRCDIR) {
        if (! -d $NEWDIR) { die("When source is a dir, then destination must be dir, too!");}
        opendir(DIR, $SRCDIR);
        @SOURCES = grep { $_ !~ /^(\.\.?)$/ } readdir( DIR);
        closedir(DIR);
        $SRCDIR.="/";
        $NEWDIR.="/";
} else { @SOURCES = ($SRCDIR); $SRCDIR='';}

my $file;
FILE:
foreach $file (@SOURCES) {
($SRCFILE, $NEWFILE) = ("$SRCDIR$file","$NEWDIR");

### now slurp it in.
unless (open(SOURCE,"<$SRCFILE")) { warn("Can't open old config file $SRCFILE."); next FILE;}
my $config = <SOURCE>;
$config =~ s,\\\n, $LINECONT ,go;
close(SOURCE);

if (-d $NEWFILE) { my $tmp=$SRCFILE; $tmp=~s,^.*/,,; $NEWFILE.="/$tmp"; }
$NEWFILE =~ s,//+,/,go;
if (-s $NEWFILE) { warn("Destination file $NEWFILE must not exist, will not replace files."); next FILE;}

### special case: var becomes cmd.
$hits= ($config =~ s/(set([ \t]| $LINECONT )+)(alternates)=?/$3 /gm );

### now the _real_ deal
$total = $hits + ($config =~ s/(\b(un|re)?set|toggle)([ \t]+[^\n]+)/$1 . replace($3)/gme );

### changed type to plain boolean, no "ask-"
$config =~ s,(pgp_autoinline=['"]*)ask-,$1,gm;

### save changes
unless (open(TARGET,">$NEWFILE")) { warn("Can't open NEW config file $NEWFILE, does dir exist?"); next FILE ;}
$config =~ s, $LINECONT ,\\\n,go;
print TARGET $config;
close(TARGET);

printf STDERR "changed vars: %3s in checked lines: %3d in $NEWFILE\n", $hits, $total;

$changed+=$hits;

} # foreach SOURCES, FILE

if ($changed) {
print STDERR "Total $changed changes. Please verify excess or missing changes!!! Use this cmd:\n";
if ($#SOURCES < 1) {
        print STDERR "\tsdiff $SRCFILE $NEWFILE| less +'/ \\| '\n";
} else {
        print STDERR "\tdiff -r $SRCDIR $NEWDIR| less +'/^diff.*'\n";
}
}

### EOF
