# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}


package NCD::ComponentProxy;

use strict;
use LC::Exception qw (SUCCESS throw_error);

use parent qw(CAF::ReporterMany CAF::Object);
use EDG::WP4::CCM::CacheManager;
use EDG::WP4::CCM::Path;
use CAF::Log;
use LC::Check;

use File::Path;

our $this_app;
*this_app = \$main::this_app;


my $_COMP_PREFIX='/software/components';

my $ec=LC::Exception::Context->new->will_store_all;

use constant COMPONENT_BASE => "/usr/lib/perl/NCM/Component";

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

=item executeConfigure(): ref(hash)

executeConfigure loads and executes the component with
'configure'. the number of produced errors and warnings is returned in
a hash ('ERRORS','WARNINGS'). If the component cannot be executed,
undef is returned.

=cut

sub executeConfigure {
    my $self=shift;

    return $self->_execute('Configure');
}


=pod

=item executeUnconfigure(): ref(hash)

executeUnconfigure loads and executes the component with
'unconfigure'. the number of produced errors and warnings is returned
in a hash ('ERRORS','WARNINGS'). If the component cannot be executed,
undef is returned.


=cut

sub executeUnconfigure {
    my $self=shift;

    return $self->_execute('Unconfigure');

}


=pod

=item name(): string

returns the name of the component

=cut

sub name {
    my $self=shift;
    return $self->{'NAME'};
}

=pod

=item module(): string

returns the module to be loaded for executing the component

=cut

sub module {
    my $self = shift;
    return $self->{MODULE};
}


=pod

=item getPreDependencies(): ref(@array)

returns an array to the names of predependent components. The array is
empty if no predependencies are found.

=cut

sub getPreDependencies {
    my $self=shift;

    return $self->{'PRE_DEPS'};
}

=pod

=item getPostDependencies(): ref(@array)

returns an array to the names of postdependent components. The array is
empty if no postdependencies are found.

=cut

sub getPostDependencies {
    my $self=shift;

    return $self->{'POST_DEPS'};
}

=pod

=item getComponentFilename()

Returns the absolute filename of the components perl module.

Receives an optional parameter with the base directory where the Perl
module should be looked for.

=cut

