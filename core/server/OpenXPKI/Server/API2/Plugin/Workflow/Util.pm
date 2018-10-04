package OpenXPKI::Server::API2::Plugin::Workflow::Util;
use Moose;

# Core modules
use English;
use Try::Tiny;

# Project modules
use OpenXPKI::Server::Context qw( CTX );
use OpenXPKI::Connector::WorkflowContext;
use OpenXPKI::MooseParams;
use OpenXPKI::Debug;

=head2 validate_input_params

Validates the given parameters against the field spec of the current activity
and returns

Currently NO check is performed on data types or required fields to not break
old code.

Currently returns the input parameter HashRef on success. Throws an exception
on error.

B<Positional parameters>

=over

=item * C<$workflow> (Str) - workflow type / name

=item * C<$activity> (Str) - workflow activity

=item * C<$params> (HashRef) - parameters to validate

=back

=cut
# TODO - implement check for type and requirement (perhaps using a validator
sub validate_input_params {
    my ($self, $workflow, $activity, $params) = @_;
    $params //= {};

    ##! 2: "check parameters"
    return undef unless scalar keys %{ $params };

    my %fields = map { $_->name => 1 } $workflow->get_action_fields($activity);

    # throw exception on fields not listed in the field spec
    # TODO - perhaps build a filter from the spec and tolerate additonal params
    my $result;
    for my $key (keys %{$params}) {
        if (not exists $fields{$key}) {
            OpenXPKI::Exception->throw (
                message => "Illegal parameter given for workflow activity",
                params => {
                    workflow => $workflow->type,
                    id       => $workflow->id,
                    activity => $activity,
                    param    => $key,
                    value    => $params->{$key}
                },
                log => { priority => 'error', facility => 'workflow' },
            );
        }
        $result->{$key} = $params->{$key};
    }

    return $result;
}

=head2 execute_activity

Executes the named activity on the given workflow object.

See L<API command "execute_workflow_activity"|OpenXPKI::Server::API2::Plugin::Workflow::execute_workflow_activity/execute_workflow_activity>
for more details.

Returns an L<OpenXPKI::Workflow> object.

B<Positional parameters>

=over

=item * C<$workflow> I<Str> - workflow type / name

=item * C<$activity> I<Str> - workflow activity

=item * C<$async> I<Bool> - "background" execution: forks a new process.

=item * C<$wait> I<Bool> - wait for background execution to start (max. 15 seconds).

=back

=cut
sub execute_activity {
    my ($self, $wf, $activity, $async, $wait) = @_;
    ##! 2: 'execute activity ' . $activity

    # ASYNCHRONOUS - fork
    if ($async) {
        $self->_execute_activity_async($wf, $activity); # returns the background process PID
        if ($wait) {
            return $self->watch($wf); # wait and fetch updated workflow state
        }
        else {
            return $wf; # return old workflow state
        }
    }
    # SYNCHRONOUS
    else {
        $self->_execute_activity_sync($wf, $activity); # modifies the $workflow object (and so $updated_workflow)
        return $wf;
    }
}

=head2 _execute_activity_sync

Executes the named activity on the given workflow object.

Returns 0 on success and throws exceptions on errors.

B<Positional parameters>

=over

=item * C<$workflow> (Str) - workflow type / name

=item * C<$activity> (Str) - workflow activity

=back

