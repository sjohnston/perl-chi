package CHI::Driver::Memory;
use Carp qw(cluck croak);
use Moose;
use strict;
use warnings;

extends 'CHI::Driver';

our $Global_Datastore = {};    ## no critic (ProhibitPackageVars)

has 'datastore' => ( is => 'ro', isa => 'HashRef' );
has 'global'    => ( is => 'ro', isa => 'Bool' );

__PACKAGE__->meta->make_immutable();

sub default_discard_policy { 'lru' }

sub BUILD {
    my ( $self, $params ) = @_;

    if ( $self->{global} ) {
        croak "cannot specify both 'datastore' and 'global'"
          if ( defined( $self->{datastore} ) );
        $self->{datastore} = $Global_Datastore;
    }
    if ( !defined( $self->{datastore} ) ) {
        cluck "must specify either 'datastore' hashref or 'global' flag";
        $self->{datastore} = $Global_Datastore;
    }
    $self->{datastore}->{ $self->namespace }->{values}   ||= {};
    $self->{datastore}->{ $self->namespace }->{metadata} ||= {};
    $self->_initialize_namespace_slots();
}

sub _initialize_namespace_slots {
    my ($self) = @_;

    $self->{datastore_for_namespace} = $self->{datastore}->{ $self->namespace };
    $self->{values_for_namespace} = $self->{datastore_for_namespace}->{values};
    $self->{metadata_for_namespace} =
      $self->{metadata_for_namespace}->{metadata};
}

sub fetch {
    my ( $self, $key ) = @_;

    if ( $self->is_size_aware() ) {
        $self->{metadata_for_namespace}->{last_used_time}->{$key} = time;
    }
    return $self->{values_for_namespace}->{$key};
}

sub store {
    my ( $self, $key, $data ) = @_;

    $self->{values_for_namespace}->{$key} = $data;
}

sub remove {
    my ( $self, $key ) = @_;

    delete $self->{values_for_namespace}->{$key};
    delete $self->{metadata_for_namespace}->{$key};
}

sub clear {
    my ($self) = @_;

    $self->{datastore}->{ $self->namespace } = {};
    $self->_initialize_namespace_slots();
}

sub get_keys {
    my ($self) = @_;

    return keys( %{ $self->{values_for_namespace} } );
}

sub get_namespaces {
    my ($self) = @_;

    return keys( %{ $self->{datastore} } );
}

sub discard_policy_lru {
    my ($self) = @_;

    my $last_used_time = $self->{metadata_for_namespace}->{last_used_time};
    my @keys_in_lru_order =
      sort { $last_used_time->{$a} <=> $last_used_time->{$b} } $self->get_keys;
    return sub {
        shift(@keys_in_lru_order);
    };
}

1;

__END__

=pod

=head1 NAME

CHI::Driver::Memory -- In-process memory based cache.

=head1 SYNOPSIS

    use CHI;

    my $hash = {};
    my $cache = CHI->new( driver => 'Memory', datastore => $hash );

    my $cache = CHI->new( driver => 'Memory', global => 1 );

=head1 DESCRIPTION

This cache driver stores data on a per-process basis.  This is the fastest of
the cache implementations, but data can not be shared between processes.  Data
will remain in the cache until cleared, expired, or the process dies.

To maintain the same semantics as other caches, data structures are deep-copied
on set and get. Thus, modifications to the original data structure will not
affect the data structure stored in the cache, and vica versa.

=head1 CONSTRUCTOR OPTIONS

When using this driver, the following options can be passed to CHI->new() in
addition to the L<CHI|general constructor options/constructor>. One of
I<datastore> or I<global> must be specified, or else a warning (possibly an
error eventually) will be thrown.

=over

=item datastore [HASH]

A hash to be used for storage. Within the hash, each namespace is used as a key
to a second-level hash.  This hash may be passed to multiple
CHI::Driver::Memory constructors.

For example, it can be useful to create a memory cache that lasts for a single
web request. If you using a web framework with a request object which goes out
of scope at the end of the page request, you can hang a datastore off of that
request object.  e.g.

    $r->notes('memory_cache_datastore', {});
    ...
    my $cache = CHI->new(driver => 'Memory', datastore => $r->notes('memory_cache_datastore'));

This eliminates the danger of "forgetting" to clear the cache at the end of the
request.

=item global [BOOL]

Use a standard global datastore. Multiple caches created with this flag will
see the same data. Before 0.21, this was the default behavior; now it must be
specified explicitly (to avoid accidentally sharing the same datastore in
unrelated code).

=back

=head1 DISCARD POLICY

For L<CHI/SIZE AWARENESS|size aware> caches, this driver implements an 'LRU'
policy, which discards the least recently used items first. This is the default
policy.

=head1 SEE ALSO

CHI

=head1 AUTHOR

Jonathan Swartz

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
