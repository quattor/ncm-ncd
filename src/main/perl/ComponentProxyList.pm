# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

package NCD::ComponentProxyList;

use strict;
use LC::Exception qw (SUCCESS throw_error);
use parent qw(CAF::ReporterMany CAF::Object);
use NCD::ComponentProxy;
use JSON::XS;
use CAF::Process;

our $this_app;

*this_app = \$main::this_app;

my $ec = LC::Exception::Context->new->will_store_errors;

=pod

=head1 NAME

NCD::ComponentProxyList - component proxy list class

=head1 SYNOPSIS


=head1 INHERITANCE

  CAF::Object, CAF::Reporter

=head1 DESCRIPTION

Instantiation, execution and management of ComponentProxy object instances.

=back

=head2 Public methods

=over 4

=cut

sub reportComponents
{
    my $self = shift;

    $self->report('active components found inside profile /software/components:');
    $self->report(sprintf("%-15s%-7s%-29s%-29s", "name", "file?", "predeps", "postdeps"));
    $self->report("-------------------------------------------------------------------");
    my $comp;
    foreach $comp (@{$self->{'CLIST'}}) {
        $self->report(
            sprintf(
                "%-15s%-7s%-29s%-29s",
                $comp->name() . ':',
                ($comp->hasFile() ? "yes" : "no"),
                join(',', @{$comp->getPreDependencies()}),
                join(',', @{$comp->getPostDependencies()})
            )
        );
    }
    return SUCCESS;
}

# Run the pre-config $hook, possibly timing out after $timeout seconds
sub pre_config_actions
{
    my ($self, $hook, $timeout, $comps) = @_;

    return 1 if !$hook;

    my %opts = (log => $self);
    $opts{stdin}   = encode_json($comps) if $comps;
    $opts{timeout} = $timeout            if $timeout;

    my $proc = CAF::Process->new([$hook], %opts);
    $proc->execute();

    if ($?) {
        $self->error("Failed to run pre-hook $self->{PRE_HOOK}");
        return 0;
    }

    return 1;
}

# Run the post_config $hook, maybe timing out after $timeout seconds.
# The $report argument is the summary of errors and warnings, that
# will be serialized to JSON and passed to the hook as its standard
# input.
sub post_config_actions
{
    my ($self, $hook, $timeout, $report) = @_;

    return 1 if !$hook;

    my %opts = (
        log   => $self,
        stdin => encode_json($report)
    );
    $opts{timeout} = $timeout if $timeout;

    my $proc = CAF::Process->new([$hook], %opts);
    $proc->execute();

    if ($?) {
        $self->error("Failed to run post-hook $self->{POST_HOOK}");
        return 0;
    }

    return 1;
}

# Runs all $components, potentially obeying $nodeps.  Fills in $status
# with the results of the executions: which components failed, which
# had warnings, and so on.
sub run_all_components
{
    my ($self, $components, $nodeps, $status) = @_;

    my (%failed_components);

    foreach my $comp (@{$components}) {
        $self->report();
        my $name = $comp->name();
        $self->info("running component: $name");
        $self->report('---------------------------------------------------------');
        my @broken_dep = ();
        foreach my $predep (@{$comp->getPreDependencies()}) {
            if (!$nodeps && exists($status->{ERR_COMPS}->{$predep})) {
                push(@broken_dep, $predep);
                $self->debug(1, "predependencies broken for component $name: $predep");
            }
        }
        if (@broken_dep) {
            my $err =
                "Cannot run component: $name as pre-dependencies failed: " . join(",", @broken_dep);
            $self->error($err);
            $status->{'ERRORS'}++;
            $status->{ERR_COMPS}->{$name} = 1;
            $self->set_state($name, $err);
        } else {

            # we set the state to "unknown" (in effect) just before we
            # run configure, so that the state will reflect that this component
            # has still not run to completion. All code-paths following this
            # MUST either set_state or clear_state.
            $self->set_state($name, "");

            my $ret = $comp->executeConfigure();
            if (!defined($ret)) {
                my $err = "cannot execute configure on component " . $name;
                $self->error($err);
                $status->{'ERRORS'}++;
                $status->{ERR_COMPS}->{$name} = 1;
                $self->set_state($name, $err);
            } else {
                if ($ret->{'ERRORS'}) {
                    $status->{ERR_COMPS}->{$name} = $ret->{ERRORS};
                    $self->set_state($name, $ret->{ERRORS});
                } else {
                    $self->clear_state($name);
                }
                if ($ret->{'WARNINGS'}) {
                    $status->{WARN_COMPS}->{$name} = $ret->{WARNINGS};
                }

                $status->{'ERRORS'}   += $ret->{'ERRORS'};
                $status->{'WARNINGS'} += $ret->{'WARNINGS'};
            }
        }
    }
}

