#${PMpre} NCM::Component${PMpost}

use LC::Exception qw (SUCCESS throw_error);
use LC::Sysinfo;
use CAF::History qw($IDX);
use CAF::Reporter qw($HISTORY);
use parent qw(Exporter CAF::Object);

our ($this_app, @EXPORT, $NoAction, $SYSNAME, $SYSVERS);

*this_app = \$main::this_app;

@EXPORT = qw($NoAction $SYSNAME $SYSVERS);

$NoAction = defined($this_app) ? $this_app->option('noaction') : 0;
$CAF::Object::NoAction = $NoAction;

$SYSNAME = LC::Sysinfo::os()->name;
$SYSVERS = LC::Sysinfo::os()->version;

my $EC = LC::Exception::Context->new->will_report_all;

=pod

=head1 NAME

NCM::Component - basic support functions for NCM components

=head1 INHERITANCE

  CAF::Object

=head1 DESCRIPTION

This class provides the neccessary support functions for components,
which have to inherit from it.

=head1 Public methods

=over

=item warn

Report with loglevel 'WARN'. Increases the number of
reported warnings in the C<WARNINGS> attribute by 1.

(The ncd client will report the number of warnings reported by the component.)

=cut

sub warn
{
    my $self = shift;
    $self->SUPER::warn(@_);
    $self->{WARNINGS}++;
}

=item error

Report with loglevel 'ERROR'. Increases the number of
reported errors in the C<ERRORS> attribute by 1.

(The ncd client will report the number of errors reported by the component.
The component will therefore be flagged as
failed, and no depending components will be executed.)

=cut

sub error
{
    my $self = shift;
    $self->SUPER::error(@_);
    $self->{ERRORS}++;
}

=item name

Returns the component name

=cut

sub name
{
    my $self = shift;
    return $self->{NAME};
}

=item prefix

Returns the standard configuration path for the component
C<</software/components/<name>>>.

=cut

sub prefix
{
    my ($self) = @_;

    return "/software/components/$self->{NAME}";
}


=item unescape($string): $string

Returns the unescaped version of the string provided as parameter (as escaped by using the corresponding PAN function).

=cut

sub unescape
{
    my ($self, $str) = @_;

    $str =~ s!(_[0-9a-f]{2})!sprintf("%c",hex($1))!eg;
    return $str;
}

=item escape($string): $string

Returns the escaped version of the string provided as parameter (similar to the corresponding PAN function)

=cut

sub escape
{
    my ($self, $str) = @_;

    $str =~ s/(^[0-9]|[^a-zA-Z0-9])/sprintf("_%lx", ord($1))/eg;
    return $str;
}


=item get_warnings(): integer

Returns the number of calls to 'warn' by the component.

=cut

sub get_warnings
{
    my $self = shift;

    return $self->{WARNINGS};
}

=item get_errors(): integer

Returns the number of calls to 'error' by the component.

=cut

sub get_errors
{
    my $self = shift;

    return $self->{ERRORS};
}

=item event

Add an event to the history (if exists). Following metadata is added

=over

=item component

The component name

=item component_module

The component module

=back

All other arguments are passed on unmodified.

=cut

sub event
{
    my ($self, $object, %metadata) = @_;

    return SUCCESS if (! $self->{log}->can('event'));

    $metadata{component} = $self->name();
    $metadata{component_module} = ref($self);

    return $self->{log}->event($object, %metadata);
}

=item event_report

Report any relevant events:

=over

=item events triggered by this component

=item modified files

=back

Returns arrayref with reported event indices.

=cut

sub event_report
{
    my ($self) = @_;

    my $history = $self->{log}->{$HISTORY};
    return [] if (! $history);

    my $match = sub {
        my $ev = shift;

        # only return relevant events for this component
        return if (($ev->{component} || '') ne $self->name());

        # only return modified events
        return if (! $ev->{modified});

        # match!
        return 1;
    };

    # Besides IDX and component name, only filename metadata?
    my $filter = [$IDX, 'filename', 'component'];
    my $evs = $history->query_raw($match, $filter);

    my @idxs;
    foreach my $ev (@$evs) {
        push(@idxs, $ev->{$IDX});
        $self->info("EVENT: $ev->{component} modified file $ev->{filename}");
    }

    $self->verbose("No events to report") if (! @idxs);

    return \@idxs;
}


=item add_files()

Stores files that have been manipulated by this component

=cut

sub add_files
{
    my ($self, @files) = @_;

    push(@{$self->{FILES}}, @files);
}

=item get_files(): ref to list of strings

Returns a reference to the list of files manipulated by the component

=cut

sub get_files
{
    my $self = shift;

    return $self->{FILES};
}

=item set_active_config

Set C<config> as the C<ACTIVE_CONFIG> attribute.

Returns the current active config.

=cut

sub set_active_config
{
    my ($self, $config) = @_;

    $self->{ACTIVE_CONFIG} = $config;

    return $self->{ACTIVE_CONFIG};
}


=back

=head1 Pure virtual methods

=over

=item Configure($config): boolean

Component Configure method. Has to be overwritten if used.

=cut


sub Configure
{
    my ($self, $config) = @_;

    $self->error('Configure() method not implemented by component');
    return;
}

=item Unconfigure($config): boolean

Component Unconfigure method. Has to be overwritten if used.

=cut


sub Unconfigure
{
    my ($self, $config) = @_;

    $self->error('Unconfigure() method not implemented by component');
    return;
}


=back

=head1 Private methods

=over

=item _initialize

object initialization (done via new)

Arguments

=over

=item name

Set the component name

=item logger

Set the logger instance (C<main::this_app> is used as default when undefined)

=back

Optional arguments

=over

=item config

Set config as active config (using C<set_active_config> method).

=back

=cut

sub _initialize
{
    my ($self, $name, $logger, %opts) = @_;

    unless (defined $name) {
        throw_error('bad initialization (missing first "name" agument)');
        return undef;
    }

    $self->{NAME} = $name;
    $self->{ERRORS} = 0;
    $self->{WARNINGS} = 0;
    $self->{FILES} = [];
    $self->{log} = defined $logger ? $logger : $this_app;

    # Keep LOGGER attribute for backwards compatibility
    $self->{LOGGER} = $self->{log};

    if ($opts{config}) {
        $self->set_active_config($opts{config});
    }

    return SUCCESS;
}

=back

=head1 Legacy methods

=over

=item LogMessage

Same as C<log> method.
This is deprecated, use C<log> method instead.

=cut

*LogMessage = *log;

=item Report

Same as C<report> method.
This is deprecated, use C<report> method instead.

=cut

*Report = *report;

=item Info

Same as C<info> method.
This is deprecated, use C<info> method instead.

=cut

*Info = *info;

=item Verbose

Same as C<verbose> method.
This is deprecated, use C<verbose> method instead.

=cut

*Verbose = *verbose;

=item Debug

Similar to C<debug>,  but the debug level is set to 1.

This is deprecated, use C<debug> method instead and set loglevel.

=cut

sub Debug {
    my $self = shift;
    $self->debug(1, @_);
}

=item Warn

Same as C<warn> method.
This is deprecated, use C<report> method instead.

=cut

*Warn = *warn;

=item Error

Same as C<error> method.
This is deprecated, use C<error> method instead.

=cut

*Error = *error;

=pod

=back

=cut

1;
