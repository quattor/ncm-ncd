#${PMpre} NCD::ComponentProxy${PMpost}

use CAF::Object qw (SUCCESS throw_error);

use CAF::Reporter qw($HISTORY $LOGFILE);

use parent qw(CAF::ReporterMany CAF::Object);

use EDG::WP4::CCM::CacheManager;
use EDG::WP4::CCM::Path;
use LC::Check;
use Cwd qw(getcwd);

use File::Path;

our $this_app;
*this_app = \$main::this_app;

my $ec = LC::Exception::Context->new->will_store_all;

use Readonly;
Readonly my $COMPONENTS_PROFILE_PATH => '/software/components';
Readonly my $RUN_FROM => '/tmp';

Readonly my $COMPONENT_BASE => "/usr/lib/perl/NCM/Component";
# Methods called during _execute
Readonly::Array my @COMPONENT_MANDATORY_METHODS => qw(Configure
    error warn get_errors get_warnings name
);

=pod

=head1 NAME

NCD::ComponentProxy - component proxy class

=head1 INHERITANCE

  CAF::Object, CAF::Reporter

=head1 DESCRIPTION

Provides management functions for accessing and executing NCM
components.

=head2 Public methods

=over 4

=item executeConfigure

executeConfigure loads and executes the component with C<Configure> method.
The number of produced errors and warnings is returned in
a hashref with keys C<ERRORS> and C<WARNINGS>.
If the component cannot be executed, undef is returned.

=cut

sub executeConfigure
{
    my $self = shift;

    return $self->_execute('Configure');
}


=item executeUnconfigure

executeUnconfigure loads and executes the component with C<Unconfigure>.
The number of produced errors and warnings is returned in
a hashref with keys C<ERRORS> and C<WARNINGS>.
If the component cannot be executed, undef is returned.

=cut

sub executeUnconfigure
{
    my $self = shift;

    return $self->_execute('Unconfigure');
}


=item name

returns the name of the component

=cut

sub name
{
    my $self = shift;
    return $self->{NAME};
}

=pod

=item module

returns the module to be loaded for executing the component

=cut

sub module
{
    my $self = shift;
    return $self->{MODULE};
}


=item getPreDependencies

returns an arrayref with the names of predependent components.
The arrayref is empty if no predependencies are found.

=cut

sub getPreDependencies
{
    my $self = shift;
    return $self->{PRE_DEPS};
}


=item getPostDependencies

returns an arrayref with the names of postdependent components.
The array is empty if no postdependencies are found.

=cut

sub getPostDependencies
{
    my $self = shift;

    return $self->{POST_DEPS};
}


=item getComponentFilename

Returns the absolute filename of the components perl module.

Receives an optional parameter with the base directory where the Perl
module should be looked for.

=cut

