#${PMpre} NCD::CLI${PMpost}

use parent qw(CAF::Application CAF::Reporter);

use CAF::Reporter qw($LOGFILE);
use CAF::Object qw (SUCCESS throw_error);
use EDG::WP4::CCM::CacheManager;
use EDG::WP4::CCM::Fetch qw(NOQUATTOR NOQUATTOR_EXITCODE NOQUATTOR_FORCE);
use CAF::Lock qw(FORCE_IF_STALE FORCE_ALWAYS);

use Readonly;

# TODO: get from other module
Readonly my $QUATTOR_LOCKDIR => '/var/lock/quattor';
Readonly my $NCD_LOGDIR => '/var/log/ncm';
Readonly my $NCD_CONFIGFILE => '/etc/ncm-ncd.conf';
Readonly my $NCD_CHDIR => '/tmp';

=head1 NAME NCD::CLI

Module for the ncm-ncd CLI script

=head1 FUNCTIONS

=over

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

    $msg = "locked CCM configuration for cacheroot $cacheroot and profileID ".(defined($profileID) ? $profileID : '<undef>');
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

=item check_noquattor

Handle the presence of the /etc/noquattor file.
Exits, does not return anything.

=cut

sub check_noquattor
{
    my $self = shift;

    # Do not run if the file is present and check-noquattor is set
    if ($self->option('check-noquattor') &&
        -f NOQUATTOR && ! $self->option(NOQUATTOR_FORCE)) {
        $self->warn("ncm-ncd: not doing anything with ",
                        "check-noquattor set and ",
                        "CCM updates disabled globally (", NOQUATTOR, " present)");
        my $fh = CAF::FileReader->new(NOQUATTOR);
        $self->warn("$fh") if $fh;
        $self->finish(NOQUATTOR_EXITCODE);
    }
}

=item check_options

Check for any conflicting options.

Exits on any conflict, does not return anything.

=cut

sub check_options
{
    my $self = shift;

    $self->info('Dry run, no changes will be performed (--noaction flag set)')
        if ($self->option('noaction'));

    unless ($self->option('configure')
            || $self->option('unconfigure')
            || $self->option('list'))
    {
        $self->error('please specify either configure, unconfigure or list as options');
        $self->finish(-1);
    }

    if ($self->option('configure') && $self->option('unconfigure')) {
        $self->error('configure and unconfigure options cannot be used simultaneously');
        $self->finish(-1);
    }
}

=item action

Take action: list, unconfigure or (default) configure.

Report the components with C<list> and exit.
Otherwise return a hashref and the action name.

Takes existing exception context as argument.

=cut

