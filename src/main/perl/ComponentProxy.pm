# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}


package NCD::ComponentProxy;

use strict;
use vars qw(@ISA $this_app);
use CAF::ReporterMany;
use LC::Exception qw (SUCCESS throw_error);

use CAF::Object;
use EDG::WP4::CCM::CacheManager;
use EDG::WP4::CCM::Path;
use CAF::Log;
use LC::Check;
use NCM::Template;

use File::Path;

*this_app = \$main::this_app;


@ISA=qw(CAF::Object CAF::ReporterMany);


my $_COMP_PREFIX='/software/components';

my $ec=LC::Exception::Context->new->will_store_all;

# default template delimiters (will be restored before running a component)
my @_TEMPLATE_DELIMITERS=NCM::Template->GetDelimiters();

=pod

=head1 NAME

NCD::ComponentProxy - component proxy class

=head1 SYNOPSIS


=head1 INHERITANCE

  CAF::Object, CAF::Reporter

=head1 DESCRIPTION

Provides management functions for accessing and executing NCM
components.

=over

=back

=head1 AUTHOR

German Cancio <German.Cancio@cern.ch>

=head1 VERSION

$Id: ComponentProxy.pm.cin,v 1.34 2008/09/26 15:59:34 munoz Exp $

=cut


#------------------------------------------------------------
#                      Public Methods/Functions
#------------------------------------------------------------

=pod

=back

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

=item hasFile(): boolean

returns 1 if the components perl module is installed, 0 otherwise.

=cut

sub hasFile {
  my $self=shift;

  return -r '/usr/lib/perl/NCM/Component/'.$self->name().'.pm' ? 1:0 ;
}

=pod
=item writeComponent(): boolean

returns 1 if the component has the code defined in the configuration
and has been written to disk, 0 otherwise.  This will erase old
component definitions if the code is no longer defined in the
XML configuration.

=cut

sub writeComponent {

  my $self=shift;

  # Pull out the component name and the configuration.
  my $cname = $self->{'NAME'};
  my $config = $self->{'CONFIG'};

  # Ensure that both the name and configuration are defined.
  unless (defined($cname)) {
      $self->error("internal error: component name not defined");
  }
  unless (defined($config)) {
      $self->error("internal error: component configuration not defined");
  }

  # Base name for component configuration.
  my $base = '/software/components/'.$cname;

  # Determine if the script exists.  If not, then ensure that any
  # files created by previous runs are removed.  This is to avoid
  # interference between old scripts and newer ones installed via
  # a package.  This is needed because there is no hook for
  # cleaning up a script if no 'Unconfigure' method is defined.
  unless ($config->elementExists($base.'/code/script')) {

      # If the script exists, remove it.
      my $fname = "/var/ncm/lib/perl/NCM/Component/$cname.pm";
      if (-e $fname) {
	  unlink $fname;
	  $self->error("error unlinking $fname") if ($?);
      }

      # Remove data directory for this template.
      my $dname = "/var/ncm/config/$cname";
      rmtree($dname,0,1) if (-e $dname);

      return 0;
  }

  # Ensure that the directory for the components exists.
  my $sdir = '/var/ncm/lib/perl/NCM/Component';
  unless (-d $sdir) {
      mkpath($sdir, 0, 0755);
      unless (-d $sdir) {
	  $self->error("cannot create directory: $sdir");
	  return 0;
      }
  }

  # Ensure that the directory for the component data exists.
  my $ddir = '/var/ncm/config/'.$cname;
  unless (-d $ddir) {
      mkpath($ddir, 0, 0755);
      unless (-d $ddir) {
	  $self->error("cannot create directory: $ddir");
	  return 0;
      }
  }

  # Now write the script to the file.
  my $script = $config->getValue($base.'/code/script');
  my $fname = "$sdir/$cname.pm";
  open SCRIPT, '>', "$fname";
  print SCRIPT $script;
  close SCRIPT;

  # Check if there was an error while writing the script.
  if ($?) {
      $self->error("error writing script $fname: $!");
      return 0;
  }

  # Write out data files if specified.
  if ($config->elementExists($base.'/code/data')) {
      my $dhash = $config->getElement($base.'/code/data');
      while ($dhash->hasNextElement()) {
	  my $entry = $dhash->getNextElement();
	  my $fname = $entry->getName();
	  my $contents = $config->getValue($base.'/code/data/'.$fname);

	  # Now write the script to the file.
	  open DATA, '>', "$ddir/$fname";
	  print DATA $contents;
	  close DATA;

	  # Check if there was an error while writing the script.
	  if ($?) {
	      $self->error("error writing data file $ddir/$fname: $!");
	      return 0;
	  }
      }
  }

  return 1;
}

=pod

=head2 Private methods

=item _initialize($comp_name, $config)

object initialization (done via new)

=cut