sub getComponentFilename
{
    my ($self, $base) = @_;

    $base ||= $self->{COMPONENT_BASE};

    my $mod = $self->module();
    $mod =~ s{::}{/}g;

    my $fn = "$base/$mod.pm";
    $fn =~ s{//+}{/}g;

    return $fn;
}


=item hasFile

returns 1 if the components perl module is installed, 0 otherwise.

Receives an optional parameter with the base directory where the Perl
module should be looked for.

=cut

sub hasFile
{
    my ($self, $base) = @_;

    my $filename = $self->getComponentFilename($base);

    return -r $filename ? 1 : 0;
}

=back

=head2 Private methods

=over

=item _initialize

object initialization (done via new)

=cut

sub _initialize
{
    my ($self, $name, $config) = @_;
    $self->setup_reporter();

    if (!defined($name) || !defined($config)) {
        throw_error('bad initialization');
        return;
    }

    if ($name =~ m{^([a-zA-Z_]\w+)$}) {
        $self->{NAME} = $1;
    } else {
        throw_error ("Bad component name: $name");
        return;
    }

    $self->{CONFIG} = $config;

    # Default basepath for NCM modules
    $self->{COMPONENT_BASE} = $COMPONENT_BASE;

    # check for existing and 'active' in node profile

    # component itself does however not get loaded yet
    # (this is done on demand by the 'execute' commands)

    my $tree = $config->getTree("$COMPONENTS_PROFILE_PATH/$name", 2);
    if (! $tree) {
        $self->error("no such component in node profile: $name");
        return;
    }

    $self->{MODULE} = $tree->{'ncm-module'} || $self->{NAME};

    if ($self->{MODULE} =~ m{^([a-zA-Z_]\w*(?:::[a-zA-Z_]\w*)*)$}) {
        $self->{MODULE} = $1;
    } else {
        throw_error ("Bad module name: $self->{MODULE}");
        return;
    }

    if ($tree->{version}) {
        # version is part of the PMpost maven template
        # be aware of obscure tainting errors (version uses XS); untaint if needed
        my $errmsg = "component $name has invalid version from config $tree->{version} (bug in profile?)";
        my $pattern = '^(v?\d+(?:\.\d+(?:\.\d+)))$';
        if ($tree->{version} =~ m/$pattern/) {
            local $@;
            eval {
                $self->{VERSION_CONFIG} = version->new($1);
            };
            if ($@) {
                $self->error("$errmsg: $@");
                return;
            } else {
                $self->verbose("component $name version from config $self->{VERSION_CONFIG}");
            }
        } else {
            $self->error("$errmsg: does not match regex pattern $pattern");
            return;
        }
    } else {
        $self->verbose("component $name no version from config");
    };

    my $active = $tree->{active};

    if ($active) {
        return ($self->_setDependencies());
    } elsif (defined $active) {
        $self->error("component $name is not active");
        return;
    } else {
        $self->error("component $name 'active' flag not found in node profile");
        return;
    }

}


=item _load

Load the component file in a separate namespace C<< NCM::Component::<name> >>

Returns the component instance on success, undef on failure.

=cut

sub _load
{
    my $self = shift;

    my $mod = $self->module();
    my $name = $self->name();

    my $mod_fn = $self->getComponentFilename();
    if (!$self->hasFile()) {
        # No arguments passed to hasFile
        $self->error("component $mod is not installed (looking for $mod_fn)");
        return;
    }

    local $@;

    my $package = "NCM::Component::$mod";

    eval ("use $package;");
    if ($@) {
        $self->error("bad Perl code in $package ($mod_fn): $@");
        return;
    }

    my $comp_EC;
    eval "\$comp_EC=\$$package\:\:EC;";
    if ($@ || !defined $comp_EC || ref($comp_EC) ne 'LC::Exception::Context') {
        $self->error('bad component exception handler: $EC is not defined, ',
                     'not accessible or not of type LC::Exception::Context',
                     "(note 1: the component package name has to be exactly ",
                     "'$package' - please verify this inside $mod_fn) ",
                     '(note 2: $EC has to be declared in "our (...)")');
        return;
    }

    my $version;
    eval "\$version=\$$package\:\:VERSION;";
    if ($@) {
        $self->verbose("component package $package for $name has no VERSION defined: $@");
    } else {
        $self->{VERSION_PACKAGE} = $version;
    }

    my $component;
    eval {
        $component = $package->new($name, $self);
    };
    if ($@) {
        $self->error("component $mod instantiation statement fails: $@");
        return;
    }

    foreach my $mandatory_method (@COMPONENT_MANDATORY_METHODS) {
        if (! $component->can($mandatory_method)) {
            $self->error("component $mod is missing the mandatory $mandatory_method method");
            return;
        }
    }

    return $component;
}


=item _setDependencies

Reads the dependencies on other components via the NVA API and stores
them internally. They can be recovered by getDependencies()

=cut

sub _setDependencies
{

    my ($self) = @_;

    my $name = $self->name();
    my $tree = $self->{CONFIG}->getTree("$COMPONENTS_PROFILE_PATH/$name/dependencies");

    foreach my $type (qw(pre post)) {
        my @deps = @{$tree->{$type} || []};
        $self->{uc("${type}_deps")} = \@deps;

        my $msg = "$type dependencies for component $name";
        if (@deps) {
            $self->debug(2, "$msg: ", join(',', @deps));
        } else {
            $self->debug(1, "no $msg");
        }
    }

    return SUCCESS;
}


=item _version_check

Apply version related checks.

Return C<SUCCESS> if there are no version-related issues;
report an error and return undef otherwise.

Current version only reports possible different versions,
and always returns C<SUCCESS>
(but behaviour might change in future versions).

=cut

# TODO implement actual policy, part of issue #41

sub _version_check
{
    my ($self) = @_;

    my $cfg = $self->{VERSION_CONFIG};
    my $pkg = $self->{VERSION_PACKAGE};

    if (defined($pkg) && defined($cfg)) {
        if ($pkg != $cfg) {
            $self->verbose("Config version $cfg is different from package version $pkg");
        }
    }

    return SUCCESS;
}


=item _execute

common function for executeConfigure() and executeUnconfigure()

Adds the C<USR1> signal handler (reports the (currently active) component and method)
C<HUP>, C<PIPE> and C<ALRM> signals are ignored during the method execution.

=cut

sub _execute
{
    my ($self, $method) = @_;

    my $name = $self->name();

    # Save environment to restore
    my %ENV_ORIG = %ENV;
    my %SIG_ORIG = %SIG;
    my $pwd = getcwd();
    # Untaint $pwd so we can chdir to it
    # TODO: This will fail is the current directory has a newline in it
    if ($pwd =~ m/^(.*)$/) {
        $pwd = $1;
    } else {
        $self->error("Untainting pwd $pwd failed.");
        return;
    }

    my $res = $self->_execute_dirty($method);

    # restore original env and signals
    %ENV = %ENV_ORIG;
    %SIG = %SIG_ORIG;

    if (chdir($pwd)) {
        $self->debug(1, "Changed back to $pwd after executing component $name method $method");
    } else {
        $self->warn("Fail to change back to $pwd executing component $name method $method");
    };

    return $res;
};

sub _execute_dirty
{
    my ($self, $method) = @_;

    my $name = $self->name();
    my $mod = $self->module();

    # load the component
    my $component = $self->_load();
    unless (defined $component) {
        $self->error("cannot load component: $name");
        return;
    }

    # Just return, reports it's own error/warning/...
    return if ! $self->_version_check();

    # redirect log file to component's log file
    if ($this_app->option('multilog')) {
        my $logfilename = $this_app->option("logdir")."/component-$name.log";
        if (! $self->init_logfile($logfilename, 'at')) {
            $self->error("cannot open component log file: $logfilename");
            return;
        }
    } else {
        $self->set_report_logfile ($this_app->{$LOGFILE});
    }

    # TODO: support multihistory? does that even make sense?
    $self->set_report_history($this_app->{$HISTORY}) if $this_app->option('history');

    $self->log('-----------------------------------------------------------');

    my $noaction_orig = $LC::Check::NoAction;
    if ($this_app->option('noaction')) {
        $LC::Check::NoAction = 1;
        my $compname = $self->{'NAME'};
        my $noact_supported = undef;
        eval "\$noact_supported=\$NCM::Component::$mod\:\:NoActionSupported;";
        if ($@ || !defined $noact_supported || !$noact_supported) {
            # noaction is not supported by the component, skip
            # execution in fake mod
            $self->info("component $compname (implemented by $mod) has ",
                        "NoActionSupported not defined or false, skipping ",
                        "noaction run");
            my $retval = {
                WARNINGS => 0,
                ERRORS => 0
            };
            return $retval;
        } else {
            $self->info("note: running component $compname in noaction mode");
        }
    }

    # run from /tmp
    if (chdir($RUN_FROM)) {
        $self->debug(1, "Changed to $RUN_FROM before executing component $name method $method");
    } else {
        $self->warn("Fail to change to $RUN_FROM before executing component $name method $method");
    };

    # USR1 reports current active component / method
    $SIG{'USR1'} = sub {
        $self->info("Executing component $name $method");
    };

    # ensure that these signals get ignored
    # (%SIG is redefined by Perl itself sometimes)
    $SIG{$_} = 'IGNORE' foreach qw(HUP PIPE ALRM);

    # execute component
    # TODO: return value $result is unused
    local $@;
    my $result;
    eval "\$result=\$component->$method(\$self->{'CONFIG'});";

    my $formatter = $this_app->option('verbose') || $this_app->option('debug')
        ? "format_long" : "format_short";

    my $retval;
    if ($@) {
        $self->error("component $name executing method $method fails: $@");
    } else {
        my $comp_EC;
        eval "\$comp_EC=\$NCM::Component::$mod\:\:EC;";
        if ($@) {
            # This is checked in _load
            $self->error("No component exception handler for component $name");
        } else {
            if ($comp_EC->error) {
                $self->error("uncaught error exception in component: $name");
                $component->error($comp_EC->error->$formatter());
                $comp_EC->ignore_error();
            }

            if ($comp_EC->warnings) {
                $self->warn("uncaught warning exception in component: $name");
                foreach ($comp_EC->warnings) {
                    $component->warn($_->$formatter());
                }
                $comp_EC->ignore_warnings();
            }
        }

        if ($ec->error) {
            $self->error("error exception thrown by component: $name");
            $component->error($ec->error->$formatter());
            $ec->ignore_error();
        }
        if ($ec->warnings) {
            $self->warn("warning exception thrown by component: $name");
            foreach ($ec->warnings) {
                $component->warn($_->$formatter());
            }
            $ec->ignore_warnings();
        }

        $retval = {
            WARNINGS => $component->get_warnings(),
            ERRORS => $component->get_errors()
        };

        $self->info("configure on component $name executed, ",
                    "$retval->{ERRORS} errors, ",
                    "$retval->{WARNINGS} warnings");

        # TODO: make event_report a mandatory method
        if ($component->can('event_report')) {
            my $idxs = $component->event_report();
            if (defined($idxs)) {
                push(@{$this_app->{REPORTED_EVENTS}}, @$idxs);
            } else {
                $self->warn("Something went wrong with reporting events");
            }
        } else {
            $self->verbose('Cannot report events.')
        }
    }

    # restore logfile and noaction flags
    $self->set_report_logfile($this_app->{'LOG'})
        if ($this_app->option('multilog'));

    $LC::Check::NoAction = $noaction_orig;

    return $retval;
}

=pod

=back

=cut

1;
