#!/usr/bin/perl
#
# Test if a background workflow (i.e. forking) works in conjunction with a
# workflow action that calls Proc::SafeExec.
# Previously, there have been problems with SIGCHLD, see Github issue #517.
#
use strict;
use warnings;

# Core modules
use English;
use FindBin qw( $Bin );

# CPAN modules
use Test::More;
use Test::Deep;
use Test::Exception;
use DateTime;

# Project modules
use lib "$Bin/lib", "$Bin/../lib", "$Bin/../../core/server/t/lib";
use OpenXPKI::Test;


# plan tests => 14; WE CANNOT PLAN tests as there is a while loop that sends commands (which are tests)


#
# Setup test context
#
sub workflow_def {
    my ($name) = @_;
    (my $cleanname = $name) =~ s/[^0-9a-z]//gi;
    return {
        'head' => {
            'label' => $name,
            'persister' => 'OpenXPKI',
            'prefix' => $cleanname,
        },
        'state' => {
            'INITIAL' => {
                'action' => [ 'initialize > BACKGROUNDING' ],
            },
            'BACKGROUNDING' => {
                'autorun' => 1,
                'action' => [ 'pause_before_fork > LOITERING' ],
            },
            'LOITERING' => {
                'autorun' => 1,
                'action' => [ 'do_something > SUCCESS' ],
            },
            'SUCCESS' => {
                'label' => 'I18N_OPENXPKI_UI_WORKFLOW_SET_MOTD_SUCCESS_LABEL',
                'description' => 'I18N_OPENXPKI_UI_WORKFLOW_SET_MOTD_SUCCESS_DESCRIPTION',
                'output' => [ 'message', 'link', 'role' ],
            },
            'FAILURE' => {
                'label' => 'Workflow has failed',
            },
        },
        'action' => {
            'initialize' => {
                'class' => 'OpenXPKI::Server::Workflow::Activity::Noop',
                'label' => 'I18N_OPENXPKI_UI_WORKFLOW_ACTION_MOTD_INITIALIZE_LABEL',
                'description' => 'I18N_OPENXPKI_UI_WORKFLOW_ACTION_MOTD_INITIALIZE_DESCRIPTION',
            },
            'do_something' => {
                'class' => 'OpenXPKI::Test::Is13Prime',
            },
            'pause_before_fork' => {
                'class' => 'OpenXPKI::Server::Workflow::Activity::Tools::Disconnect',
                'param' => { 'pause_info' => 'We want this to be picked up by the watchdog' },
            },
        },
        'field' => {},
        'validator' => {},
        'acl' => {
            'CA Operator' => { creator => 'any', techlog => 1, history => 1 },
        },
    };
};

my $oxitest = OpenXPKI::Test->new(
    with => [ "SampleConfig", "Server", "Workflows" ],
    also_init => "crypto_layer",
    start_watchdog => 1,
    add_config => {
        "realm.ca-one.workflow.def.wf_type_1" => workflow_def("wf_type_1"),
    },
);

my $tester = $oxitest->new_client_tester;
$tester->login("ca-one" => "caop");

sub wait_for_proc_state {
    my ($wfid, $state_regex) = @_;
    my $testname = "Waiting for workflow state $state_regex";
    my $result;
    my $count = 0;
    while ($count++ < 20) {
        $result = $tester->send_command_ok("search_workflow_instances" => { SERIAL => [ $wfid ] });
        # no workflow found?
        if ($result->[0]->{'WORKFLOW.WORKFLOW_SERIAL'} != $wfid) {
            diag "Workflow with ID $wfid not found!";
            fail $testname;
            return;
        }
        # wait if paused (i.e. resuming in progress) or still running (the remaining steps)
        if (not $result->[0]->{'WORKFLOW.WORKFLOW_PROC_STATE'} =~ $state_regex) {
            sleep 1;
            next;
        }
        # expected proc state reached
        return $result;
    }
    return;
}
my $result;

lives_and {
    $result = $tester->send_command_ok("create_workflow_instance" => {
        WORKFLOW => "wf_type_1",
        PARAMS => {},
    });
} "create_workflow_instance()";

my $wf_t1_a = $result->{WORKFLOW};

##diag explain OpenXPKI::Workflow::Config->new->workflow_config;

#
# wait for wakeup by watchdog
#
note "waiting for backgrounded (forked) workflow to finish";
$result = wait_for_proc_state $wf_t1_a->{ID}, qr/^(finished|exception)$/;

# compare result
cmp_deeply $result, [ superhashof({
    'WORKFLOW.WORKFLOW_SERIAL' => $wf_t1_a->{ID},
    'WORKFLOW.WORKFLOW_PROC_STATE' => 'finished', # could be 'exception' if things go wrong
    'WORKFLOW.WORKFLOW_STATE' => 'SUCCESS',
}) ], "Workflow finished successfully" or diag explain $result;

#
# get_workflow_info - check action results
#
lives_and {
    $result = $tester->send_command_ok("get_workflow_info" => { ID => $wf_t1_a->{ID} });
    cmp_deeply $result->{WORKFLOW}->{CONTEXT}->{is_13_prime}, 1;
} "Workflow action returns correct result";

#
# get_workflow_history - check correct execution history
#
lives_and {
    $result = $tester->send_command_ok("get_workflow_history" => { ID => $wf_t1_a->{ID} });
    cmp_deeply $result, [
        superhashof({ WORKFLOW_STATE => "INITIAL", WORKFLOW_ACTION => re(qr/create/i) }),
        superhashof({ WORKFLOW_STATE => "INITIAL", WORKFLOW_ACTION => re(qr/initialize/i) }),
        superhashof({ WORKFLOW_STATE => "BACKGROUNDING", WORKFLOW_ACTION => re(qr/pause_before_fork/i) }), # pause
        superhashof({ WORKFLOW_STATE => "BACKGROUNDING", WORKFLOW_ACTION => re(qr/pause_before_fork/i) }), # wakeup
        superhashof({ WORKFLOW_STATE => "BACKGROUNDING", WORKFLOW_ACTION => re(qr/pause_before_fork/i) }), # state change
        superhashof({ WORKFLOW_STATE => "LOITERING", WORKFLOW_ACTION => re(qr/do_something/i) }),
    ] or diag explain $result;
} "get_workflow_history()";

$oxitest->stop_server;

done_testing;

1;
