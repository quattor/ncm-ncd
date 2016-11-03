#${PMpre} NCD::ComponentProxyList${PMpost}

use CAF::Object qw (SUCCESS throw_error);
use parent qw(CAF::ReporterMany CAF::Object Exporter);
use NCD::ComponentProxy;
use JSON::XS;
use CAF::Process;
use CAF::FileWriter;
use File::Path qw(mkpath);

our @EXPORT_OK = qw(get_statefile set_state);

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
# Returns 1 on success, 0 on failure
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
# Returns 1 on success, 0 on failure
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

    # nodeps should be implied by the ignore-errors-from-dependencies option
    # allow it here explicitly as part of the API
    my $downgrade_dep_errors_global = $nodeps && $this_app->option('ignore-errors-from-dependencies');

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
        $self->verbose("$name is ", ($is_requested ? "" : "not "),"a requested component");

        # if downgrade_dep_errors, errors for this component are not global errors, but become warnings
        # TODO only if this component is not a predependency of any of the requested components
        my $downgrade_dep_errors = $downgrade_dep_errors_global && (! $is_requested);
        $self->verbose("downgrade_dep_errors set for $name (errors will downgraded to warnings)")
            if $downgrade_dep_errors;

        # TODO should we remove the requested components?
        #     a failing requested component is not the same as a failing dependency
        #     (even if the requested component is a dependency of
        #      some other (requested or not) component)
        #
        # getPreDependencies is not recursive, but the error state is passed upwards
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
            $self->_set_state($name, $err);
        } else {

            # we set the state to "unknown" (in effect) just before we
            # run configure, so that the state will reflect that this component
            # has still not run to completion. All code-paths following this
            # MUST either set_state or clear_state.
            $self->_set_state($name, "");

            my $ret = $comp->executeConfigure();
            if (defined($ret)) {
                # errors before warnings (errors can be downgraded to warnings)
                if ($ret->{'ERRORS'}) {
                     if ($downgrade_dep_errors) {
                         # Convert errors in warnings
                         # Clear the state (treat as regular warning)
                         $self->warn("Errors from $name are downgraded to warnings (downgrade_dep_errors is set). ",
                                     "State is cleared");
                         $ret->{'WARNINGS'} += $ret->{'ERRORS'};
                         $self->clear_state($name);
                    } else {
                        $status->{ERR_COMPS}->{$name} = $ret->{ERRORS};
                        $self->_set_state($name, $ret->{ERRORS});

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
                $self->_set_state($name, $err);
            }
        }
    }
}

