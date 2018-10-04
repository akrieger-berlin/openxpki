## OpenXPKI::Crypto::Tool::LibSCEP::Command::create_certificate_reply
## Written 2015-2018 by Gideon Knocke and Martin Bartosch for the OpenXPKI project
## (C) Copyright 2015-2018 by The OpenXPKI Project
package OpenXPKI::Crypto::Tool::LibSCEP::Command::create_certificate_reply;

use strict;
use warnings;
use English;

use Class::Std;
use Data::Dumper;

use OpenXPKI::Debug;
use Crypt::LibSCEP;
use MIME::Base64;

my %scep_handle_of   :ATTR;
my %cert_of          :ATTR;
my %engine_of        :ATTR;
my %enc_alg_of       :ATTR;
my %hash_alg_of      :ATTR;
my %fu_of            :ATTR;


sub START {
    my ($self, $ident, $arg_ref) = @_;

    $fu_of     {$ident}     = OpenXPKI::FileUtils->new();
    $engine_of {$ident}     = $arg_ref->{ENGINE};
    $scep_handle_of{$ident} = $arg_ref->{SCEP_HANDLE};
    $cert_of   {$ident}     = $arg_ref->{CERTIFICATE};
    $enc_alg_of{$ident}     = $arg_ref->{ENCRYPTION_ALG};
    $hash_alg_of {$ident}   = $arg_ref->{HASH_ALG};

}

sub get_result
{
    my $self = shift;
    my $ident = ident $self;

    if (! defined $engine_of{$ident}) {
        OpenXPKI::Exception->throw(
            message => 'I18N_OPENXPKI_CRYPTO_TOOL_LIBSCEP_COMMAND_CREATE_CERTIFICATE_REPLY_NO_ENGINE',
        );
    }
    ##! 64: 'engine: ' . Dumper($engine_of{$ident})
    my $keyfile  = $engine_of{$ident}->get_keyfile();
    if (! defined $keyfile || $keyfile eq '') {
        OpenXPKI::Exception->throw(
            message => 'I18N_OPENXPKI_CRYPTO_TOOL_LIBSCEP_COMMAND_CREATE_CERTIFICATE_REPLY_KEYFILE_MISSING',
        );
    }
    my $certfile = $engine_of{$ident}->get_certfile();
    if (! defined $certfile || $certfile eq '') {
        OpenXPKI::Exception->throw(
            message => 'I18N_OPENXPKI_CRYPTO_TOOL_LIBSCEP_COMMAND_CREATE_CERTIFICATE_REPLY_CERTFILE_MISSING',
        );
    }
    my $pwd    = $engine_of{$ident}->get_passwd();

    my $cert = $fu_of{$ident}->read_file($certfile);
    my $key = $fu_of{$ident}->read_file($keyfile);

    my $encalg = $enc_alg_of{$ident};
    if($encalg eq '3DES') {
        $encalg = 'des3';
    }
    my $sigalg = $hash_alg_of{$ident};
    my $issuedCert = $cert_of{$ident};
    my $transid;
    my $senderNonce;
    my $enc_cert;
    my $pending_reply;

    eval {
        $transid = Crypt::LibSCEP::get_transaction_id($scep_handle_of{$ident});
    };
    if($EVAL_ERROR) {
        OpenXPKI::Exception->throw(
            message => $EVAL_ERROR,
        );
    }
    eval {
        $senderNonce = Crypt::LibSCEP::get_senderNonce($scep_handle_of{$ident});
    };
    if($EVAL_ERROR) {
        OpenXPKI::Exception->throw(
            message => $EVAL_ERROR,
        );
    }
    eval{
        #yes, we use the signer cert for encryption
        $enc_cert = Crypt::LibSCEP::get_signer_cert($scep_handle_of{$ident});
    };
    if($EVAL_ERROR) {
        OpenXPKI::Exception->throw(
            message => $EVAL_ERROR,
        );
    }
    eval {
      $pending_reply = Crypt::LibSCEP::create_certificate_reply_wop7({passin=>"pass", passwd=>$pwd, sigalg=>$sigalg, encalg=>$encalg}, $key, $cert, $transid, $senderNonce, $enc_cert, $issuedCert);
    };
    if($EVAL_ERROR) {
        OpenXPKI::Exception->throw(
            message => $EVAL_ERROR,
        );
    }
    $pending_reply =~ s/\n?\z/\n/;
    $pending_reply =~ s/^(?:.*\n){1,1}//;
    $pending_reply =~ s/(?:.*\n){1,1}\z//;
    return decode_base64($pending_reply);
}

sub cleanup {

    my $self = shift;
    my $ident = ident $self;

    $fu_of{$ident}->cleanup();
}

1;
__END__
