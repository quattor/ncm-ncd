# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}

package NCM::Component;

use strict;
use vars qw(@ISA $this_app @EXPORT $NoAction $SYSNAME $SYSVERS);
use LC::Exception qw (SUCCESS throw_error);
use LC::Sysinfo;
use CAF::Object;
use Exporter;
use Template;
use Template::Stash;

@ISA=qw(Exporter CAF::Object);

*this_app = \$main::this_app;

@EXPORT=qw($NoAction $SYSNAME $SYSVERS);

$NoAction=$this_app->option('noaction');
$CAF::Object::NoAction=$NoAction;

$SYSNAME=LC::Sysinfo::os()->name;
$SYSVERS=LC::Sysinfo::os()->version;

my $EC=LC::Exception::Context->new->will_report_all;

=pod

=head1 NAME

NCM::Component - basic support functions for NCM components

=head1 INHERITANCE

  CAF::Object

=head1 DESCRIPTION

This class provides the neccessary support functions for components,
which have to inherit from it. Some functions provide aliases, for
enhanced LCFG backwards compatibility.

=head1 AUTHOR

German Cancio <German.Cancio@cern.ch>

=head1 VERSION

$Id: Component.pm.cin,v 1.11 2008/07/28 16:51:35 munoz Exp $

=cut


#------------------------------------------------------------
#                      Public Methods/Functions
#------------------------------------------------------------

=pod

=head1 Public methods

=over 4

=item log(@array) or LogMessage(@array)

write @array to component's logfile

=cut

*LogMessage = *log;
sub log {
  my $self=shift;
  $self->{LOGGER}->log(@_);
}


=pod

=item report(@array) or Report(@array)

write @array to component's logfile and stdout.

=cut

*Report = *report;
sub report {
  my $self=shift;
  $self->{LOGGER}->report(@_);
}

=pod

=item info(@array) or Info(@array)

same as 'report', but string prefixed by [INFO]

=cut

*Info = *info;
sub info {
  my $self=shift;
  $self->{LOGGER}->info(@_);
}

=pod

=item OK(@array)

same as 'report', but string prefixed by [OK]

=cut

sub OK {
  my $self=shift;
  $self->{LOGGER}->OK(@_);
}

=pod

=item verbose(@array) or Verbose(@array)

as 'report' - only if verbose output is activated.

=cut

*Verbose = *verbose;
sub verbose {
  my $self=shift;
  $self->{LOGGER}->verbose(@_);
}

=pod

=item debug($int,@array) or Debug(@array)

as 'report' - only if debug level $int is activated. If called as
Debug(@array), the default debug level is set to 1.

=cut

sub debug {
  my $self=shift;
  $self->{LOGGER}->debug(@_);
}

sub Debug {
  my $self=shift;
  $self->{LOGGER}->debug(1,@_);
}


=pod

=item warn(@array) or Warn(@array)

as 'report', but @array prefixed by [WARN]. Increases the number of
reported warnings by 1.

The ncd will report the number of warnings reported by the component.

=cut

*Warn = *warn;
sub warn {
  my $self=shift;
  $self->{LOGGER}->warn(@_);
  $self->{'WARNINGS'}++;
}

=pod

=item error(@array) or Error(@array)

as 'report', but @array prefixed by [ERROR]. Increases the number of
reported errors by 1. The component will therefore be flagged as
failed, and no depending components will be executed.

The ncd will report the number of errors reported by the component.

=cut

*Error = *error;
sub error {
  my $self=shift;
  $self->{LOGGER}->error(@_);
  $self->{'ERRORS'}++;
}



=pod

=item name():string

Returns the component name

=cut

sub name {
  my $self=shift;
  return $self->{'NAME'};
}

=pod

=item prefix():string

Returns the standard configuration path for the component.

=cut

sub prefix {
  my ($proto) = @_;
  my $class = ref $proto ? ref $proto : $proto;
  my @nsclass = split(/::/, $class);
  my $short = pop(@nsclass);
  return "/software/components/$short";
}


#=pod
#
#=item noaction(): 0|1
#
#Returns if noaction flag is set by the application.
#
#=cut
#
#sub noaction {
#  my $self=shift;
#  return $self->{'NOACTION'};
#}


=pod

=item unescape($string): $string

Returns the unescaped version of the string provided as parameter (as escaped by using the corresponding PAN function).

=cut

sub unescape ($) {
  my ($self,$str)=@_;

  $str =~ s!(_[0-9a-f]{2})!sprintf("%c",hex($1))!eg;
  return $str;
}

=pod

=item escape($string): $string

Returns the escaped version of the string provided as parameter (similar to the corresponding PAN function)

=cut

sub escape ($) {
  my ($self,$str)=@_;

  $str =~ s/(^[0-9]|[^a-zA-Z0-9])/sprintf("_%lx", ord($1))/eg;
  return $str;
}



=pod

=item get_warnings(): integer

Returns the number of calls to 'warn' by the component.

=cut

sub get_warnings {
  my $self=shift;

  return $self->{'WARNINGS'};
}

=pod

=item get_errors(): integer

Returns the number of calls to 'error' by the component.

=cut

sub get_errors {
  my $self=shift;

  return $self->{'ERRORS'};
}


=pod

=head1 Pure virtual methods

=item Configure($config): boolean

Component Configure method. Has to be overwritten if used.

=cut


sub Configure {
  my ($self,$config)=@_;

  $self->error('Configure() method not implemented by component');
  return undef;
}

=pod

=item Unconfigure($config): boolean

Component Unconfigure method. Has to be overwritten if used.

=cut


sub Unconfigure {
  my ($self,$config)=@_;

  $self->error('Unconfigure() method not implemented by component');
  return undef;
}




=pod

=head1 Private methods

=item _initialize($comp_name)

object initialization (done via new)

=cut

sub _initialize {
  my ($self,$name, $logger)=@_;

  unless (defined $name) {
    throw_error('bad initialization');
    return undef;
  }
  $self->{'NAME'}=$name;
  $self->{'ERRORS'}=0;
  $self->{'WARNINGS'}=0;
  $self->{LOGGER} = defined $logger ? $logger:$this_app;
  return SUCCESS;
}

$Template::Stash::PRIVATE = undef;
my $template = Template->new(INCLUDE_PATH =>
			     $this_app->option("template-path"));

sub template
{
    return $template;
}


#+#############################################################################
1;