=cut
sub _execute_activity_sync {
    my ($self, $workflow, $activity) = @_;
    ##! 4: 'start'

    my $log = CTX('log')->workflow;

    ##! 64: Dumper $workflow
    OpenXPKI::Server::__set_process_name("workflow: id %d", $workflow->id());
    # run activity
    eval { $self->_run_activity($workflow, $activity) };

    if (my $eval_err = $EVAL_ERROR) {
       $log->error(sprintf ("Error executing workflow activity '%s' on workflow id %01d (type %s): %s",
            $activity, $workflow->id(), $workflow->type(), $eval_err));

        OpenXPKI::Server::__set_process_name("workflow: id %d (exception)", $workflow->id());

        my $logcfg = { priority => 'error', facility => 'workflow' };

        # clear MDC
        Log::Log4perl::MDC->put('wfid', undef);
        Log::Log4perl::MDC->put('wftype', undef);

        ## normal OpenXPKI exception
        $eval_err->rethrow() if (ref $eval_err eq "OpenXPKI::Exception");

        ## workflow exception
        my $error = $workflow->context->param('__error');
        if (defined $error) {
            if (ref $error eq '') {
                OpenXPKI::Exception->throw(
                    message => $error,
                    log     => $logcfg,
                );
            }
            if (ref $error eq 'ARRAY') {
                my @list = ();
                for my $item (@{$error}) {
                    eval {
                        OpenXPKI::Exception->throw(
                            message => $item->[0],
                            params  => $item->[1]
                        );
                    };
                    push @list, $EVAL_ERROR;
                }
                OpenXPKI::Exception->throw (
                    message  => "I18N_OPENXPKI_SERVER_API_EXECUTE_WORKFLOW_ACTIVITY_FAILED",
                    children => [ @list ],
                    log      => $logcfg,
                );
            }
        }

        ## unknown exception
        OpenXPKI::Exception->throw(
            message => "$eval_err", # stringify bubbled up exceptions
            log     => $logcfg,
        );
    };

    OpenXPKI::Server::__set_process_name("workflow: id %d (cleanup)", $workflow->id());
    return 0;
}

=head2 _execute_activity_async

Execute the named activity on the given workflow object ASYNCHRONOUSLY, i.e.
forks off a child process.

Returns the PID of the forked child.

B<Positional parameters>

=over

=item * C<$workflow> (Str) - workflow type / name

=item * C<$activity> (Str) - workflow activity

=back

=cut
sub _execute_activity_async {
    my ($self, $workflow, $activity) = @_;
    ##! 4: 'start'

    my $log = CTX('log')->workflow;

    $log->info(sprintf ("Executing workflow activity asynchronously. State %s in workflow id %01d (type %s)",
        $workflow->state(), $workflow->id(), $workflow->type()));

    # FORK
    my $pid = OpenXPKI::Daemonize->new->fork_child; # parent returns PID, child returns 0

    # parent process
    if ($pid > 0) {
        ##! 32: ' Workflow instance succesfully forked with pid ' . $pid
        $log->trace("Forked workflow instance with PID $pid") if $log->is_trace;
        return $pid;
    }

    # child process
    try {
        ##! 16: ' Workflow instance succesfully forked - I am the workflow'
        # append fork info to process name
        OpenXPKI::Server::__set_process_name("workflow: id %d (detached)", $workflow->id());

        # create memory-only session for workflow if it's not already one
        if (CTX('session')->type ne 'Memory') {
            my $session = OpenXPKI::Server::Session->new(type => "Memory")->create;
            $session->data->user( CTX('session')->data->user );
            $session->data->role( CTX('session')->data->role );
            $session->data->pki_realm( CTX('session')->data->pki_realm );

            OpenXPKI::Server::Context::setcontext({ session => $session, force => 1 });
            Log::Log4perl::MDC->put('sid', substr(CTX('session')->id,0,4));
        }

        # run activity
        $self->_run_activity($workflow, $activity);

        # DB commits are done inside the workflow engine
    }
    catch {
        # DB rollback is not needed as this process will terminate now anyway
        local $@ = $_; # makes OpenXPKI::Exception compatible with Try::Tiny
        if (my $exc = OpenXPKI::Exception->caught) {
            $exc->show_trace(1);
        }
        # make sure the cleanup code does not die as this would escape this method
        eval { CTX('log')->system->error($_) };
    };

    eval { CTX('dbi')->disconnect };

    ##! 16: 'Backgrounded workflow finished - exit child'
    exit;
}