# Executes all the components listed in $self, finding (and adding)
# their pre and post-dependencies, in the correct order.  It will also
# execute the $pre_hook with an optional $pre_timeout and the
# $post_hook with a $post_timeout.
sub executeConfigComponents
{
    my ($self, $pre_hook, $pre_timeout, $post_hook, $post_timeout) = @_;

    $self->info("executing configure on components....");
    $self->report();

    my $global_status = {
        'ERRORS'   => 0,
        'WARNINGS' => 0
    };

    my $sortedList = $self->_sortComponents($self->{'CLIST'});

    my $pre_input = {'components' => [map({name => $_->name()}, @$sortedList)]};

    if (!defined($sortedList)) {
        $self->error("cannot sort components according to dependencies");
        $global_status->{'ERRORS'}++;
    } elsif ($self->pre_config_actions($pre_hook, $pre_timeout, $pre_input)) {
        $self->run_all_components($sortedList, $this_app->option("nodeps"), $global_status);
    } else {
        foreach my $cmp (@$sortedList) {
            $self->set_state($cmp->name(), "Disallowed by policy");
        }
        $global_status->{ERRORS}++;
    }

    if (!$self->post_config_actions($post_hook, $post_timeout, $global_status)) {
        $global_status->{ERRORS}++;
    }

    return $global_status;
}

