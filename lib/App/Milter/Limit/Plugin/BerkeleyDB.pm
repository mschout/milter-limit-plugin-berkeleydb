# COPYRIGHT

package App::Milter::Limit::Plugin::BerkeleyDB;

# ABSTRACT: BerkeleyDB driver for App::Milter::Limit

use strict;
use warnings;
use base qw(App::Milter::Limit::Plugin Class::Accessor);

use App::Milter::Limit::Log;
use BerkeleyDB qw(DB_CREATE DB_INIT_MPOOL DB_INIT_CDB);

__PACKAGE__->mk_accessors(qw(_db));

sub init {
    my $self = shift;

    $self->init_defaults;

    App::Milter::Limit::Util::make_path($self->config_get('driver', 'home'));

    # db/env creation deferred until child_init
}

sub init_defaults {
    my $self = shift;

    $self->config_defaults('driver',
        home  => $self->config_get('global', 'state_dir'),
        file  => 'bdb-stats.db',
    );
}

# open BerkeleyDB handles in child_init handler.
sub child_init {
    my $self = shift;

    my $conf = App::Milter::Limit::Config->section('driver');

    my $env = BerkeleyDB::Env->new(
        -Home  => $$conf{home},
        -Flags => DB_CREATE | DB_INIT_MPOOL | DB_INIT_CDB)
            or die "failed to open BerkeleyDB env: $!";

    my $db = BerkeleyDB::Hash->new(
        -Filename => $$conf{file},
        -Env      => $env,
        -Flags    => DB_CREATE) or die "failed to open BerkeleyDB: $!";

    $self->_db($db);

    debug("BerkeleyDB connection initialized");
}

sub query {
    my ($self, $from) = @_;

    my $conf = App::Milter::Limit::Config->global;

    my $db = $self->_db;

    my $val;
    $db->db_get($from, $val);

    unless (defined $val) {
        # initialize new record for sender
        $val = join ':', time, 0;
    }

    my ($start, $count) = split ':', $val;

    # reset counter if it is expired
    if ($start < time - $$conf{expire}) {
        $count = 0;
        $start = time;
    }

    # update database for this sender.
    $val = join ':', $start, ++$count;
    $db->db_put($from, $val);

    return $count;
}

1;

__END__

=head1 SYNOPSIS

 my $milter = App::Milter::Limit->instance('BerkeleyDB');

=head1 DESCRIPTION

This module implements the L<App::Milter::Limit> backend using a BerkeleyDB data
store.

=head1 CONFIGURATION

The C<[driver]> section of the configuration file must specify the following items:

=over 4

=item home [optional]

The directory where the database files should be stored (default: C<state_dir> setting).

=item file [optional]

The database filename (default: C<bdb-stats.db>)

=item mode [optional]

The file mode for the database files (default: C<0644>).

=back

=begin Pod::Coverage

child_init
init_defaults

=end Pod::Coverage
