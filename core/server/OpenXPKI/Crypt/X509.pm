package OpenXPKI::Crypt::X509;

use strict;
use warnings;
use English;

use OpenXPKI::DN;
use Math::BigInt;
use Digest::SHA qw(sha1_base64 sha1_hex);
use OpenXPKI::DateTime;
use MIME::Base64;
use Moose;
use Crypt::X509;

has data => (
    is => 'ro',
    required => 1,
    isa => 'Str',
);

has pem => (
    is => 'ro',
    init_arg => undef,
    isa => 'Str',
    lazy => 1,
    default => sub {
        my $self = shift;
        # convert DER to PEM
        my $pem = encode_base64($self->data());
        $pem =~ s{\s}{}g;
        $pem =~ s{ (.{64}) }{$1\n}xmsg;
        return "-----BEGIN CERTIFICATE-----\n$pem\n-----END CERTIFICATE-----";
    },
);

has _cert => (
    is => 'ro',
    required => 1,
    isa => 'Crypt::X509',
);

has cert_identifier => (
    is => 'rw',
    init_arg => undef,
    isa => 'Str',
    reader => 'get_cert_identifier',
    lazy => 1,
    default => sub {
        my $self = shift;
        my $cert_identifier = sha1_base64($self->data);
        ## RFC 3548 URL and filename safe base64
        $cert_identifier =~ tr/+\//-_/;
        return $cert_identifier;
    },
);

has subject => (
    is => 'ro',
    init_arg => undef,
    isa => 'Str',
    reader => 'get_subject',
    lazy => 1,
    default => sub {
        my $self = shift;
        return join(',', reverse @{$self->_cert()->Subject});
    }
);

has subject_alt_name => (
    is => 'ro',
    init_arg => undef,
    isa => 'ArrayRef',
    reader => 'get_subject_alt_name',
    lazy => 1,
    builder => '_build_san'
);

has issuer => (
    is => 'ro',
    init_arg => undef,
    isa => 'Str',
    reader => 'get_issuer',
    lazy => 1,
    default => sub {
        my $self = shift;
        return join(',', reverse @{$self->_cert()->Issuer});
    }
);

has subject_key_id => (
    is => 'rw',
    init_arg => undef,
    isa => 'Str',
    reader => 'get_subject_key_id',
    lazy => 1,
    default => sub {
        my $self = shift;
        my $keyid = $self->_cert()->subject_keyidentifier();
        if ($keyid) {
            $keyid = unpack 'H*', $self->_cert()->subject_keyidentifier();
        } else {
            $keyid = sha1_hex( $self->_cert()->pubkey() );
        }
        return uc join ':', ( unpack '(A2)*', $keyid);
    }
);

has authority_key_id => (
    is => 'rw',
    init_arg => undef,
    isa => 'Str',
    reader => 'get_authority_key_id',
    lazy => 1,
    default => sub {
        my $self = shift;
        return uc join ':', ( unpack '(A2)*', ( unpack 'H*', $self->_cert()->key_identifier() ) );
    }
);

has notbefore => (
    is => 'ro',
    init_arg => undef,
    isa => 'Int',
    lazy => 1,
    default => sub {
        my $self = shift;
        return $self->_cert()->not_before();
    }
);

has notafter => (
    is => 'ro',
    init_arg => undef,
    isa => 'Int',
    lazy => 1,
    default => sub {
        my $self = shift;
        return $self->_cert()->not_after();
    }
);

has serial => (
    is => 'ro',
    init_arg => undef,
    isa => 'Str',
    reader => 'get_serial',
    lazy => 1,
    default => sub {
        my $self = shift;
        my $serial = $self->_cert()->serial;
        if (ref $serial eq 'Math::BigInt') {
            $serial = $serial->bstr();
        }
        return $serial;
    }
);


around BUILDARGS => sub {

    my $orig  = shift;
    my $class = shift;
    my $data = shift;

    if ($data =~ m{-----BEGIN[^-]*CERTIFICATE-----(.+)-----END[^-]*CERTIFICATE-----}xms ) {
        $data = decode_base64($1);
    }

    my $cert = Crypt::X509->new( cert => $data );
    if ($cert->error) {
        die $cert->error;
    }

    return $class->$orig( data => $data, _cert => $cert );

};

sub get_notbefore {
    my $self = shift;
    return $self->_get_validity( $self->notbefore(), shift );
}

sub get_notafter {
    my $self = shift;
    return $self->_get_validity( $self->notafter(), shift );
}

sub is_selfsigned {

    my $self = shift;
    # todo - calculate signature might be better
    if ($self->get_authority_key_id() && $self->get_subject_key_id()) {
        return $self->get_authority_key_id() eq $self->get_subject_key_id();
    }
    return $self->get_issuer eq $self->get_subject;

}

sub _build_san {

    my $self = shift;

    my $san_map = {
        otherName => 'otherName',
        rfc822Name => 'email',
        dNSName => 'DNS',
        x400Address => '', # not supported by openssl
        directoryName => 'dirName',
        ediPartyName => '', # not supported by openssl
        uniformResourceIdentifier => 'URI',
        iPAddress  => 'IP',
        registeredID => 'RID',
    };

    my @san_list;

    # List where eacht item is a string with "type=value"
    my $san_names = $self->_cert->SubjectAltName();

    # Walk all san lines
    foreach my $san (@$san_names) {
        my ($type, $value) = $san =~ m{\A(\w+)=(.+)\z};
        my $san_type = $san_map->{$type};
        next unless($san_type);
        push @san_list, [ $san_type, $value ];
    }

    return \@san_list;
}

sub _get_validity {
    my $self = shift;
    my $date = shift;
    my $format = shift || '';

    if ($format eq 'epoch') {
        return $date;
    }

    $date = DateTime->from_epoch( epoch => $date);

    if (!$format) {
        return $date;
    }

    return OpenXPKI::DateTime::convert_date({
        DATE      => $date,
        OUTFORMAT => $format,
    });
}

1;

__END__;
