## OpenXPKI::Crypto::Tool::SCEP::Command::create_nextca_reply.pm
## (C) Copyright 2013 by The OpenXPKI Project
package OpenXPKI::Crypto::Tool::SCEP::Command::create_nextca_reply;

use strict;
use warnings;

use Class::Std;

use OpenXPKI::Debug;
use OpenXPKI::FileUtils;
use Data::Dumper;

my %fu_of      :ATTR; # a FileUtils instance
my %outfile_of :ATTR;
my %tmp_of     :ATTR;
my %chain_of   :ATTR;
my %engine_of  :ATTR;
my %hash_alg_of  :ATTR;

sub START {
    my ($self, $ident, $arg_ref) = @_;

    $fu_of    {$ident} = OpenXPKI::FileUtils->new();
    $engine_of{$ident} = $arg_ref->{ENGINE};
    $tmp_of   {$ident} = $arg_ref->{TMP};
    $chain_of {$ident} = $arg_ref->{CHAIN};
    $hash_alg_of {$ident} = $arg_ref->{HASH_ALG};
}

sub get_command {
    my $self  = shift;
    my $ident = ident $self;

    # keyfile, signcert, passin
    if (! defined $engine_of{$ident}) {
        OpenXPKI::Exception->throw(
            message => 'I18N_OPENXPKI_CRYPTO_TOOL_SCEP_COMMAND_CREATE_NEXTCA_REPLY_NO_ENGINE',
        );
    }
    ##! 64: 'engine: ' . Dumper($engine_of{$ident})
    my $keyfile  = $engine_of{$ident}->get_keyfile();
    if (! defined $keyfile || $keyfile eq '') {
        OpenXPKI::Exception->throw(
            message => 'I18N_OPENXPKI_CRYPTO_TOOL_SCEP_COMMAND_CREATE_NEXTCA_REPLY_KEYFILE_MISSING',
        );
    }
    my $certfile = $engine_of{$ident}->get_certfile();
    if (! defined $certfile || $certfile eq '') {
        OpenXPKI::Exception->throw(
            message => 'I18N_OPENXPKI_CRYPTO_TOOL_SCEP_COMMAND_CREATE_NEXTCA_REPLY_CERTFILE_MISSING',
        );
    }

    $ENV{pwd}    = $engine_of{$ident}->get_passwd();

    my $chain_filename = $fu_of{$ident}->get_safe_tmpfile({
        'TMP' => $tmp_of{$ident},
    });
    $outfile_of{$ident} = $fu_of{$ident}->get_safe_tmpfile({
        'TMP' => $tmp_of{$ident},
    });
    $fu_of{$ident}->write_file({
        FILENAME => $chain_filename,
        CONTENT  => $chain_of{$ident},
        FORCE    => 1,
    });

    my $command = " -new -passin env:pwd -signcert $certfile -msgtype GetNextCACert -keyfile $keyfile -nextCAfile $chain_filename -inform PEM -outform DER -out $outfile_of{$ident} ";

    if ($hash_alg_of{$ident}) {
        $command .= ' -'.$hash_alg_of{$ident};
    }

    ##! 16: 'scep cli ' . $command
    return $command;
}

sub hide_output
{
    return 0;
}

sub key_usage
{
    return 0;
}

sub get_result
{
    my $self = shift;
    my $ident = ident $self;

    my $pending_reply = $fu_of{$ident}->read_file($outfile_of{$ident});

    return $pending_reply;
}

sub cleanup {
    my $self = shift;
    my $ident = ident $self;

    $ENV{pwd} = '';
    $fu_of{$ident}->cleanup();
}

1;
__END__

=head1 Name

OpenXPKI::Crypto::Tool::SCEP::Command::create_nextca_reply

=head1 Functions

=head2 get_command

=over

=item * PKCS7

=back

=head2 hide_output

returns 0

=head2 key_usage

returns 0

=head2 get_result

Creates an SCEP PENDING reply.