sub _initialize {
  my ($self,$name,$config)=@_;
  $self->setup_reporter();
  unless (defined $name && defined $config) {
    throw_error('bad initialization');
    return undef;
  }

  unless ($name =~ m{^([a-zA-Z_]\w+)$}) {
    throw_error ("Bad component name: $name");
    return undef;
  }

  $self->{'NAME'}=$1;
  $self->{'CONFIG'}=$config;

  # check for existing and 'active' in node profile

  # component itself does however not get loaded yet (this is done on demand
  # by the 'execute' commands)

  my $cdb_entry=$self->{'CONFIG'}->getElement('/software/components/'.$name);
  unless (defined $cdb_entry) {
    $ec->ignore_error();
    $self->error('no such component in node profile: '.$name);
    return undef;
  }

  my $prop=$config->getElement($_COMP_PREFIX.'/'.$name.'/active');
  unless (defined $prop) {
    $ec->ignore_error();
    $self->error('component '.$name.
		 " 'active' flag not found in node profile");
    return undef;
  } else {
    my $active=$prop->getBooleanValue();
    if ($active ne 'true') {
      $self->error('component '.$name.' is not active');
      return undef;
    }

    return ($self->_setDependencies());
  }
}


=pod

=item _load(): boolean

loads the component file in a separate namespace (NCM::Component::$name)

=cut

sub _load {
  my $self=shift;

  my $compname=$self->{'NAME'};

  # try to create the component from configuration information
  # or check that it is pre-installed
  if (!$self->writeComponent()) {
      unless ($self->hasFile()) {
	  $self->error('component '.$compname.' is not installed in /var/ncm/lib/perl/NCM/Component or /usr/lib/perl/NCM/Component');
	  return undef;
      }
  }

  eval ("use NCM::Component::$compname;");
  if ($@) {
    $self->error("bad Perl code in NCM::Component::$compname : $@");
    return undef;
  }

  my $comp_EC;
  eval "\$comp_EC=\$NCM::Component::$compname\:\:EC;";
  if ($@ || !defined $comp_EC || ref($comp_EC) ne 'LC::Exception::Context') {
    $self->error('bad component exception handler: $EC is not defined, not accessible or not of type LC::Exception::Context');
    $self->error("(note 1: the component package name has to be exactly 'NCM::Component::$compname' - please verify this inside '/usr/lib/perl/NCM/Component/$compname.pm' or '/var/ncm/lib/perl/NCM/Component/$compname.pm')");
    $self->error('(note 2: $EC has to be declared in "use vars (...)")');
    return undef;
  }

  my $component;
  eval("\$component=NCM::Component::$compname->new(\$compname, \$self)");
  if ($@) {
    $self->error("component $compname instantiation statement fails: $@");
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

  $self->{'PRE_DEPS'}=[()];
  $self->{'POST_DEPS'}=[()];

  my $conf=$self->{'CONFIG'};

  my $pre_path = $_COMP_PREFIX.'/'.$self->{'NAME'}.'/dependencies/pre';
  my $post_path = $_COMP_PREFIX.'/'.$self->{'NAME'}.'/dependencies/post';


  # check if paths are defined (otherwise, no dependencies)


  my $res=$conf->getElement($pre_path);
  if (defined $res) {
    my $el;
    foreach $el ($res->getList()) {
      push (@{$self->{'PRE_DEPS'}},$el->getStringValue());
    }
    $self->debug(2,'pre dependencies for component '.$self->{'NAME'}.
		 ' '.join(',',@{$self->{'PRE_DEPS'}}));
  } else {
    $ec->ignore_error();
    $self->debug(1,'no pre dependencies found for '.$self->{'NAME'});
  }

  $res=$conf->getElement($post_path);
  if (defined $res) {
    my $el;
    foreach $el ($res->getList()) {
      push (@{$self->{'POST_DEPS'}},$el->getStringValue());
    }
    $self->debug(2,'post dependencies for component '.$self->{'NAME'}.
		 ' '.join(',',@{$self->{'POST_DEPS'}}));
  } else {
    $ec->ignore_error();
    $self->debug(1,'no post dependencies found for '.$self->{'NAME'});
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
    eval "\$noact_supported=\$NCM::Component::$compname\:\:NoActionSupported;";
    if ($@ || !defined $noact_supported || !$noact_supported) {
      # noaction is not supported by the component, skip execution in fake mod
      $self->info("component $compname has NoActionSupported not defined or to false, skipping noaction run");
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
  NCM::Template->SetDelimiters(@_TEMPLATE_DELIMITERS);
  my %ENV_BK=%ENV;
  # ensure that these signals get ignored
  # (%SIG is redefined by Perl itself sometimes)
  $SIG{$_}='IGNORE' foreach qw(HUP PIPE ALRM);

  # go and run the component
  eval "\$result=\$component->$method(\$self->{'CONFIG'});";

  %ENV=%ENV_BK; # restore env and signals
  if ($@) {
    $self->error("component ".$name.
		" executing method $method fails: $@");
    $retval=undef;
  } else {

    my $comp_EC;
    eval "\$comp_EC=\$NCM::Component::$name\:\:EC;";
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

    $self->info('configure on component '.$component->name().' executed, '.
		$component->get_errors(). ' errors, '.
		$component->get_warnings(). ' warnings');
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





#+#############################################################################
1;

