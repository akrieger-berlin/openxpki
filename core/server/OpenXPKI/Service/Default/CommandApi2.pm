package OpenXPKI::Service::Default::CommandApi2;
use Moose;

=head1 NAME

OpenXPKI::Service::Default::CommandApi2 - Execute commands via new API

=cut

# Project modules
use OpenXPKI::Exception;
use OpenXPKI::Server::API2;

=head1 DESCRIPTION

Default service command class to execute commands via the new API (API2).

=cut

has api => (
    is => 'rw',
    isa => 'OpenXPKI::Server::API2',
    lazy => 1,
    default => sub { OpenXPKI::Server::API2->new(enable_acls => 0) },
);

has command => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

has params => (
    is => 'ro',
    isa => 'HashRef',
    required => 1,
);


=head1 METHODS

=head2 new

Stores command and parameters for later execution via API.

B<Parameters>

=over

=item * C<command> I<Str> - API command name

=item * C<params> I<HashRef> - command parameters

=back

=head2 execute

Executes the command via API.

Returns a data structure that can be serialized and directly returned to the
client:

    {
        SERVICE_MSG => 'COMMAND',
        COMMAND => $command,
        PARAMS  => $api_call_result,
    }

=cut
sub execute {
    my $self = shift;
    return {
        SERVICE_MSG => 'COMMAND',
        COMMAND => $self->command,
        PARAMS  => $self->api->dispatch(
            command => $self->command,
            params  => $self->params,
        ),
    };
}

__PACKAGE__->meta->make_immutable;
