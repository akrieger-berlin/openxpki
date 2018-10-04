#!/usr/bin/perl

use lib qw(../lib);
use strict;
use warnings;
use JSON;
use English;
use Data::Dumper;
use Log::Log4perl qw(:easy);
use TestCGI;

use Test::More tests => 3;

package main;

my $result;
my $client = TestCGI::factory();

# create temp dir
-d "tmp/" || mkdir "tmp/";

$result = $client->mock_request({
    'page' => 'workflow!index!wf_type!certificate_signing_request_v2',
});

is($result->{main}->[0]->{content}->{fields}->[2]->{name}, 'wf_token');

$result = $client->mock_request({
    'action' => 'workflow!index',
    'wf_token' => undef,
    'cert_profile' => 'I18N_OPENXPKI_PROFILE_TLS_SERVER',
    'cert_subject_style' => '00_basic_style'
});

like($result->{goto}, qr/workflow!load!wf_id!\d+/, 'Got redirect');

my ($wf_id) = $result->{goto} =~ /workflow!load!wf_id!(\d+)/;

diag("Workflow Id is $wf_id");

$result = $client->mock_request({
    'page' => $result->{goto},
});

$result = $client->mock_request({
    'action' => 'workflow!select!wf_action!csr_upload_pkcs10!wf_id!'.$wf_id,
});

# Create the pkcs10
my $pkcs10 = `openssl req -new -subj "/CN=testbox.openxpki.org" -nodes -keyout /dev/null 2>/dev/null`;

$result = $client->mock_request({
    'action' => 'workflow!index',
    'pkcs10' => $pkcs10,
    'wf_token' => undef
});

$result = $client->mock_request({
    'action' => 'workflow!index',
    'cert_subject_parts{hostname}' => 'testbox.openxpki.org',
    'cert_subject_parts{hostname2}' => ['testbox.openxpki.net'],
    'wf_token' => undef
});

$result = $client->mock_request({
    'action' => 'workflow!index',
    'wf_token' => undef
});


$result = $client->mock_request({
    'action' => 'workflow!index',
    'cert_info{requestor_email}' => 'test@openxpki.local',
    'wf_token' => undef
});


# this is either submit or the link to enter a policy violation comment
$result = $client->mock_request({
    'action' => $result->{main}->[0]->{content}->{buttons}->[0]->{action}
});

if ($result->{main}->[0]->{content}->{fields} &&
    $result->{main}->[0]->{content}->{fields}->[0]->{name} eq 'policy_comment') {

    $result = $client->mock_request({
        'action' => 'workflow!index',
        'policy_comment' => 'Testing',
        'wf_token' => undef
    });
};

$result = $client->mock_request({
    'action' => 'workflow!select!wf_action!csr_approve_csr!wf_id!' . $wf_id,
});


is ($result->{status}->{level}, 'success', 'Status is success');

my $cert_identifier = $result->{main}->[0]->{content}->{data}->[0]->{value}->{label};
$cert_identifier =~ s/\<br.*$//g;

# Download the certificate
$result = $client->mock_request({
     'page' => 'certificate!download!format!pem!identifier!'.$cert_identifier
});

open(CERT, ">tmp/entity12.id");
print CERT $cert_identifier;
close CERT;

open(CERT, ">tmp/entity12.crt");
print CERT $result ;
close CERT;

