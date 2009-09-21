package Twitter::Filter::Classifier::Groups;

use Modern::Perl;

use Config::Std;
use File::stat;

my $timestamp = 0;
my %config;



sub classify {
    my $self       = shift;
    my $classifier = shift;
    my $tweet      = shift;
    
    my $config_file = $classifier->get_plugin_config_file();
    refresh_config_if_updated( $config_file );
    
    my $from = $tweet->{'user'}{'screen_name'};
    my @groups;
    my $score = 0;
    
    foreach my $group ( keys %config ) {
        my @users = get_group_members( $group );
        
        foreach my $user ( @users ) {
            if ( $user eq $from ) {
                push @groups, $group;
                $score += $config{ $group }{'score'} 
                       // 0;
            }
        }
    }
    
    return ( $score, @groups );
}
sub get_group_members {
    my $group = shift;
    my @users;
    
    my $user = $config{ $group }{'user'};
    if ( 'ARRAY' eq ref $user ) {
        push @users, @{ $config{ $group }{'user'} };
    }
    else {
        push @users, $config{ $group }{'user'};
    }
    
    return @users;
}
sub refresh_config_if_updated {
    my $file = shift;
    
    my $stat = stat( $file );
    
    if ( defined $stat ) {
        if ( $stat->mtime > $timestamp ) {
            read_config 'groups.conf' => %config;
        }
    }
}

1;
