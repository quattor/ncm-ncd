#${PMpre} NCD::CLI${PMpost}

use parent qw(CAF::Application CAF::Reporter);

use CAF::Reporter qw($LOGFILE);
use CAF::Object qw (SUCCESS throw_error);
use EDG::WP4::CCM::CacheManager;
use EDG::WP4::CCM::Fetch qw(NOQUATTOR_FORCE);
use CAF::Lock qw(FORCE_IF_STALE FORCE_ALWAYS);

use Readonly;

# TODO: get from other module
Readonly my $QUATTOR_LOCKDIR => '/var/lock/quattor';
Readonly my $NCD_LOGDIR => '/var/log/ncm';
Readonly my $NCD_CONFIGFILE => '/etc/ncm-ncd.conf';

=head1 NAME NCD::CLI

Module for the ncm-ncd CLI script

=head1 FUNCTIONS

=over

=cut


=item app_options

Extend C<CAF::Application> options

=cut

sub app_options()
{
    # these options complement the ones defined in CAF::Application
    my @array;
    push(
        @array,

        { NAME    => 'list',
          HELP    => 'list existing components and exit' },

        { NAME    => 'configure',
          HELP    => 'run the configure method on the components (passed as arguments, not values for this option)' },

        { NAME    => 'all',
          HELP    => 'used with --configure to run on all components' },

        { NAME    => 'unconfigure',
          HELP    => 'run the unconfigure method on the component (only one component at a time supported)' },

        { NAME    => 'logdir=s',
          HELP    => "log directory to use for log files (application and each component in case of multilog) (default $NCD_LOGDIR)",
          DEFAULT => $NCD_LOGDIR },

        { NAME    => 'cache_root:s',
          HELP    => 'CCM cache root directory (optional, otherwise CCM default taken)' },

        { NAME    => 'cfgfile=s',
          HELP    => "configuration file for ncd defaults (default $NCD_CONFIGFILE)",
          DEFAULT => $NCD_CONFIGFILE },

        { NAME    => 'multilog',
          HELP    => 'use separate component log files in log directory (enabled by default)',
          DEFAULT => 1 },

        { NAME    => 'noaction',
          HELP    => 'do not actually perform operations' },

        { NAME    => 'retries=i',
          HELP    => 'number of retries if ncd is locked',
          DEFAULT => 30 },

        { NAME    => 'state=s',
          HELP    => 'Component state files directory' },

        { NAME    => 'timeout=i',
          HELP    => 'maximum time in seconds between retries',
          DEFAULT => 30 },

        { NAME    => 'useprofile:s',
          HELP    => 'profile to use as configuration profile (optional, otherwise latest)' },

        { NAME    => 'skip:s',
          HELP    => 'skip one component (only to be used with --all)' },

        { NAME    => 'facility=s',
          HELP    => 'facility name for syslog',
          DEFAULT => 'local1' },

        { NAME    => "include=s",
          HELP    => 'a colon-seperated list of directories to include in search path' },

        { NAME    => "pre-hook=s",
          HELP    => "Command line to run as pre-hook" },

        { NAME    => "pre-hook-timeout=i",
          HELP    => "Time out for the pre hook, in seconds",
          DEFAULT => 300 },

        { NAME    => "post-hook=s",
          HELP    => "Command line to run as post hook" },

        { NAME    => "post-hook-timeout=i",
          HELP    => "Time out for hte post hook, in seconds",
          DEFAULT => 300 },

        { NAME    => "chroot=s",
          HELP    => "Chroot to the the directory given as an argument" },

        { NAME    => 'check-noquattor',
          HELP    => 'Do not run if CCM updates are globally disabled',
          DEFAULT => 0 },

        { NAME    => NOQUATTOR_FORCE,
          HELP    => 'Run even if CCM updates are globally disabled (and --check-noquattor is set)',
          DEFAULT => 0 },

        { NAME    => 'history',
          HELP    => 'Enable history/event tracking',
          DEFAULT => 1 },

        # Advanced options
        { NAME    => 'ignorelock',
          HELP    => 'ignore application lock. Use with care.' },

        { NAME    => 'forcelock',
          HELP    => 'take over application lock. Use with care.' },

        { NAME    => 'nodeps',
          HELP    => 'ignore broken (pre/post) dependencies in configure. Use with care.' },

        { NAME    => 'ignore-errors-from-dependencies',
          HELP    => 'errors from failing (pre/post) dependencies in configure are downgraded to warnings (implies --nodeps --autodeps). Use with care.' },

        { NAME    => 'autodeps!',
          HELP    => 'expand missing pre/post dependencies in configure. Use with care.',
          DEFAULT => 1 },

        { NAME    => 'allowbrokencomps',
          HELP    => 'Do not stop overall execution if broken components are found. Use with care.',
          DEFAULT => 1 },

        { NAME    => 'history-instances',
          HELP    => 'Enable history/event instances tracking. Use with care.',
          DEFAULT => 0 },

    );

    return \@array;

}