# Executes all the components listed in $self->{CLIST}, finding (and adding)
# their pre and post-dependencies, in the correct order.  It will also
# execute the $pre_hook with an optional $pre_timeout and the
# $post_hook with a $post_timeout.
sub executeConfigComponents
{
    my ($self, $pre_hook, $pre_timeout, $post_hook, $post_timeout) = @_;

    $self->info("executing configure on components....");
    $self->report();

    my $sortedList = $self->_sortComponents($self->{CLIST});

    my $global_status = {
        ERRORS   => 0,
        WARNINGS => 0,
        # The names of the components on order of execution
        CLIST => [map({name => $_->name()}, @$sortedList)],
    };

    # Make a copy of the global_status CLIST
    my $pre_input = {'components' => [@{$global_status->{CLIST}}]};

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

sub executeUnconfigComponent
{
    my $self = shift;

    my $nr_instances = scalar @{$self->{'CLIST'}};

    my %global_status = (
        'ERRORS'   => 0,
        'WARNINGS' => 0
    );

    if ($nr_instances == 0) {
        $self->error('could not instantiate component');
        $global_status{'ERRORS'}++;
    } else {
        my $comp = @{$self->{'CLIST'}}[0];
        my $name = $comp->name();
        # TODO increase global_status ERRORS ?
        $self->error("Only one component can be unconfigured at a time; ",
                     "taking the first one $name from proxy instance list ",
                     "($nr_instances instances)")
            if $nr_instances > 1;

        my $ret = $comp->executeUnconfigure();
        unless (defined $ret) {
            $self->error("cannot execute unconfigure on component $name");
            $global_status{'ERRORS'}++;
        } else {
            $self->report("unconfigure on component $name executed, ",
                          $ret->{'ERRORS'}, ' errors, ',
                          $ret->{'WARNINGS'}, ' warnings');
            $global_status{'ERRORS'}   += $ret->{'ERRORS'};
            $global_status{'WARNINGS'} += $ret->{'WARNINGS'};
        }
    }
    return \%global_status;
}


# Private wrapper around unlink for easy mocking in unittest
# (it's not possible to redefine via CORE as it used in the test framework itself)
sub _unlink
{
    my ($self, $file) = @_;
    return unlink($file);
}

# Mark a component as succeeded within our state directory
# by removing the statefile
# (returns undef with noaction option, 1 otherwise)
sub clear_state
{
    my ($self, $comp) = @_;
    my $file = get_statefile($self, $comp, $this_app->option('state'));

    if ($this_app->option('noaction')) {
        $self->info("would mark state of component $comp as success and remove statefile $file (noaction set)");
        return;
    } elsif ($file) {
        $self->verbose("mark state of component $comp as success, removing statefile $file");
        $self->_unlink($file) or $self->warn("failed to clean state of component $comp $file: $!");
    } else {
        $self->debug(2, "No statefile to clear for component $comp");
    }

    return 1;
}


# protected methods

# Topological sort (Aho, Hopcroft & Ullman)
#
# Arguments
#   C<v>: Current vertex
#   C<after>: Hash of component followers
#   C<visited>: Visited markers
#   C<active>: Components on this path (to check for loops)
#   C<stack>: Output stack
#   C<depth>: Depth
sub _topoSort
{
    my ($self, $v, $after, $visited, $active, $stack, $depth) = @_;

    return SUCCESS if ($visited->{$v});

    $visited->{$v} = $active->{$v} = $depth;
    foreach my $n (sort keys(%{$after->{$v}})) {
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

# sort the components according to dependencies
# returns an arrayref with the sorted proxyinstances
sub _sortComponents
{
    my ($self, $unsortedcompProxyList) = @_;

    my $nodeps = $this_app->option('nodeps');

    my %comps = map {$_->name(), $_} @$unsortedcompProxyList;
    $self->verbose("sorting unsorted components according to dependencies: ",
                   join(",", sort keys %comps));

    my $after = {};
    foreach my $comp (@$unsortedcompProxyList) {
        my $name = $comp->name();

        # add itself
        $after->{$name} ||= {};

        foreach my $p (@{$comp->getPreDependencies()}) {
            my $msg = "pre-dependency $p for component $name";
            if (defined $comps{$p}) {
                $self->debug(2, "Found existing $msg, run $name AFTER $p");
                $after->{$p}->{$name} = 1;
            } elsif (!$nodeps) {
                $self->debug(2, "Found non-existing $msg, error (nodeps=$nodeps)");
                $self->error("pre-requisite for component \"$name\" does not exist: $p");
                return undef;
            } else {
                $self->debug(2, "Found non-existing $msg, continue (nodeps=$nodeps)");
            }
        }

        foreach my $p (@{$comp->getPostDependencies()}) {
            my $msg = "post-dependency $p for component $name";
            if (!defined($comps{$p}) && (!$nodeps)) {
                $self->debug(2, "Found non-existing $msg, error (nodeps=$nodeps)");
                $self->error("post-requisite for component \"$name\"  does not exist: $p");
                return undef;
            } else {
                # TODO: This has to be wrong, why is there no check if $comps{$p} is defined?
                # This will happily add non-existing postdeps
                $self->debug(2, "Adding $msg, not checking if it exists (nodeps=$nodeps)");
                $after->{$name}->{$p} = 1;
            }
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
    # that have no proxy (due to e.g. --no-autodeps)
    my @sortedcompProxyList = grep {defined($_)} map {$comps{$_}} @$sorted;
    $self->verbose("returning sorted component proxy list ",
                   join(",", map {$_->name()} @sortedcompProxyList) );
    return \@sortedcompProxyList;
}

# Returns a hash with all active components
# (and these will the Perl modules to execute).
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
    $self->verbose("Components in the profile: ",
                   join(", ", sort keys(%components)));

    return %components;
}

# parse the --skip commandline option as comma-separated
# array of components to skip. Returns array reference of components
# to skip (empty list if none)
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
# filters out all componets that are in the SKIP list
# (i.e. C<$comps> is modidified).
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

# Given hashref C<comps> with components (active or inactive),
# return the list of pre- and/or post-dependencies for
# proxy instance C<proxy> not part of C<comps>
# if autodeps option is set. If the autodeps option is false, either
# log the missing component with nodeps option set
# or log a warning and return undef with nodeps also false.
sub missing_deps
{
    my ($self, $proxy, $comps) = @_;

    my $name = $proxy->name();

    my @pre  = sort @{$proxy->getPreDependencies()};
    my @post = sort @{$proxy->getPostDependencies()};

    my @deps;

    # use '|| 0' to avoid undef
    my $autodeps = $this_app->option("autodeps") || 0;
    my $nodeps = $this_app->option("nodeps") || 0;

    foreach my $pp (@pre, @post) {
        push(@deps, $pp) if (!exists($comps->{$pp}));
    }

    if(! @deps) {
        $self->debug(1, "no missing_deps for component $name");
        return @deps;
    }


    # Missing dependencies
    my $deps_txt = join(",", @deps);
    $self->debug(1, "missing_deps for component $name ",
                 "(autodeps=$autodeps/nodeps=$nodeps): $deps_txt");
    if(!$autodeps) {
        if ($nodeps) {
            # no warning here, nodeps=1
            $self->verbose("Not satisfying dependencies $deps_txt (nodeps=1/autodeps=0)");
            # return empty list to distinguish from undef for unittesting
            @deps = ();
        } else {
            $ec->ignore_error();
            $self->warn("Not satisfying dependencies $deps_txt");
            return;
        }
    }

    return (@deps);
}

# Given hash ref C<comps>, return list of component proxies
# and add missing_deps with state 1 to the C<comps> hashref
# (i.e. the hashref is modified).
# Does a recursive walk through all dependencies.
# Returns undef on (first) failure to create a ComponentProxy instance
# of a component.
sub get_proxies
{
    my ($self, $comps) = @_;

    my @pxs;

    my @c = sort keys(%$comps);
    $self->debug(3, "get_proxies for initial list ", join(',', @c));
    foreach my $comp (@c) {
        my $px = NCD::ComponentProxy->new($comp, $self->{CCM_CONFIG});
        if (!$px) {
            $self->error("Failed to create ComponentProxy for component $comp");
            return;
        }

        my (@deps) = $self->missing_deps($px, $comps);
        if (@deps) {
            $self->debug(2, "Component $comp has missing_deps ",
                         join(',', @deps));


            # Check on the existsence, not the value
            # TODO: isn't this already done by missing deps (making this unnecessary)?
            my @unknown_deps = grep(!exists($comps->{$_}), @deps);
            if (@unknown_deps) {
                $self->debug(2, "Component $comp has unknown missing_deps ",
                             join(',', @unknown_deps));

                # This makes the loop recursive
                push(@c, @unknown_deps);
                $self->debug(3, "get_proxies updated list ", join(',', @c));
            }
        }

        push(@pxs, $px);
        $comps->{$_} = 1 foreach @deps;
    }

    my $msg = "for components " . join(',', sort keys(%$comps));
    if (@pxs) {
        $self->verbose("Created ", scalar @pxs, " ComponentProxy instances $msg");
    } else {
        $self->error("Failed to create ComponentProxy $msg");
    }
    return @pxs;
}

# _getComponents(): boolean
# instantiates the list of components specified in new().
# If the list is empty, instantiates all active components.
# Returns SUCCESS on success, undef on failure.
# CLIST attribute with list of component proxies is set.
# Failures occur when any of the specified components in new()
# is inactive or missing; if no active components exists or if
# a ComponentProxy cannot be instantiated (via get_proxies).
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

    $self->_getComponents();

    return SUCCESS;
}

=item _set_state

Convenience method to wrap around C<set_state> function,
passing C<noaction> and C<statedir> from current options
and using C<self> as logger.

=cut

sub _set_state
{
    my ($self, $comp, $msg) = @_;

    return set_state($self, $comp, $msg, $this_app->option('state'), $this_app->option('noaction'));
}

=pod

=back

=head2 Functions

=over

=item get_statefile

Return the statefile filename for component C<comp> in the
C<statedir>. Statedir is created if it doesn't exist previously
Return undef in case of problem.

First argument is a C<CAF::Reporter> instance for logging.

=cut

sub get_statefile
{
    my ($logger, $comp, $statedir) = @_;

    if ($statedir) {
        # remove trailing slashes
        $statedir =~ s/\/+$//;

        my $file = "$statedir/$comp";
        if ($file =~ m{^(\/[^\|<>&]*)$}) {

            # the state directory could be volatile
            # only create after sanity/taint check
            mkpath($statedir) unless -d $statedir;

            # Must be an absolute path, no shell metacharacters
            return $1;
        } else {
            $logger->warn("state component $comp filename $file is inappropriate");

            # Don't touch the state file
            return;
        }
    } else {
        $logger->debug(2, "No state directory via state option set for component $comp");
    }

    return;
}

=item set_state

Mark a component C<comp> as failed within our state directory
by wrtiting message C<msg> to the statefile in C<statedir>.

Returns undef with C<noaction> argument (from noaction option),
1 otherwise.

First argument is a C<CAF::Reporter> instance for logging.

=cut

sub set_state
{
    my ($logger, $comp, $msg, $statedir, $noaction) = @_;
    if ($noaction) {
        $msg = "needing to run" if ($msg ne '');
        $logger->info("would mark state of component $comp as '$msg' (noaction set)");
        return;
    }

    my $msg_txt = $msg eq '' ? 'no message': "message: $msg";

    my $file = get_statefile($logger, $comp, $statedir);
    if ($file) {
        $logger->verbose("set_state for component $comp $file ($msg_txt)");
        my $fh = CAF::FileWriter->new($file, log => $logger);
        print $fh "$msg\n";
        # calling close here will not update timestamp in case of same state
        # so the timestamp will be of first failure with this message, not the last
        # TODO: ok or not?
        my $changed = $fh->close();

        my $err = $ec->error();
        if(defined($err)) {
            $ec->ignore_error();
            $logger->warn("failed to write state for component $comp file $file: ".$err->reason());
        } else {
            $logger->verbose("state for component $comp $file ", ($changed ? "" : "not "), "changed.");
        }
    } else {
        $logger->debug(2, "No statefile to set for component $comp ($msg_txt)");
    }
    return 1;
}


=pod

=back

=cut

1;