# runs the given workflow activity on the Workflow engine
sub _run_activity {
    my ($self, $wf, $ac) = @_;
    ##! 8: 'start'

    my $log = CTX('log')->workflow;

    # This is a hack to handle simple "autorun" actions which we use to
    # create a bypass around optional actions
    do {
        my $last_state = $wf->state;
        $wf->execute_action($ac);

        my @action = $wf->get_current_actions();
        # A single possible action with a name starting with global_skip indicates
        # that we need the auto execute feature, the second part will (hopefully)
        # prevent infinite loops in case something goes wrong when running execute
        $ac = '';
        if (scalar @action == 1 and $action[0] =~ m{ \A global_skip }xs) {
            if ($last_state eq $wf->state && $ac eq $action[0]) {
                OpenXPKI::Exception->throw (
                    message  => "Loop found in auto bypass while executing workflow activity",
                    params   => {
                        state => $last_state, action => $ac, id => $wf->id, type => $wf->type
                    }
                );
            }
            $log->info(sprintf ("Found internal bypass action, leaving state %s in workflow id %01d (type %s)",
                $wf->state, $wf->id, $wf->type));

            $ac = $action[0];
        }
    } while($ac);
}

=head2 get_ui_info

Returns informations about a workflow from the workflow engine and the config
as a I<HashRef>:

    {
        workflow => {
                type        => ...,
                id          => ...,
                state       => ...,
                label       => ...,
                description => ...,
                last_update => ...,
                proc_state  => ...,
                count_try   => ...,
                wake_up_at  => ...,
                reap_at     => ...,
                context     => { ... },
                attribute   => { ... },   # only if "attribute => 1"
            },
            handles  => [ ... ],
            activity => { ... },
            state => {
                button => { ... },
                option => [ ... ],
                output => [ ... ],
            },
        }
    }

The workflow can be specified using an ID or an L<OpenXPKI::Server::Workflow>
object.

B<Named parameters>:

=over

=item * C<id> I<Int> - numeric workflow id

=item * C<workflow> I<OpenXPKI::Server::Workflow> - workflow object

=item * C<activity> I<Str> - only return informations about this workflow action.
Default: all actions available in the current state.

Note: you have to prepend the workflow prefix to the action separated by an
underscore.

=item * C<attribute> I<Bool> - set to 1 to get the extra attribute informations

=back

=cut
sub get_ui_info {
    my ($self, %args) = named_args(\@_,   # OpenXPKI::MooseParams
        id        => { isa => 'Int',  optional => 1 },
        workflow  => { isa => 'OpenXPKI::Server::Workflow', optional => 1 },
        attribute => { isa => 'Bool', optional => 1, default => 0 },
        activity  => { isa => 'Str',  optional => 1, },
    );
    ##! 2: 'start'

    die "Please specify either 'id' or 'workflow'" unless ($args{id} or $args{workflow});

    my $workflow = $args{workflow}
        ? $args{workflow}
        : CTX('workflow_factory')->get_workflow({ ID => $args{id} });

    my $type = $workflow->type;
    my $state = $workflow->state;
    my $head = CTX('config')->get_hash([ 'workflow', 'def', $type, 'head' ]);
    my $context = { %{$workflow->context->param } }; # make a copy
    my $result = {
        workflow => {
            type        => $type,
            id          => $workflow->id,
            state       => $state,
            label       => $head->{label},
            description => $head->{description},
            last_update => $workflow->last_update->iso8601,
            proc_state  => $workflow->proc_state,
            count_try   => $workflow->count_try,
            wake_up_at  => $workflow->wakeup_at,
            reap_at     => $workflow->reap_at,
            context     => $context,
            $args{attribute}
                ? ( attribute => $workflow->attrib)
                : (),
        },
        handles => $workflow->get_global_actions(),
    };

    # fetch actions of current state (or use given action)
    my @activities = $args{activity} ? ($args{activity}) : $workflow->get_current_actions();

    # additional infos
    my $add = $self->_get_config_details($workflow->factory, $result->{workflow}->{type}, $head->{prefix}, $state, \@activities, $context);
    $result->{$_} = $add->{$_} for keys %{ $add };

    return $result;
}

=head2 get_ui_base_info

Returns basic informations about a workflow type from the workflow config as a
I<HashRef>:

    {
        workflow => {
                type        => ...,
                id          => ...,
                state       => ...,
                label       => ...,
                description => ...,
            },
            activity => { ... },
            state => {
                button => { ... },
                option => [ ... ],
                output => [ ... ],
            },
        }
    }

B<Positional parameters>:

