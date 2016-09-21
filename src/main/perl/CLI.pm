#------------------------------------------------------------
# Application
#------------------------------------------------------------

package ncd;

use strict;
use warnings;
use parent qw(CAF::Application CAF::Reporter);
use CAF::Reporter qw($LOGFILE);
use LC::Exception qw (SUCCESS throw_error);
use EDG::WP4::CCM::CacheManager;
use EDG::WP4::CCM::Fetch qw(NOQUATTOR_FORCE);
use CAF::Lock qw(FORCE_IF_STALE FORCE_ALWAYS);

#
# Public Methods/Functions for CAF
#

sub app_options()
{
    # these options complement the ones defined in CAF::Application
    my @array;
    push(
        @array,

        {
            NAME    => 'list',
            HELP    => 'list existing components and exit',
            DEFAULT => undef
        },

        {
            NAME    => 'configure',
            HELP    => 'run the configure method on the components',
            DEFAULT => undef
        },

        {
            NAME    => 'all',
            HELP    => 'used with --configure to run on all components',
            DEFAULT => undef
        },

        {
            NAME    => 'unconfigure',
            HELP    => 'run the unconfigure method on the component (only one component at a time supported)',
            DEFAULT => undef
        },

        {
            NAME    => 'logdir=s',
            HELP    => 'log directory to use for ncd log files',
            DEFAULT => '/var/log/ncm'
        },

        {
            NAME    => 'cache_root:s',
            HELP    => 'CCM cache root directory (optional, otherwise CCM default taken)',
            DEFAULT => undef
        },

        {
            NAME    => 'cfgfile=s',
            HELP    => 'configuration file for ncd defaults',
            DEFAULT => '/etc/ncm-ncd.conf'
        },

        {
            NAME    => 'multilog',
            HELP    => 'use separate component log files in log directory',
            DEFAULT => 1
        },

        {
            NAME    => 'noaction',
            HELP    => 'do not actually perform operations',
            DEFAULT => undef
        },

        {
            NAME    => 'retries=i',
            HELP    => 'number of retries if ncd is locked',
            DEFAULT => 30
        },

        {
            NAME    => 'state=s',
            HELP    => 'where to find state files',
            DEFAULT => undef
        },

        {
            NAME    => 'timeout=i',
            HELP    => 'maximum time in seconds between retries',
            DEFAULT => 30
        },

        {
            NAME    => 'useprofile:s',
            HELP    => 'profile to use as configuration profile (optional, otherwise latest)',
            DEFAULT => undef
        },

        {
            NAME    => 'skip:s',
            HELP    => 'skip one component (only to be used with --all)',
            DEFAULT => undef
        },

        {
            NAME    => 'facility=s',
            HELP    => 'facility name for syslog',
            DEFAULT => 'local1'
        },

        {
            NAME    => "template-path=s",
            HELP    => 'store for Template Toolkit files',
            DEFAULT => '/usr/share/templates/quattor'
        },

        {
            NAME    => "include=s",
            HELP    => 'a colon-seperated list of directories to include in search path',
            DEFAULT => undef
        },

        {
            NAME => "pre-hook=s",
            HELP => "Command line to run as pre-hook"
        },
        {
            NAME    => "pre-hook-timeout=i",
            HELP    => "Time out for the pre hook, in seconds",
            DEFAULT => 300
        },
        {
            NAME => "post-hook=s",
            HELP => "Command line to run as post hook"
        },
        {
            NAME    => "post-hook-timeout=i",
            HELP    => "Time out for hte post hook, in seconds",
            DEFAULT => 300
        },
        {
            NAME    => "chroot=s",
            HELP    => "Chroot to the the directory given as an argument",
            DEFAULT => undef
        },

        {
            NAME    => 'check-noquattor',
            DEFAULT => 0,
            HELP    => 'Do not run if CCM updates are globally disabled',
        },

        {
            NAME    => NOQUATTOR_FORCE,
            DEFAULT => 0,
            HELP    => 'Run even if CCM updates are globally disabled (and --check-noquattor is set)',
        },

        {
            NAME    => 'history',
            HELP    => 'Enable history/event tracking',
            DEFAULT => 1
        },

        # Advanced options
        {
            NAME => 'ignorelock',
            HELP => 'ignore application lock. Use with care.'
        },

        {
            NAME => 'forcelock',
            HELP => 'take over application lock. Use with care.'
        },

        {
            NAME    => 'nodeps',
            HELP    => 'ignore broken (pre/post) dependencies in configure. Use with care.',
            DEFAULT => undef
        },

        {
            NAME    => 'ignore-errors-from-dependencies',
            HELP    => 'errors from failing (pre/post) dependencies in configure are downgraded to warnings (implies --nodeps --autodeps). Use with care.',
            DEFAULT => undef
        },

        {
            NAME    => 'autodeps!',
            HELP    => 'expand missing pre/post dependencies in configure. Use with care.',
            DEFAULT => 1
        },

        {
            NAME    => 'allowbrokencomps',
            HELP    => 'Do not stop overall execution if broken components are found. Use with care.',
            DEFAULT => 1
        },

        {
            NAME    => 'history-instances',
            HELP    => 'Enable history/event instances tracking. Use with care.',
            DEFAULT => 0
        },

    );

    return \@array;

}

