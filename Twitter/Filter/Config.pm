package Twitter::Filter::Config;

use Modern::Perl;
use Moose::Role;
use MooseX::Method::Signatures;

use Config::Std;



method read_config_file ( Str $config_file! ) {
    my %config;
    
    eval {
        read_config $config_file => %config;
    };
    if ( $@ ) {
        warn "read_config: $@";
    }
    
    return \%config;
}
method read_global_config {
    return $self->read_config_file( 'conf/tunnelvision' );
}


method get_config ( Str $key!, Str $section = '' ) {
    my $config = $self->{'_config'};
    return $config->{ $section }{ $key };
}
method get_config_as_array ( Str $section!, Str $key! ) {
    my $config = $self->{'_config'};
    my $result = $config->{ $section }{ $key };
    my @results;
    
    if ( 'ARRAY' eq ref( $result ) ) {
        push @results, @{ $result };
    }
    else {
        push @results, $result;
    }
    
    return @results;
}
method set_config ( Str $section!, Str $key!, $value! ) {
    my $config = $self->{'_config'};
    $config->{ $section }{ $key } = $value;
}


method get_plugin_config_file {
    my $caller = caller(1);
    
    $caller =~ s{^ Twitter::Filter:: (Plugin::)? }{}x;
    $caller =~ s{::}{_};
    $caller =~ tr{A-Z}{a-z};
    
    return "conf/$caller";
}
method get_plugin_config {
    my $file = $self->get_plugin_config_file();
    
    # create the file if necessary
    if ( ! -f $file ) {
        my $handle = FileHandle->new( $file, 'w' );
    }
    
    return $self->read_config_file( $file );
}

method save_config {
    write_config %{ $self->{'_config'} };
}

1;
