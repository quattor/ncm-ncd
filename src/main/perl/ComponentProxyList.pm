# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}

package NCD::ComponentProxyList;

use strict;
use LC::Exception qw (SUCCESS throw_error);
use parent qw(CAF::Object CAF::ReporterMany);
use NCD::ComponentProxy;

our $this_app;

*this_app = \$main::this_app;

my $ec=LC::Exception::Context->new->will_store_errors;



=pod

=head1 NAME

NCD::ComponentProxyList - component proxy list class

=head1 SYNOPSIS


=head1 INHERITANCE

  CAF::Object, CAF::Reporter

=head1 DESCRIPTION

Instantiation, execution and management of ComponentProxy object instances.

=over

=back

=head1 AUTHOR

German Cancio <German.Cancio@cern.ch>

=head1 VERSION

$Id: ComponentProxyList.pm.cin,v 1.17 2008/10/21 15:54:53 munoz Exp $

=cut


#------------------------------------------------------------
#                      Public Methods/Functions
#------------------------------------------------------------

=pod

=back

=head2 Public methods

=over 4

=cut


sub reportComponents {
  my $self=shift;

  $self->report('active components found inside profile /software/components:');
  $self->report(sprintf("%-15s%-7s%-29s%-29s","name","file?","predeps","postdeps"));
  $self->report("-------------------------------------------------------------------");
  my $comp;
  foreach $comp (@{$self->{'CLIST'}}) {
    $self->report(sprintf("%-15s%-7s%-29s%-29s",$comp->name().':',
		  ($comp->hasFile() ? "yes":"no"),
		  join(',',@{$comp->getPreDependencies()}),
		  join(',',@{$comp->getPostDependencies()})
		  ));
  }
  return SUCCESS;
}

#
#
#
sub pre_config_actions
{
    my $self = shift;
}

sub post_config_actions
{
    my ($self, $report) = @_;
}

sub executeConfigComponents {
  my $self=shift;

  $self->info("executing configure on components....");
  $self->report();

  $self->pre_config_actions();

  my %err_comps_list;
  my %warn_comps_list;
  my %global_status=(
		     'ERRORS'=>0,
		     'WARNINGS'=>0
		    );

  my $sortedList=$self->_sortComponents($self->{'CLIST'});
  unless (defined $sortedList) {
    $self->error("cannot sort components according to dependencies");
    $global_status{'ERRORS'}++;
  } else {
    # execute now all components, leaving out ones with broken pre deps

    my $OK=1;
    my $FAIL=2;
    my %exec_status=map {$_->name(),0} @{$sortedList};

    my $comp;
    foreach $comp (@{$sortedList}) {
      $self->report();
      $self->info('running component: '.$comp->name());
      $self->report('---------------------------------------------------------');
      my @broken_dep=();
      my $predep;
      foreach $predep (@{$comp->getPreDependencies()}) {
	if (!$this_app->option('nodeps') &&
	    $exec_status{$predep} != $OK) {
	  push (@broken_dep,$predep);
	  $self->debug(1, 'predependencies broken for component '.$comp->name().': '.$predep);
	}
      }
      if (scalar @broken_dep) {
        my $err = 'cannot run component: '.$comp->name().
          ' as pre-dependencies failed: '.join(',',@broken_dep);
        $self->error($err);
	$global_status{'ERRORS'}++;
	$err_comps_list{$comp->name()}=1;
        $self->set_state($comp->name(), $err);
      } else {
        # we set the state to "unknown" (in effect) just before we
        # run configure, so that the state will reflect that this component
        # has still not run to completion. All code-paths following this
        # MUST either set_state or clear_state.
        $self->set_state($comp->name(), "");

	my $ret=$comp->executeConfigure();
	unless (defined $ret) {
          my $err = "cannot execute configure on component " . $comp->name();
          $self->error($err);
	  $global_status{'ERRORS'}++;
	  $err_comps_list{$comp->name()}=1;
	  $exec_status{$comp->name()}=$FAIL;
          $self->set_state($comp->name(), $err);
	} else {
	  if ($ret->{'ERRORS'}) {
	    $err_comps_list{$comp->name()}=$ret->{'ERRORS'};
	    $exec_status{$comp->name()}=$FAIL;
            $self->set_state($comp->name(), $ret->{ERRORS});
	  } else {
	    $exec_status{$comp->name()}=$OK;
            $self->clear_state($comp->name());
	  }
	  if ($ret->{'WARNINGS'}) {
	    $warn_comps_list{$comp->name()}=$ret->{'WARNINGS'};
          }

	  $global_status{'ERRORS'}   += $ret->{'ERRORS'};
	  $global_status{'WARNINGS'} += $ret->{'WARNINGS'};
	}
      }
    }
  }

  $global_status{'ERR_COMPS'}=\%err_comps_list;
  $global_status{'WARN_COMPS'}=\%warn_comps_list;

  $self->post_config_actions(\%global_status);

  return \%global_status;
}