# public methods

#
# setLockedCCMConfig($cacheroot,$profileID): boolean
#

sub setLockCCMConfig
{
    my ($self, $cacheroot, $profileID) = @_;

    $self->verbose('accessing CCM cache manager..');

    $self->{'CACHEMGR'} = EDG::WP4::CCM::CacheManager->new($cacheroot);
    unless (defined $self->{'CACHEMGR'}) {
        throw_error('cannot access cache manager');
        return undef;
    }

    my $cred = undef;    # not defined yet in CCM

    $self->verbose('getting locked CCM configuration..');

    $self->{'CCM_CONFIG'} = $self->{'CACHEMGR'}->getLockedConfiguration($cred, $profileID);
    unless (defined $self->{'CCM_CONFIG'}) {
        throw_error('cannot get configuration via CCM');
        return undef;
    }

    return SUCCESS;
}

#
# getCCMConfig(): ref(EDG::WP4::CCM::Configuration)
# returns the CCM config instance
#

sub getCCMConfig
{
    my $self = shift;

    return $self->{'CCM_CONFIG'};
}

#
# Other relevant methods
#

sub lock
{
    my $self = shift;

    # /var/lock can be volatile
    mkdir('/var/lock/quattor');
    $self->{LOCK} = CAF::Lock->new('/var/lock/quattor/ncm-ncd', log => $self);
    my $lock_flag = FORCE_IF_STALE;
    $lock_flag = FORCE_ALWAYS if ($self->option("forcelock"));
    unless ($self->{LOCK}->set_lock($self->option("retries"), $self->option("timeout"), $lock_flag))
    {
        return undef;
    }
    return SUCCESS;
}

sub finish
{
    my ($self, $ret) = @_;
    $self->{LOCK}->unlock() if ($self->{LOCK} && $self->{LOCK}->is_set());
    exit($ret);
}

sub _initialize
{
    my $self = shift;
    #
    # define application specific data.
    #
    # external version number
    $self->{'VERSION'} = '${project.version}';

    # show setup text
    $self->{'USAGE'} =
          "Usage: ncm-ncd --configure   [options] [<component1,2..>] or\n"
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

    $self->{'NCD_LOGFILE'} = $self->option("logdir") . '/ncd.log';

    return if(! $self->init_logfile($self->{'NCD_LOGFILE'}, 'at'));
    # Legacy LOG attibute
    $self->{'LOG'} = $self->{$LOGFILE};

    # start history event tracking
    $self->{REPORTED_EVENTS} = [];
    $self->init_history($self->option("history-instances"))
        if $self->option("history");

    return SUCCESS;
}
