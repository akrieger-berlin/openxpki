package OpenXPKI::Server::API2::Plugin::Token::Util;
use Moose;

=head1 NAME

OpenXPKI::Server::API2::Plugin::Token::Util - Some utility functions for token
related API methods

=head1 METHODS

=cut

# Project modules
use OpenXPKI::Server::Context qw( CTX );

# CPAN modules
use Try::Tiny;



=head2 is_token_usable

Checks if the given token is usable by doing an encryption/decryption roundtrip.

Returns 1 if everything went fine, undef otherwise.

=cut
sub is_token_usable {
    my ($self, $token) = @_;

    try {
        CTX('log')->application()->debug('Check if token is usable using crypto operation');

        my $base = 'OpenXPKI Encryption Test';
        my $encrypted = $token->command({ COMMAND => 'pkcs7_encrypt', CONTENT => $base });
        my $decrypted = $token->command({ COMMAND => 'pkcs7_decrypt', PKCS7 => $encrypted });

        if ($decrypted ne $base) {
            OpenXPKI::Exception->throw (
                message => 'Mismatch after encrypt/decrypt roundtrip during token test',
                params => { token_backend_class => ref $token->get_instance }
            );
        }
    }
    catch {
        return;
    }

    return 1;
}

=head2 validity_to_epoch

Converts a I<HashRef> with a validity interval given as L<DateTime> objects into
a I<HashRef> with Unix epoch timestamps.

Expects undef or DateTime objects in a HashRef like this:

    {
        notbefore => DateTime->new(year => 1980, month => 12, day => 1),
        notafter => undef, # means: now
    }

and converts it to:

    {
        notbefore => 344476800,
        notafter => 1491328939,
    }

=cut
sub validity_to_epoch {
    my ($self, $validity) = @_;
    my $result = {};

    for my $key (qw(notbefore notafter) ) {
        my $value = $validity->{$key};
        OpenXPKI::Exception->throw(
            message => "Values in 'validity' must be specified as DateTime object (or set to 'undef')",
            params => { key => uc($key), type => blessed($value) },
        ) unless (not defined $value or (defined blessed($value) and $value->isa('DateTime')));
        $result->{$key} = $value ? $value->epoch : time;
    }

    return $result;
}

__PACKAGE__->meta->make_immutable;