sub get_statefile {
    my ($self, $comp) = @_;
    if ($this_app->option('state')) {
       my $file = $this_app->option('state') . '/' . $comp;
       if ($file =~ m{^(\/[^\|<>&]*)$}) {
           # Must be an absolute path, no shell metacharacters
           return $1;
       } else {
           $self->warn("state filename $file is inappropriate");
           # Don't touch the state file
           return undef;
       }
    }
    return undef;
}

# Mark a component as failed within our state directory
sub set_state {
    my ($self, $comp, $msg) = @_;
    if ($this_app->option('noaction')) {
       if (!$msg) {
           $self->info("would mark state of component as needing to run");
       } else {
           $self->info("would mark state of component as '$msg'");
       }
       return;
    }
    my $file = $self->get_statefile($comp);
    if ($file) {
       if (open(TOUCH, ">$file")) {
           print TOUCH "$msg\n";
           close(TOUCH);
       } else {
           $self->warn("failed to write state file $file: $!");
       }
    }
}


# Mark a component as succeeded within our state directory
sub clear_state {
    my ($self, $comp) = @_;
    if ($this_app->option('noaction')) {
       $self->info("would mark state of component as success");
       return;
    }
    my $file = $self->get_statefile($comp);
    if ($file) {
       unlink($file) or $self->warn("failed to clean state $file: $!");
    }
}

sub executeUnconfigComponent {
  my $self=shift;

  my $comp=@{$self->{'CLIST'}}[0];

  my %global_status=(
		     'ERRORS'=>0,
		     'WARNINGS'=>0
		    );

  unless (defined $comp) {
    $self->error('could not instantiate component');
    $global_status{'ERRORS'}++;
  } else {
    my $ret=$comp->executeUnconfigure();
    unless (defined $ret) {
      $self->error('cannot execute unconfigure on component '.$comp->name());
      $global_status{'ERRORS'}++;
    } else {
      $self->report('unconfigure on component '.$comp->name().' executed, '.
		    $ret->{'ERRORS'}. ' errors, '.
		    $ret->{'WARNINGS'}. ' warnings');
      $global_status{'ERRORS'}   += $ret->{'ERRORS'};
      $global_status{'WARNINGS'} += $ret->{'WARNINGS'};
    }
  }
  return \%global_status;
}



# protected methods


# topological Sort
# preliminary mkxprof based version, to be replaced by a
# qsort call in the next alpha release.
#
sub _topoSort {
  # Topological sort (Aho, Hopcroft & Ullman)

  my $self=shift;
  my $v = shift;         # Current vertex
  my $after = shift;     # Hash of component followers
  my $visited = shift;   # Visited markers
  my $active = shift;    # Components on this path (to check for loops)
  my $stack = shift;     # Output stack
  my $depth = shift;     # Depth

  return SUCCESS if ($visited->{$v});
  $visited->{$v} = $active->{$v} = $depth;
  foreach my $n (keys(%{$after->{$v}})) {
    if ($active->{$n}) {
      my @loop = sort { $active->{$a} <=> $active->{$b} } keys(%$active);
      $self->error("dependency ordering loop detected: ",
		join(' < ',(@loop,$n)));
      return undef;
    }
    return undef unless
	($self->_topoSort($n,$after,$visited,$active,$stack,$depth+1));
  }
  delete $active->{$v}; unshift @$stack,($v);
  return SUCCESS;
}