sub get_statefile
{
    my ($self, $comp) = @_;
    if ($this_app->option('state')) {

        # the state directory could be volative
        mkdir($this_app->option('state')) unless -d $this_app->option('state');
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
sub set_state
{
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
sub clear_state
{
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

sub executeUnconfigComponent
{
    my $self = shift;

    my $comp = @{$self->{'CLIST'}}[0];

    my %global_status = (
        'ERRORS'   => 0,
        'WARNINGS' => 0
    );

    unless (defined $comp) {
        $self->error('could not instantiate component');
        $global_status{'ERRORS'}++;
    } else {
        my $ret = $comp->executeUnconfigure();
        unless (defined $ret) {
            $self->error('cannot execute unconfigure on component ' . $comp->name());
            $global_status{'ERRORS'}++;
        } else {
            $self->report('unconfigure on component '
                    . $comp->name()
                    . ' executed, '
                    . $ret->{'ERRORS'}
                    . ' errors, '
                    . $ret->{'WARNINGS'}
                    . ' warnings');
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
sub _topoSort
{
    # Topological sort (Aho, Hopcroft & Ullman)

    my $self    = shift;
    my $v       = shift;    # Current vertex
    my $after   = shift;    # Hash of component followers
    my $visited = shift;    # Visited markers
    my $active  = shift;    # Components on this path (to check for loops)
    my $stack   = shift;    # Output stack
    my $depth   = shift;    # Depth

    return SUCCESS if ($visited->{$v});
    $visited->{$v} = $active->{$v} = $depth;
    foreach my $n (keys(%{$after->{$v}})) {
        if ($active->{$n}) {
            my @loop = sort {$active->{$a} <=> $active->{$b}} keys(%$active);
            $self->error("dependency ordering loop detected: ", join(' < ', (@loop, $n)));
            return undef;
        }
        return undef
            unless ($self->_topoSort($n, $after, $visited, $active, $stack, $depth + 1));
    }
    delete $active->{$v};
    unshift @$stack, ($v);
    return SUCCESS;
}

#
# sort the components according to dependencies
#
sub _sortComponents
{
    my ($self, $unsortedcompProxyList) = @_;

    $self->verbose("sorting components according to dependencies...");

    my %comps;
    %comps = map {$_->name(), $_} @$unsortedcompProxyList;
    my $after = {};
    foreach my $comp (@$unsortedcompProxyList) {
        my $name = $comp->name();
        $after->{$name} ||= {};
        my @pre  = @{$comp->getPreDependencies()};
        my @post = @{$comp->getPostDependencies()};
        foreach my $p (@pre) {
            if (defined $comps{$p}) {
                $after->{$p}->{$name} = 1;
            } elsif (!$this_app->option('nodeps')) {
                $self->error(qq{pre-requisite for component "$name" does not exist: $p});
                return undef;
            }
        }
        foreach my $p (@post) {
            if (!defined $comps{$p} && !$this_app->option('nodeps')) {
                $self->error(qq{post-requisite for component "$name"  does not exist: $p});
                return undef;
            }
            $after->{$name}->{$p} = 1;
        }
    }
    my $visited = {};
    my $sorted  = [()];
    foreach my $c (sort keys(%$after)) {
        unless ($self->_topoSort($c, $after, $visited, {}, $sorted, 1)) {
            $self->error("cannot sort dependencies");
            return undef;
        }
    }
    my @sortedcompProxyList = map {$comps{$_}} @$sorted;
    return \@sortedcompProxyList;
}

# Returns a hash with all the Perl modules be executed.
sub get_component_list
{
    my ($self) = @_;

    my $cfg = $self->{CCM_CONFIG};

    my %modules;

    my $el = $cfg->getElement("/software/components");
    if (!$el) {
        $ec->ignore_error();
        $self->error("No components found in profile");
        return;
    }

    my %cmps = $el->getHash();

    foreach my $cname (keys(%cmps)) {
        my $active = $cfg->getElement("/software/components/$cname/active");

        if (!$active) {
            $ec->ignore_error();
            $self->warning("Active flag not found for component $cname. Skipping");
            next;
        }

        next if $active->getValue() ne 'true';

        $modules{$cname} = 1;
    }

    $self->verbose("Active components in the profile: ", join(", ", keys(%modules)));
    return %modules;
}

sub skip_components
{
    my ($self, $comps) = @_;

    my @skp = split(/,/, $self->{SKIP});
    my %to_skip = map(($_ => 1), @skp);

    $self->info("Skipping: ", join(",", @skp));

    foreach my $sk (keys(%to_skip)) {
        delete($comps->{$sk});
    }
    return %to_skip;
}

sub missing_deps
{
    my ($self, $proxy, $comps) = @_;

    my @pre  = @{$proxy->getPreDependencies()};
    my @post = @{$proxy->getPostDependencies()};

    my ($ret, @deps);
    my $autodeps = $this_app->option("autodeps");

    foreach my $pp (@pre, @post) {
        if (!exists($comps->{$pp})) {
            if (!$autodeps) {
                $ec->ignore_error();
                $self->warn("Not satifying dependency $pp");
                return;
            }
            push(@deps, $pp);
        }
    }
    return (@deps);
}

sub get_proxies
{
    my ($self, $comps) = @_;

    my @pxs;

    my @c = keys(%$comps);
    foreach my $comp (@c) {
        my $px = NCD::ComponentProxy->new($comp, $self->{CCM_CONFIG});
        if (!$px) {
            $self->info("Skipping component $comp");
            next;
        }
        my (@deps) = $self->missing_deps($px, $comps);

        push(@pxs, $px);
        push(@c, grep(!exists($comps->{$_}), @deps));
        $comps->{$_} = 1 foreach @deps;
    }
    return @pxs;
}

#
# _getComponents(): boolean
# instantiates the list of components specified in new(). If
# the list is empty, returns all components flagged as 'active'
#

sub _getComponents
{
    my ($self) = @_;

    my %comps = map(($_ => 1), @{$self->{'NAMES'}});

    %comps = $self->get_component_list() if !%comps;

    if (!%comps) {
        $self->error('no active components found in profile');
        return undef;
    }

    $self->skip_components(\%comps) if $self->{SKIP};

    my @comp_proxylist = $self->get_proxies(\%comps);

    $self->{'CLIST'} = \@comp_proxylist;
    return SUCCESS;
}

=pod

=head2 Private methods

=item _initialize($skip,@comp_names)

object initialization (done via new)

=cut

sub _initialize
{
    my ($self, $config, $skip, @names) = @_;
    $self->{'CCM_CONFIG'} = $config;
    $self->{'SKIP'}       = $skip;
    chomp($self->{SKIP}) if $skip;
    $self->{'NAMES'} = \@names;

    return $self->_getComponents();
}

1;