sub getComponentFilename {
    my ($self, $base) = @_;

    $base ||= $self->{'COMPONENT_BASE'};

    my $mod = $self->module();
    $mod =~ s{::}{/}g;

    my $fn = "$base/$mod.pm";
    $fn =~ s{//+}{/}g;

    return $fn;
}


=pod

=item hasFile(): boolean

returns 1 if the components perl module is installed, 0 otherwise.

Receives an optional parameter with the base directory where the Perl
module should be looked for.

=cut

sub hasFile {
    my ($self, $base) = @_;

    my $filename = $self->getComponentFilename($base);

    return -r $filename ? 1:0 ;
}

=back

=head2 Private methods

=over

=item _initialize($comp_name, $config)

object initialization (done via new)

=cut

sub _initialize {
    my ($self,$name,$config)=@_;
    $self->setup_reporter();

    if (!defined($name) || !defined($config)) {
        throw_error('bad initialization');
        return undef;
    }

    if ($name !~ m{^([a-zA-Z_]\w+)$}) {
        throw_error ("Bad component name: $name");
        return undef;
    }

    $self->{'NAME'}=$1;
    $self->{'CONFIG'}=$config;

    # Default basepath for NCM modules
    $self->{'COMPONENT_BASE'} = COMPONENT_BASE;

    # check for existing and 'active' in node profile

    # component itself does however not get loaded yet (this is done on demand
    # by the 'execute' commands)

    my $cdb_entry=$config->getElement("$_COMP_PREFIX/$name");
    if (!defined($cdb_entry)) {
        $ec->ignore_error();
        $self->error('no such component in node profile: '.$name);
        return undef;
    }

    $self->{MODULE} = $config->elementExists("$_COMP_PREFIX/$name/ncm-module") ?
            $config->getElement("$_COMP_PREFIX/$name/ncm-module")->getValue() :
            $self->{NAME};

    if ($self->{MODULE} !~ m{^([a-zA-Z_]\w*(?:::[a-zA-Z_]\w*)*)$}) {
        throw_error ("Bad module name: $self->{MODULE}");
        return undef;
    }
    $self->{MODULE} = $1;

    my $prop=$config->getElement("$_COMP_PREFIX/$name/active");
    if (defined ($prop)) {
        my $active=$prop->getBooleanValue();
        if ($active ne 'true') {
            $self->error("component $name is not active");
            return undef;
        }
        return ($self->_setDependencies());
    } else {
        $ec->ignore_error();
        $self->error("component $name 'active' flag not found in node profile");
        return undef;
    }
}


=pod

=item _load(): boolean

loads the component file in a separate namespace (NCM::Component::$name)

=cut

sub _load {
    my $self=shift;

    my $mod = $self->module();
    my $name = $self->name();

    my $mod_fn = $self->getComponentFilename();
    if (!$self->hasFile()) {
        # No arguments passed to hasFile
        $self->error("component $mod is not installed ",
                     "(looking for $mod_fn)");
        return undef;
    }

    my $package = "NCM::Component::$mod";

    eval ("use $package;");
    if ($@) {
        $self->error("bad Perl code in $package ($mod_fn): $@");
        return undef;
    }

    my $comp_EC;
    eval "\$comp_EC=\$$package\:\:EC;";
    if ($@ || !defined $comp_EC || ref($comp_EC) ne 'LC::Exception::Context') {
        $self->error('bad component exception handler: $EC is not defined, ',
                     'not accessible or not of type LC::Exception::Context',
                     "(note 1: the component package name has to be exactly ",
                     "'$package' - please verify this inside $mod_fn) ",
                     '(note 2: $EC has to be declared in "our (...)")');
        return undef;
    }

    my $component;
    eval("\$component=$package->new(\$name, \$self)");
    if ($@) {
        $self->error("component $mod instantiation statement fails: $@");
        return undef;
    }
    return $component;
}


=pod

=item _setDependencies(): boolean

Reads the dependencies on other components via the NVA API and stores
them internally. They can be recovered by getDependencies()

=cut

sub _setDependencies {

    my ($self)=@_;

    $self->{PRE_DEPS}=[()];
    $self->{POST_DEPS}=[()];

    my $conf=$self->{CONFIG};

    my $pre_path = "$_COMP_PREFIX/$self->{NAME}/dependencies/pre";
    my $post_path = "$_COMP_PREFIX/$self->{NAME}/dependencies/post";


    # check if paths are defined (otherwise, no dependencies)


    my $res=$conf->getElement($pre_path);
    if (defined $res) {
        foreach my $el ($res->getList()) {
            push (@{$self->{'PRE_DEPS'}},$el->getStringValue());
        }
        $self->debug(2, "pre dependencies for component $self->{'NAME'}: ",
                     join(',',@{$self->{PRE_DEPS}}));
    } else {
        $ec->ignore_error();
        $self->debug(1, "no pre dependencies found for $self->{NAME}");
    }

    $res=$conf->getElement($post_path);
    if (defined $res) {
        my $el;
        foreach $el ($res->getList()) {
            push (@{$self->{'POST_DEPS'}},$el->getStringValue());
        }
        $self->debug(2, "post dependencies for component $self->{NAME}: ",
                     join(',',@{$self->{POST_DEPS}}));
    } else {
        $ec->ignore_error();
        $self->debug(1, "no post dependencies found for $self->{NAME}");
    }
    return SUCCESS;
}



=pod

=item _execute

common function for executeConfigure() and executeUnconfigure()

=cut

sub _execute {
    my ($self,$method)=@_;

    # load the component

    my $retval;
    my $name=$self->name();
    my $mod = $self->module();

    local $SIG{'USR1'} = sub {
        $self->info("Executing component $name");
    };

    my $component=$self->_load();
    unless (defined $component) {
        $self->error('cannot load component: '.$name);
        return undef;
    }

    # redirect log file to component's log file
    if ($this_app->option('multilog')) {
        my $logfile=$this_app->option("logdir").'/component-'.$name.'.log';
        my $objlog=CAF::Log->new($logfile,'at');
        unless (defined $objlog) {
            $self->error('cannot open component log file: '.$logfile);
            return undef;
        }
        $self->set_report_logfile($objlog);
    } else {
        $self->set_report_logfile ($this_app->{LOG});
    }

    $self->log('-----------------------------------------------------------');

    my $lcNoAct=$LC::Check::NoAction;
    if ($this_app->option('noaction')) {
        $LC::Check::NoAction=1;
        my $compname=$self->{'NAME'};
        my $noact_supported=undef;
        eval "\$noact_supported=\$NCM::Component::$mod\:\:NoActionSupported;";
        if ($@ || !defined $noact_supported || !$noact_supported) {
            # noaction is not supported by the component, skip
            # execution in fake mod
            $self->info("component $compname (implemented by $mod) has ",
                        "NoActionSupported not defined or false, skipping ",
                        "noaction run");
            $retval= {
                'WARNINGS'=>0,
                'ERRORS'=>0
               };
            return $retval;
        } else {
            $self->info("note: running component $compname in noaction mode");
        }
    }

    # execute component
    my $result;
    chdir ('/tmp');
    my %ENV_BK=%ENV;
    # ensure that these signals get ignored
    # (%SIG is redefined by Perl itself sometimes)
    $SIG{$_}='IGNORE' foreach qw(HUP PIPE ALRM);

    # go and run the component
    eval "\$result=\$component->$method(\$self->{'CONFIG'});";

    %ENV=%ENV_BK;               # restore env and signals
    if ($@) {
        $self->error("component $name executing method $method fails: $@");
        $retval=undef;
    } else {
        my $comp_EC;
        eval "\$comp_EC=\$NCM::Component::$mod\:\:EC;";
        unless ($@) {
            if ($comp_EC->error) {
                $self->error('uncaught error exception in component:');
                my $formatter=$this_app->option('verbose') ||
                    $this_app->option('debug') ? "format_long" : "format_short";
                $component->error($comp_EC->error->$formatter());
                $comp_EC->ignore_error();
            }
            if ($comp_EC->warnings) {
                $self->warn('uncaught warning exception in component:');
                my $formatter=$this_app->option('verbose') ||
                    $this_app->option('debug') ? "format_long" : "format_short";
                foreach ($comp_EC->warnings) {
                    $component->warn($_->$formatter());
                }
                $comp_EC->ignore_warnings();
            }
        }

        if ($ec->error) {
            $self->error('error exception thrown by component:');
            my $formatter=$this_app->option('verbose') ||
                $this_app->option('debug') ? "format_long" : "format_short";
            $component->error($ec->error->$formatter());
            $ec->ignore_error();
        }
        if ($ec->warnings) {
            $self->warn('warning exception thrown by component:');
            my $formatter=$this_app->option('verbose') ||
                $this_app->option('debug') ? "format_long" : "format_short";
            foreach ($ec->warnings) {
                $component->warn($_->$formatter());
            }
            $ec->ignore_warnings();
        }

        # future: support a 'fatal' or 'abort' function
        #  if ($component->get_abort()) {
        #    $self->error("fatal error in component execution, aborting...");
        #    return undef;
        #  }

        $self->info("configure on component ", $component->name(),
                    " executed, ", $component->get_errors(), ' errors, ',
                    $component->get_warnings(), ' warnings');
        $retval= {
            'WARNINGS'=>$component->get_warnings(),
            'ERRORS'=>$component->get_errors()
           };
    }
    # restore logfile and noaction flags
    $self->set_report_logfile($this_app->{'LOG'})
            if ($this_app->option('multilog'));
    $LC::Check::NoAction=$lcNoAct;
    return $retval;
}

=pod

=back

=cut

1;