#
# sort the components according to dependencies
#
sub _sortComponents
{
    my ($self,$unsortedcompProxyList)=@_;

    $self->verbose("sorting components according to dependencies...");

    my %comps;
    %comps=map {$_->name(),$_} @$unsortedcompProxyList;
    my $after={};
    foreach my $comp (@$unsortedcompProxyList) {
        my $name=$comp->name();
        $after->{$name} ||= {};
        my @pre=@{$comp->getPreDependencies()};
        my @post=@{$comp->getPostDependencies()};
        foreach my $p (@pre) {
            if (defined $comps{$p}) {
                $after->{$p}->{$name} = 1;
            } elsif (!$this_app->option('nodeps')) {
                $self->error(qq{pre-requisite for component "$name" does not exist: $p});
                return undef;
            }
        }
        foreach my $p (@post) {
            if (!defined $comps{$p} && ! $this_app->option('nodeps')) {
                $self->error(qq{post-requisite for component "$name"  does not exist: $p});
                return undef;
            }
            $after->{$name}->{$p}=1;
        }
    }
    my $visited={};
    my $sorted=[()];
    foreach my $c (sort keys (%$after)) {
        unless ($self->_topoSort($c,$after,$visited,{},$sorted,1)) {
            $self->error("cannot sort dependencies");
            return undef;
        }
    }
    my @sortedcompProxyList=map {$comps{$_}} @$sorted;
    return \@sortedcompProxyList;
}




#
# _getComponents(): boolean
# instantiates the list of components specified in new(). If
# the list is empty, returns all components flagged as 'active'
#

sub _getComponents {
  my ($self,$list)=@_;

  my @compnames=@{$self->{'NAMES'}};

  unless (scalar (@compnames)) {
    my $res=$self->{'CCM_CONFIG'}->getElement('/software/components');
    unless (defined $res) {
      $ec->ignore_error();
      $self->error("no components found in profile");
      return undef;
    }
    my $cname;
    my %els=$res->getHash();
    foreach $cname (keys %els) {
      my $prop=$self->{'CCM_CONFIG'}->getElement('/software/components/'.$cname.'/active');
      unless (defined $prop) {
	$ec->ignore_error();
	$self->warn('component '.$cname.
		     " 'active' flag not found in node profile under /software/components/".$cname."/, skipping");
	next;
      } else {
	if ($prop->getBooleanValue() eq 'true') {
	  push(@compnames,$cname);
	}
      }
    }
    $self->verbose('active components found in profile: ');
    $self->verbose('  '.join(',',@compnames));
  }

  unless (scalar @compnames) {
    $self->error('no active components found in profile');
    return undef;
  }

  my @skiplist;
  if (defined $self->{'SKIP'}) {
    chomp($self->{'SKIP'});
    @skiplist = split(/,/,$self->{'SKIP'});
    foreach my $skipcomp (@skiplist){
      chomp ($skipcomp);
      if (grep ($_ eq $skipcomp, @compnames)) {
        $self->info('skip option set - skipping component: '.$skipcomp);
        @compnames = grep ($_ ne $skipcomp, @compnames);
      } else {
        $self->info('skip option set - but component to be skipped '.
		  'not found in active list: '
		  .$skipcomp);
      }
    }
  }

  my @comp_proxylist=();
  my $cname;
  foreach $cname (@compnames) {
    my $comp_proxy=NCD::ComponentProxy->new($cname,$self->{'CCM_CONFIG'});
    unless (defined $comp_proxy) {
      $ec->ignore_error();
      unless ($this_app->option('allowbrokencomps') eq 'yes') {
	$self->error('cannot instantiate component: '.$cname);
	return undef;
      } else {
	$self->warn('ignoring broken component: '.$cname);
      }
    } else {
      push(@comp_proxylist,$comp_proxy);
      my @pre=@{$comp_proxy->getPreDependencies()};
      my @post=@{$comp_proxy->getPostDependencies()};
      my $pp;
      foreach $pp (@pre,@post) {
	unless (grep {$pp eq $_} @compnames) {
	  if ($this_app->option('autodeps') eq 'yes') {
	    if (@skiplist && grep{$pp eq $_} @skiplist) {
	      $self->warn('skipping requested component: '.$cname);
	    } else {
	      push(@compnames,$pp);
	      $self->info("adding missing pre/post requisite component: ".$pp);
	    }
	  }
	}
      }
    }
  }
  $self->{'CLIST'} = \@comp_proxylist;
  return SUCCESS;
}



=pod

=head2 Private methods

=item _initialize($skip,@comp_names)

object initialization (done via new)

=cut

sub _initialize {
  my ($self,$config,$skip,@names)=@_;
  $self->{'CCM_CONFIG'}=$config;
  $self->{'SKIP'}=$skip;
  $self->{'NAMES'}=\@names;


  return $self->_getComponents();
}



#+#############################################################################
1;
3