=item setLockCCMConfig


Set C<CACHEMGR> attribute with L<EDG::WP4::CCM::CacheManager> from C<cacheroot> and
C<CCM_CONFIG> attribute with locked configuration with C<profileID>.

Return SUCCESS on success, undef otherwise.

=cut

sub setLockCCMConfig
{
    my ($self, $cacheroot, $profileID) = @_;

    my $msg = "CCM cache manager with cacheroot $cacheroot";
    $self->verbose("accessing $msg");

    $self->{CACHEMGR} = EDG::WP4::CCM::CacheManager->new($cacheroot);
    unless (defined $self->{CACHEMGR}) {
        throw_error("cannot access $msg");
        return;
    }

    # Pass undef, not defined yet in CCM
    my $cred = undef;

    $msg = "locked CCM configuration for cacheroot $cachroot and profileID ".(defined($profileID) ? $profileID : '<undef>');
    $self->verbose("getting $msg");

    $self->{CCM_CONFIG} = $self->{CACHEMGR}->getLockedConfiguration($cred, $profileID);
    unless (defined $self->{CCM_CONFIG}) {
        throw_error("cannot get $msg");
        return;
    }

    return SUCCESS;
}


=item getCCMConfig

Return the CCM configuration instance from the C<CCM_CONFIG> atribute
(set by C<setLockCCMConfig> method).

=cut

sub getCCMConfig
{
    my $self = shift;

    return $self->{'CCM_CONFIG'};
}

=item lock

Try to take the lock for the C<ncm-ncd> application.
Lock instance is set in C<LOCK> attribute.

Return SUCCESS on success, undef otherwise.

=cut

sub lock
{
    my $self = shift;

    # /var/lock can be volatile
    mkdir($QUATTOR_LOCKDIR) if ! -d $QUATTOR_LOCKDIR;
    $self->{LOCK} = CAF::Lock->new("$QUATTOR_LOCKDIR/ncm-ncd", log => $self);

    my $lock_flag = FORCE_IF_STALE;
    $lock_flag = FORCE_ALWAYS if ($self->option("forcelock"));

    my $got_lock = $self->{LOCK}->set_lock($self->option("retries"), $self->option("timeout"), $lock_flag);

    return $got_lock ? SUCCESS : undef;
}

=item finish

Release the lock (if this instance has it)
and exit with C<ret> exitcode.

=cut

sub finish
{
    my ($self, $ret) = @_;
    $self->{LOCK}->unlock() if ($self->{LOCK} && $self->{LOCK}->is_set());
    exit($ret);
}

=item _initialize

Initialize the C<CAF::Application>

=cut

sub _initialize
{
    my $self = shift;

    # define application specific data.

    # external version number
    $self->{VERSION} = '${project.version}';

    # show setup text
    $self->{USAGE} =
          "Usage: ncm-ncd --configure   [options] [component1 [component2] ...] or\n"
        . "       ncm-ncd --unconfigure [options] <component>\n";
    #
    # start initialization of CAF::Application
    #
    unless ($self->SUPER::_initialize(@_)) {
        return undef;
    }

    # ensure allowed to run
    if ($>) {
        $self->error("Sorry " . $self->username() . ", this program must be run by root");
        exit(-1);
    }

    $self->{NCD_LOGFILE} = $self->option("logdir") . '/ncd.log';

    return if(! $self->init_logfile($self->{NCD_LOGFILE}, 'at'));

    # Legacy LOG attibute
    $self->{LOG} = $self->{$LOGFILE};

    # start history event tracking
    $self->{REPORTED_EVENTS} = [];
    $self->init_history($self->option("history-instances"))
        if $self->option("history");

    return SUCCESS;
}

=pod

=back

=cut

1;