sub action
{
    my ($self, $ec) = @_;

    my ($method, $action);

    if ($self->option('list')) {
        # Just do the list here
        my $compList = NCD::ComponentProxyList->new($self->getCCMConfig());
        unless (defined $compList) {
            $ec->ignore_error();
            $self->error("cannot get component(s)");
            $self->finish(-1);
        }
        $compList->reportComponents();
        $self->finish(0);
    } elsif ($self->option('unconfigure')) {
        # Sanity check the components passed to unconfigure
        # There should be exactly one.
        unless (scalar @ARGV) {
            $self->error("unconfigure requires one component as argument");
            $self->finish(-1);
        }
        unless (scalar @ARGV == 1) {
            $self->error('more than one components cannot be unconfigured at a time');
            $self->finish(-1);
        }

        $method = 'executeUnconfigComponent';
        $action = 'unconfigure';
    } else {
        # Default ComponentProxyList method / action to run
        $method = 'executeConfigComponents';
        $action = 'configure';
        $self->info('Ignoring broken pre/post dependencies (--nodeps flag set)')
            if ($self->option('nodeps'));
    }

    # Set the application lock
    $self->verbose('checking for ncm-ncd locks...');
    unless ($self->option("ignorelock")) {
        $self->lock() or $self->finish(-1);
    }

    # ignore-errors-from-dependencies implies nodeps and autodeps
    if($self->option('ignore-errors-from-dependencies')) {
        $self->{CONFIG}->set('nodeps', 1);
        $self->{CONFIG}->set('autodeps', 1);
    }

    # remove duplicates and sort
    my @component_names = sort(keys( %{ {map {$_ => 1} @ARGV} } ));
    $self->verbose("Sorted unique components ", join(',', @component_names),
                       " from commandline ", join(',', @ARGV));

    # TODO: shouldn't --all and listed components conflict?
    #       or should --all ignore any components from commandline?
    unless ($self->option('all') || @component_names) {
        $self->error("Please provide component names as parameters, or use --all");
        $self->finish(-1);
    }

    my $skip = $self->option('skip');
    if (defined $skip && !$self->option('all')) {
        $self->error("--skip option requires --all option to be set");
        $self->finish(-1);
    }

    unless (scalar(@component_names)) {
        $self->info('No components specified, getting all active ones.');
    }

    my $compList = NCD::ComponentProxyList->new($self->getCCMConfig(), $skip, @component_names);

    unless (defined $compList && defined($compList->{CLIST})) {
        $ec->ignore_error();
        $self->error("No components to dispatch.");
        $self->finish(-1);
    }

    my @args = (
        $self->option("pre-hook"),  $self->option("pre-hook-timeout"),
        $self->option("post-hook"), $self->option("post-hook-timeout"),
        );

    if ($self->option("chroot")) {
        chroot($self->option("chroot")) or die "Unable to chroot to ", $self->option("chroot");
    }

    if(! chdir($NCD_CHDIR)) {
        $self->warn("Failed to change to directory $NCD_CHDIR");
    };

    my $ret = $compList->$method(@args);

    return ($ret, $action);
}

# Create from a WARN_COMPS / ERR_COMPS hashref
# Used in report_exit
sub mk_msg
{
    my $href = shift;
    my $txt = "";

    foreach my $comp (sort keys %$href) {
        $txt .= "$comp ($href->{$comp}) ";
    }

    chop($txt);
    return $txt;
};

=item report_exit

Given the result of the C<NCD::ComponentProxyList> action,
report the succes and/or any errors and warnings and
C<exit> with the appropriate exitcode.

Takes a second argument C<action> to create appropriate message.

=cut

sub report_exit
{
    my ($self, $ret, $action) = @_;

    my $report_method  = 'OK';
    my $exitcode = 0;
    if ($ret->{ERRORS}) {
        $report_method  = 'error';
        $exitcode = -1;
    } elsif ($ret->{WARNINGS}) {
        $report_method = 'warn';
    }

    $self->report();
    $self->report('=========================================================');
    $self->report();


    my $methodmsg = $action;
    $methodmsg =~ s/e$/ing/;

    if ($ret->{ERRORS}) {
        $self->info("Errors while ${methodmsg}ing ", mk_msg($ret->{ERR_COMPS}));
    }

    if ($ret->{WARNINGS}) {
        $self->info("Warnings while ${methodmsg}ing ", mk_msg($ret->{WARN_COMPS}));
    }

    $self->$report_method($ret->{'ERRORS'}, ' errors, ', $ret->{'WARNINGS'}, ' warnings ', "executing $action");

    $self->finish($exitcode);
}

=item main

The CLI main method

=cut

sub main
{
    my ($self, $ec) = @_;

    # exit if not ok to continue
    $self->check_noquattor();

    $self->report();
    $self->log('------------------------------------------------------------');
    $self->info('NCM-NCD version ', $self->version(),
                ' started by ', $self->username(),
                ' at: ', scalar(localtime));

    # exits on failure
    $self->check_options();

    # add include directories to perl include search path
    if ($self->option('include')) {
        unshift(@INC, split(/:+/, $self->option('include')));
    }

    # set CCM Configuration
    if ($self->setLockCCMConfig($self->option('cache_root'), $self->option('useprofile'))) {
        # action exits when list option is used
        my ($ret, $action) = $self->action($ec);
        $self->report_exit($ret, $action);
    } else{
        $self->error("cannot get locked CCM configuration");
        $self->finish(-1);
    }
}

=pod

=back

=cut

1;