=over

=item * C<$type> I<Str> - workflow type

=back

=cut
sub get_ui_base_info {
    my ($self, $type) = @_;
    ##! 2: 'start'

    # TODO we might use the OpenXPKI::Workflow::Config object for this
    # Note: Using create_workflow shreds a workflow id and creates an orphaned entry in the history table
    my $factory = CTX('workflow_factory')->get_factory();

    if (not $factory->authorize_workflow({ ACTION => 'create', TYPE => $type })) {
        OpenXPKI::Exception->throw(
            message => 'User is not authorized to fetch workflow info',
            params => { type => $type }
        );
    }

    my $state = 'INITIAL';
    my $head = CTX('config')->get_hash([ 'workflow', 'def', $type, 'head' ]);
    my $result = {
        workflow => {
            type        => $type,
            id          => 0,
            state       => $state,
            label       => $head->{label},
            description => $head->{description},
        },
    };

    # fetch actions in state INITIAL from the config
    my $wf_config = $factory->_get_workflow_config($type);
    my @actions;
    for my $state (@{$wf_config->{state}}) {
        next unless $state->{name} eq 'INITIAL';
        @actions = ($state->{action}->[0]->{name});
        last;
    }

    # additional infos
    my $add = $self->_get_config_details($factory, $type, $head->{prefix}, $state, \@actions, undef);
    $result->{$_} = $add->{$_} for keys %{ $add };

    return $result;
}

# Returns a HashRef with configuration details (actions, states) of the given
# workflow type and state.
sub _get_config_details {
    my ($self, $factory, $type, $prefix, $state, $actions, $context) = @_;
    my $result = {};
    ##! 4: 'start'

    # add activities (= actions)
    $result->{activity} = {};

    OpenXPKI::Connector::WorkflowContext::set_context($context) if $context;
    for my $action (@{ $actions }) {
        $result->{activity}->{$action} = $factory->get_action_info($action, $type);
    }
    OpenXPKI::Connector::WorkflowContext::set_context() if $context;

    # add state UI info
    my $ui_state = CTX('config')->get_hash([ 'workflow', 'def', $type, 'state', $state ]);
    # replace hash key "output" with detailed field informations
    if ($ui_state->{output}) {
        my @output_fields = ref $ui_state->{output} eq 'ARRAY'
            ? @{ $ui_state->{output} }
            : CTX('config')->get_list([ 'workflow', 'def', $type, 'state', $state, 'output' ]);

        # query detailed field informations
        $ui_state->{output} = [ map { $factory->get_field_info($_, $type) } @output_fields ];
    }
    $result->{state} = $ui_state;

    # delete "action"
    delete $result->{state}->{action};

    # add button info
    my $button = $result->{state}->{button};
    $result->{state}->{button} = {};

    # possible options (=activity names) in the right order
    my @options = CTX('config')->get_scalar_as_list([ 'workflow', 'def', $type, 'state', $state, 'action' ]);

    # check defined actions and only list the possible ones
    # (non global actions are prefixed)
    $result->{state}->{option} = [];
    for my $option (@options) {
        $option =~ m{ \A (((global_)?)([^\s>]+))}xs;
        $option = $1;
        my $global = $3;
        my $option_base = $4;

        my $action = sprintf("%s_%s", $global ? "global" : $prefix, $option_base);
        ##! 16: 'Activity ' . $action
        ##! 64: 'Available actions ' . Dumper keys %{$result->{ACTIVITY}}
        push @{$result->{state}->{option}}, $action if $result->{activity}->{$action};

        # Add button config if available
        $result->{state}->{button}->{$action} = $button->{$option} if $button->{$option};
    }

    # add button markup (head)
    $result->{state}->{button}->{_head} = $button->{_head} if $button->{_head};

    return $result;
}
=head2 get_workflow_info

Return a hash with the informations taken from the workflow engine.

B<Positional parameters>:

=over

=item * C<$workflow> I<Workflow> - workflow object


=back

