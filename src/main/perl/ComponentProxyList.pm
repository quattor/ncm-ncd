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
use CAF::FileWriter;
use File::Path qw(mkpath);

our $this_app;

*this_app = \$main::this_app;

my $ec = LC::Exception::Context->new->will_store_errors;

=pod

=head1 NAME

NCD::ComponentProxyList - component proxy list class

=head1 INHERITANCE

  CAF::Object, CAF::Reporter

=head1 DESCRIPTION

Instantiation, execution and management of ComponentProxy object instances.

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

    # nodeps should be implied by the nodepsnoerrors option
    # allow it here explicitly as part of the API
    my $nodepsnoerrors_global = $nodeps && $this_app->option('nodepsnoerrors');

    foreach my $comp (@{$components}) {
        $self->report();
        my $name = $comp->name();
        $self->info("running component: $name");
        $self->report('---------------------------------------------------------');
        my @broken_dep = ();

        # Any component not in NAMES is a pre/post dependency
        # This covers the case where a component in NAMES is a pre/post dependency of another component
        # TODO: what with --all : are all components requested?
        my $is_requested = (grep {$_ eq $name} @{$self->{NAMES}}) ? 1 : 0;
        $self->verbose("$name is ", ($is_requested ? "" : "not")," a requested compoment");

        # if nodepsnoerrors, errors for this component are not global errors, but become warnings
        my $nodepsnoerrors = $nodepsnoerrors_global && (! $is_requested);
        $self->verbose("nodepsnoerrors set for $name (errors will downgraded to warnings)")
            if $nodepsnoerrors;

        # TODO should we remove the requested components?
        #     a failing requested component is not a the same as a failing dependency
        #     (even if the requested component is a dependency of
        #      some other (requested or not) component)
        foreach my $predep (@{$comp->getPreDependencies()}) {
            if (!$nodeps && $status->{ERR_COMPS}->{$predep}) {
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
            if (defined($ret)) {
                # errors before warnings (errors can be downgraded to warnings)
                if ($ret->{'ERRORS'}) {
                     if ($nodepsnoerrors) {
                         # Convert errors in warnings
                         # TODO do we set the state to failed?
                         $self->warn("Errors from $name are downgraded to warnings (nodepsnoerrors is set). ",
                                     "State is not cleared (as something went wrong), but also not set.");
                         $ret->{'WARNINGS'} += $ret->{'ERRORS'};
                    } else {
                        $status->{ERR_COMPS}->{$name} = $ret->{ERRORS};
                        $self->set_state($name, $ret->{ERRORS});

                        $status->{'ERRORS'} += $ret->{'ERRORS'};
                    }
                } else {
                    $self->clear_state($name);
                }

                if ($ret->{'WARNINGS'}) {
                    $status->{WARN_COMPS}->{$name} = $ret->{WARNINGS};

                    $status->{'WARNINGS'} += $ret->{'WARNINGS'};
                }
            } else {
                my $err = "cannot execute configure on component $name";
                $self->error($err);
                $status->{'ERRORS'}++;
                $status->{ERR_COMPS}->{$name} = 1;
                $self->set_state($name, $err);
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
    my $statedir = $this_app->option('state');
    if ($statedir) {
        # remove trailing slashes
        $statedir = s/\/+$//;

        # the state directory could be volative
        mkpath($statedir) unless -d $statedir;

        my $file = "$statedir/$comp";
        if ($file =~ m{^(\/[^\|<>&]*)$}) {

            # Must be an absolute path, no shell metacharacters
            return $1;
        } else {
            $self->warn("state component $comp filename $file is inappropriate");

            # Don't touch the state file
            return undef;
        }
    } else {
        $self->debug(2, "No state directory via state option set");
    }
    return undef;
}

# Mark a component as failed within our state directory
sub set_state
{
    my ($self, $comp, $msg) = @_;
    if ($this_app->option('noaction')) {
        $msg = "needing to run" if (!$msg);
        $self->info("would mark state of component $comp as '$msg' (noaction set)");
        return;
    }

    my $file = $self->get_statefile($comp);
    if ($file) {
        $self->verbose("set_state for component $comp $file (msg $msg)");
        my $fh = CAF::FileWriter->new($file, log => $self);
        if ($fh) {
            print $fh "$msg\n";
            # calling close here will not update timestamp in case of same state
            # so the timestamp will be of first failure with this message, not the last
            # TODO: ok or not?
            my $changed = $fh->close() ? "" : "not";
            $self->verbose("state for component $comp $file $changed changed.");
        } else {
            $self->warn("failed to write state for component $comp file $file: $!");
        }
    }
}

# Mark a component as succeeded within our state directory
# by removing the statefile
sub clear_state
{
    my ($self, $comp) = @_;
    if ($this_app->option('noaction')) {
        $self->info("would mark state of component $comp as success (noaction set)");
        return;
    }

    my $file = $self->get_statefile($comp);
    if ($file) {
        $self->verbose("mark state of component $comp as success, removing statefile $file");
        unlink($file) or $self->warn("failed to clean state of component $comp $file: $!");
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

# Topological sort (Aho, Hopcroft & Ullman)
# preliminary mkxprof based version, to be replaced by a
# qsort call in the next alpha release.
#
# Arguments
#   C<v>: Current vertex
#   C<after>: Hash of component followers
#   C<visited>: Visited markers
#   C<active>: Components on this path (to check for loops)
#   C<stack>: Output stack
#   C<depth>: Depth
#
sub _topoSort
{
    my ($self, $v, $after, $visited, $active, $stack, $depth) = @_;

    return SUCCESS if ($visited->{$v});

    $visited->{$v} = $active->{$v} = $depth;
    foreach my $n (keys(%{$after->{$v}})) {
        if ($active->{$n}) {
            my @loop = sort {$active->{$a} <=> $active->{$b}} keys(%$active);
            $self->error("dependency ordering loop detected: ", join(' < ', (@loop, $n)));
            return;
        }
        return unless ($self->_topoSort($n, $after, $visited, $active, $stack, $depth + 1));
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

    # $sorted can contain components from the dependency resolution in $after
    # that have no proxy (due to e.g. autodeps=0)
    my @sortedcompProxyList = grep {defined($_)} map {$comps{$_}} @$sorted;
    return \@sortedcompProxyList;
}

# Returns a hash with all the Perl modules be executed.
sub get_component_list
{
    my ($self) = @_;

    my %components = $self->get_all_components();
    foreach my $k (keys(%components)) {
        delete $components{$k} if (!$components{$k});
    }

    $self->verbose("Active components in the profile: ", join(", ", keys(%components)));

    return %components;
}

#
# Returns a hash with keys all the Perl modules be executed
# and values if they are active or not.
#
sub get_all_components
{
    my ($self) = @_;

    my $cfg = $self->{CCM_CONFIG};

    my %components;

    my $el = $cfg->getElement("/software/components");
    if (!$el) {
        $ec->ignore_error();
        $self->error("No components found in profile");
        return;
    }

    # depth=3 for components name, active attribute, and value of attribute
    my $t = $el->getTree(3);

    foreach my $cname (keys(%$t)) {
        my $active = $t->{$cname}->{active};

        if (!defined($active)) {
            $self->warn("Active flag not found for component $cname.");
        }

        $components{$cname} = $active;
    }
    $self->verbose("Components in the profile: ", join(", ", keys(%components)));

    return %components;
}

# parse the --skip commandline option as comma-separated array of components to skip
sub _parse_skip_args
{
    my ($skiptxt) = @_;
    my @skip;

    if ($skiptxt) {
        chomp($skiptxt);
        @skip = split(/,/, $skiptxt);
    }

    return \@skip;
}

# given hash reference to all components C<comps>, C<skip_components>
# filters out all componets that are in the SKIP list.
# Returns a hash with keys all components in the SKIP list and values
# whether or not they were skipped (not skipped if not present in C<$comps>).
sub skip_components
{
    my ($self, $comps) = @_;

    my (@skip, @skip_no_comp);
    foreach my $sk (@{$self->{SKIP}}) {
        if (exists($comps->{$sk})) {
            delete($comps->{$sk});
            push(@skip, $sk);
        } else {
            push(@skip_no_comp, $sk);
        }
    }

    $self->info("Skipping components: ", join(",", @skip)) if @skip;
    $self->info("Skipping components (but not defined/active): ", join(",", @skip_no_comp))
        if @skip_no_comp;

    my %to_skip;
    @to_skip{@skip}         = (1) x @skip;
    @to_skip{@skip_no_comp} = (0) x @skip_no_comp;

    return %to_skip;
}

sub missing_deps
{
    my ($self, $proxy, $comps) = @_;

    my @pre  = @{$proxy->getPreDependencies()};
    my @post = @{$proxy->getPostDependencies()};

    my ($ret, @deps);
    my $autodeps = $this_app->option("autodeps");
    my $nodeps = $this_app->option("nodeps");

    foreach my $pp (@pre, @post) {
        if (!exists($comps->{$pp})) {
            if ($autodeps) {
                push(@deps, $pp);
            } elsif ($nodeps) {
                $self->verbose("Not satifying dependency $pp; continuing (nodeps set)");
            } else {
                $ec->ignore_error();
                $self->warn("Not satifying dependency $pp");
                return;
            }
         }
    }
    return (@deps);
}

# Given hash C<comps>, return list of component proxies
# Does a recursive walk through all dependencies
sub get_proxies
{
    my ($self, $comps) = @_;

    my @pxs;

    my @c = keys(%$comps);

    foreach my $comp (@c) {
        my $px = NCD::ComponentProxy->new($comp, $self->{CCM_CONFIG});
        if (!$px) {
            $self->error("Failed to create ComponentProxy for component $comp");
            return;
        }

        my (@deps) = $self->missing_deps($px, $comps);
        # This makes the loop recursive
        # Check on the existsence, not the value
        push(@c, grep(!exists($comps->{$_}), @deps));

        push(@pxs, $px);
        $comps->{$_} = 1 foreach @deps;
    }

    my $msg = " for components " . join(',', keys(%$comps));
    if (@pxs) {
        $self->verbose("Created ", scalar @pxs, " ComponentProxy instances $msg");
    } else {
        $self->error("Failed to create ComponentProxy $msg");
    }
    return @pxs;
}

#
# _getComponents(): boolean
# instantiates the list of components specified in new().
# If the list is empty, instantiates all active components.
#

sub _getComponents
{
    my ($self) = @_;

    my (%comps, $error_msg);
    if (@{$self->{'NAMES'}}) {
        my %all_comps = $self->get_all_components();
        foreach my $name (@{$self->{NAMES}}) {
            if ($all_comps{$name}) {
                $comps{$name} = 1;
            } else {
                # will fail because ComponentProxy instance
                # can only be created with active component
                my $msg = "Inactive";

                if (!defined($all_comps{$name})) {
                    $msg = "Non-existing";
                }
                $self->error("$msg component $name specified");
                return;
            }
        }
        # This should not be needed
        $error_msg = 'No active components for names ' . join(',', @{$self->{NAMES}});
    } else {

        # all active components
        %comps     = $self->get_component_list();
        $error_msg = 'No active components found in profile';
    }

    if (!%comps) {
        $self->error($error_msg);
        return;
    }

    $self->skip_components(\%comps) if @{$self->{SKIP}};

    my @comp_proxylist = $self->get_proxies(\%comps);

    return if (!@comp_proxylist);

    $self->{'CLIST'} = \@comp_proxylist;

    return SUCCESS;
}

=pod

=back

=head2 Private methods

=over

=item _initialize($skip,@comp_names)

object initialization (done via new)

=cut

sub _initialize
{
    my ($self, $config, $skip, @names) = @_;

    $self->{CCM_CONFIG} = $config;
    $self->{SKIP}       = _parse_skip_args($skip);
    $self->{NAMES}      = \@names;
    $self->{CLIST}      = [];

    my $res = $self->_getComponents();
    return $res if (defined($res));

    $self->{CLIST} = undef;
    return SUCCESS;

}

=pod

=back

=cut

1;
