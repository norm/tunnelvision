package Twitter::Filter::State;

use Modern::Perl;
use Moose::Role;
use MooseX::Method::Signatures;

use Config::Std;
use IO::All     -utf8;



method read_state ( Str $state_file! ) {
    my %state;
    
    $state_file = "state/$state_file";
    
    if ( ! -f $state_file ) {
        my $default_state = '# autocreated at ' . scalar( gmtime ) . "\n";
        $default_state > io( $state_file );
    }
    
    eval {
        read_config $state_file => %state;
    };
    if ( $@ ) {
        warn "read_state $state_file: $@";
    }
    
    return \%state;
}
method save_state ( HashRef $state? ) {
    if ( !defined $state ) {
        write_config %{ $self->{'_state'} };
    }
    else {
        write_config %{ $state };
    }    
}

1;