=cut
sub get_workflow_info {
    my ($self, $workflow) = @_;
    ##! 2: 'start'

    ##! 64: Dumper $workflow

    my $result = {
        workflow => {
            id          => $workflow->id(),
            state       => $workflow->state(),
            type        => $workflow->type(),
            description => $workflow->description(),
            last_update => $workflow->last_update()->iso8601(),
            proc_state  => $workflow->proc_state(),
            count_try   => $workflow->count_try(),
            wake_up_at  => $workflow->wakeup_at(),
            reap_at     => $workflow->reap_at(),
            attribute   => $workflow->attrib(),
            context     => { %{ $workflow->context->param } },
        },
    };

    # FIXME - this stuff seems to be unused and does not reflect the attributes
    # invented for the new ui stuff
    for my $activity ($workflow->get_current_actions()) {
        ##! 2: $activity

        # FIXME - bug in Workflow::Action (v0.17)?: if no fields are defined the
        # method tries to return an arrayref on an undef'd value
        my @fields;
        eval { @fields = $workflow->get_action_fields($activity) };

        for my $field (@fields) {
            ##! 4: $field->name()
            $result->{activity}->{$activity}->{field}->{$field->name()} = {
                description => $field->description(),
                required    => $field->is_required(),
            };
        }
    }

    return $result;
}

=head2 watch

Watch a workflow for changes based on the C<workflow_state>,
C<workflow_proc_state> and C<workflow_last_update> columns.

Expects the workflow object as parameter.

The method returns the changed workflow object if a change was detected
or the initial workflow object if no change happened after 15 seconds.

=cut
sub watch {
    my ($self, $workflow) = @_;

    my $timeout = time() + 15;
    ##! 16: 'Fork mode watch - timeout: '.$timeout

    my $orig_state = {
        'state'       => $workflow->state,
        'proc_state'  => $workflow->proc_state,
        'last_update' => $workflow->last_update->strftime("%Y-%m-%d %H:%M:%S"),
    };

    # loop till changes occur or time runs out
    do {
        my $state = CTX('dbi')->select_one(
            from => 'workflow',
            columns => [ qw( workflow_state workflow_proc_state workflow_last_update ) ],
            where => { 'workflow_id' => $workflow->id() },
        );

        if (
            $state->{workflow_state}       ne $orig_state->{state}      or
            $state->{workflow_proc_state}  ne $orig_state->{proc_state} or
            $state->{workflow_last_update} ne $orig_state->{last_update}
        ) {
            ##! 8: 'Refetch workflow'
            # refetch the workflow to get the updates
            my $factory = $workflow->factory();
            return $factory->fetch_workflow($workflow->type, $workflow->id);
        } else {
            ##! 64: 'sleep'
            sleep 2;
        }
    } while (time() < $timeout);

    # return original workflow if there were no changes
    return $workflow;
}

# Returns an instance of OpenXPKI::Server::Workflow
sub fetch_workflow {
    my ($self, $type, $id) = @_;
    ##! 2: 'start'

    my $factory = CTX('workflow_factory')->get_factory;

    #
    # Check workflow PKI realm and set type (if not given)
    #
    my $dbresult = CTX('dbi')->select_one(
        from => 'workflow',
        columns => [ qw( workflow_type pki_realm ) ],
        where => { workflow_id => $id },
    )
    or OpenXPKI::Exception->throw(
        message => 'Requested workflow not found',
        params  => { workflow_id => $id },
    );

    my $wf_type = $type // $dbresult->{workflow_type};

    # We can not load workflows from other realms as this will break config and security
    # The watchdog switches the session realm before instantiating a new factory
    if (CTX('session')->data->pki_realm ne $dbresult->{pki_realm}) {
        OpenXPKI::Exception->throw(
            message => 'Requested workflow is not in current PKI realm',
            params  => {
                workflow_id => $id,
                workflow_realm => $dbresult->{pki_realm},
                session_realm => ctx('session')->data->pki_realm,
            },
        );
    }

    #
    # Fetch workflow via Workflow engine
    #
    my $workflow = $factory->fetch_workflow($wf_type, $id);

    OpenXPKI::Server::Context::setcontext({
        workflow_id => $id,
        force       => 1,
    });

    return $workflow;
}

__PACKAGE__->meta->make_immutable;
