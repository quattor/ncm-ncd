# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package NCM::Check;

use strict;
use LC::Exception qw (SUCCESS throw_error throw_warning);
use parent qw(LC::Check);

our ($this_app);

*this_app = \$main::this_app;

=pod

=head1 NAME

NCM::Check - control the state of system files

=head1 INHERITANCE

Derives from C<LC::Check>.  Most functions are described in the C<LC::Check>
manpage.

=head1 SYNOPSIS

  use NCM::Check;

  NCM::Check::lines('/filename',
    backup => ".suffix",
    linere => "regexp",
    goodre => "regexp",
    good   => "string",
    keep   => ("first" || "last" || "all"),
    add    => ("first" || "last" || "no"));

=head1 DESCRIPTION

C<NCM::Check> is a suite of functions to control the state of configuration files.
If the files are not correct, C<NCM::Check> will amend them.  Various
properties may be controlled, including:

=over 4

=item *

Existence of file (creation or deletion as necessary)

=item *

Presence of lines in a text file (added, rewritten or deleted as necessary)

=item *

File mode, owner, access time, hard and soft links, ...

=back

=head1 METHODS

=head2 NCM::Check::lines(file [, option ...])

Ensures that specified lines are present in I<file>.

A newline will be appended to the file if the last line is not newline-terminated.

Options:

=over 4

=item linere

Only lines matching /I<linere>/ will be considered.

=item goodre

Lines matching /I<goodre>/ will be preserved unchanged.

=item good

String to replace lines that match /I<linere>/ but not /I<goodre>/.  Must match
both /I<linere>/ and /I<goodre>/.

=item keep

Specifies which matching lines should be kept.

=over 4

=item C<first>

Keep only the first line matching /I<linere>/.

=item C<last>

Keep only the last line matching /I<linere>/.

=item C<all>

Default: keep all lines matching /I<linere>/.

=back

=item add

If no match for /I<linere>/ is found, C<NCM::Check::lines> may add the line to
the file.  This option specifies where to add the line:

=over 4

=item C<first>

Add I<good> string as the first line of the file.

=item C<last>

Default: add I<good> string as the last line of the file.

=item C<no>

Do not alter the file.

=back

=item backup

Save a copy of the original file, appending I<suffix> to the filename.

=item noaction

Override the global $NoAction flag.

=back

=cut

sub lines ($;%) {
    my($opath, %opt) = @_;
    my($message, $linere, $goodre, %opt2);

    # option handling

    # allow the backup option to be given as undef for backward compatibility
    delete($opt{backup}) if exists($opt{backup}) and not defined($opt{backup});

    my $result = LC::Check::_badoption(\%opt,
				    [qw(backup linere goodre good keep add)]);
    if ($result) {
      throw_error(defined($opt{$result}) ?
		  "invalid option" : "undefined option", $result);
      return();
    }
    #
    # linere must be defined and must be a valid regexp
    #
    if (exists($opt{linere})) {
      $linere = $opt{linere};
      eval { $linere =~ /$linere/ };
      if ($@) {
	throw_warning("bad linere: $linere\n$@");
	return(0);
      }
      # anchor the regexp if needed
      $linere = '^\s*' . $linere unless $linere =~ /^\^/;
      $linere = $linere . '\s*$' unless $linere =~ /\$$/;
    } else {
      throw_warning("no linere defined");
      return(0);
    }
    #
    # goodre must be defined and must be a valid regexp
    #
    if (exists($opt{goodre})) {
      $goodre = $opt{goodre};
      eval { $goodre =~ /$goodre/ };
      if ($@) {
	throw_warning("bad goodre: $goodre\n$@");
	return(0);
      }
      # anchor the regexp if needed
      $goodre = '^\s*' . $goodre unless $goodre =~ /^\^/;
      $goodre = $goodre . '\s*$' unless $goodre =~ /\$$/;
    } else {
      throw_warning("no goodre defined");
      return(0);
    }
    #
    # good must be defined and must match linere and goodre
    #
    unless (exists($opt{good})) {
      throw_warning("no good defined");
      return(0);
    }
    unless ($opt{good} =~ /$goodre/) {
      throw_warning("bad good: $opt{good} !~ /$opt{goodre}/");
      return(0);
    }
    unless ($opt{good} =~ /$linere/) {
      throw_warning("bad good: $opt{good} !~ /$opt{linere}/");
      return(0);
    }
    #
    # check that keep is first|last|all, default being all
    #
    if (exists($opt{keep})) {
      unless ($opt{keep} =~ /^first|last|all$/) {
	throw_warning("bad keep option: $opt{keep}");
	return(0);
      }
    } else {
      # default is all
      $opt{keep} = "all";
    }
    #
    # check that add is first|last|no, default being no
    #
    if (exists($opt{add})) {
      unless ($opt{add} =~ /^first|last|no$/) {
	throw_warning("bad add option: $opt{add}");
	return(0);
      }
    } else {
      # default is last
      $opt{add} = "last";
    }
    #
    # simply call LC::Check::file with a checking routine...
    #

    $opt2{source} = $opath;
    $opt2{backup} = $opt{backup} if defined($opt{backup});
    $opt2{noaction} = $opt{noaction} if defined($opt{noaction});
    $opt2{code} = sub {
                               my($contents) = @_;
			       my(@lines, $line, $count);
			       #
			       # split contents
			       #
			       @lines = ();
			       $count = 0;
			       $contents = "" unless defined($contents);
			       foreach $line (split(/\n/, $contents)) {
				   if ($line =~ /$linere/) {
				       $count++;
				       $line = $opt{good}
				           unless $line =~ /$goodre/;
				   }
				   push(@lines, $line);
			       }
			       #
			       # maybe add if missing
			       #
			       unless ($count) {
				   if ($opt{add} eq "first") {
				       unshift(@lines, $opt{good});
				   } elsif ($opt{add} eq "last") {
				       push(@lines, $opt{good});
				   }
			       }
			       #
			       # rebuild contents from lines and
			       # maybe remove duplicates
			       #
			       $contents = "";
			       if ($count <= 1 || $opt{keep} eq "all") {
				   # easy, we take all lines
				   foreach $line (@lines) {
				       $contents .= $line . "\n";
				   }
			       } else {
				   # maybe skip some lines
				   foreach $line (@lines) {
				       unless ($line =~ /$linere/) {
					   # we take this line
					   $contents .= $line . "\n";
					   next;
				       }
				       if ($opt{keep} eq "first") {
					   if ($count) {
					       # first
					       $count = 0;
					   } else {
					       # not first
					       next;
					   }
				       } elsif ($opt{keep} eq "last") {
					   if (--$count > 0) {
					       # not last
					       next;
					   } else {
					       # last
					   }
				       }
				       $contents .= $line . "\n";
				   }
			       }
			       return($contents);
	                };
    return(LC::Check::file($opath, %opt2));
}


1;
