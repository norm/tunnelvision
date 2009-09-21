package Twitter::Filter::Plugins;

use Modern::Perl;
use Moose::Role;
use MooseX::Method::Signatures;

use Config::Std;



method build_plugins ( Str :$dir!, Str :$method!, Str :$class! ) {
    my ( @plugins, @working_plugins );

    # find plugins in @INC
    foreach my $plugin ( $self->plugins() ) {
        push @plugins, $plugin;
    }

    # find plugins in the given directory
    foreach my $file ( glob "${dir}/*.pm" ) {
        require $file;

        $file =~ s{^ ${dir} / (.*) \.pm $}{$1}x;
        my $plugin = sprintf 
                         "%s::%s",
                             $class,
                             $file;
        push @plugins, $plugin;
    }

    foreach my $plugin ( @plugins ) {
        if ( $plugin->can( $method ) ) {
            push @working_plugins, $plugin;

            if ( $plugin->can( 'initialise' ) ) {
                $plugin->initialise();
            }
        }
        else {
            say STDERR "** ${plugin}: cannot ${method}";
        }
    }

    return \@working_plugins;
}

1;
