package Twitter::Filter::Database;

use Modern::Perl;
use MooseX::FollowPBP;
use Moose;
use MooseX::Method::Signatures;

use DBD::SQLite;

has handle => (
        isa     => 'DBI::db',
        is      => 'ro',
        builder => 'build_handle',
    );

use constant USER_COLUMNS  => qw( id name screen_name friends_count
                                  profile_image_url profile_sidebar_fill_color 
                                  profile_sidebar_border_color url );
use constant TWEET_COLUMNS => qw( id user_id favorited truncated created_at
                                  in_reply_to_user_id in_reply_to_status_id
                                  in_reply_to_screen_name text source                        
                                  score seen );

method build_handle {
    my $db = DBI->connect( "dbi:SQLite:dbname=state/twilter.db", q(), q() );
    
    return $db;
}



method store_tweet ( HashRef $parcel ) {
    my $tweet = $parcel->{'tweet'};
    my $user  = $tweet->{'user'};
    
    $self->update_user_details( $user );
    $self->store_tweet_details( $tweet );
    $self->update_tweet_tags( $tweet->{'id'}, @{ $parcel->{'tags'} } );
    $self->update_tweet_buckets( $tweet->{'id'}, @{ $parcel->{'buckets'} } );
}


method update_user_details ( HashRef $user! ) {
    my $statement = $self->build_insert_from_array( 
            'user', 
            $user, 
            USER_COLUMNS
        );
    
    $statement->execute;
}
method store_tweet_details ( HashRef $tweet! ) {
    my @columns = TWEET_COLUMNS;
    
    $tweet->{'user_id'} = $tweet->{'user'}{'id'};
    push @columns, 'user_id';
    
    my $statement = $self->build_insert_from_array( 
            'tweet', 
            $tweet, 
            @columns
        );
    
    $statement->execute;
}
method update_tweet_tags ( Int $id, @tags ) {
    foreach my $tag ( @tags ) {
        my $statement = $self->build_insert_from_array(
                'tag',
                {
                    tweet_id => $id,
                    text => $tag,
                }
            );
        
        $statement->execute;
    }
}
method update_tweet_buckets ( Int $id, @buckets ) {
    foreach my $bucket ( @buckets ) {
        my $statement = $self->build_insert_from_array(
                'bucket',
                {
                    tweet_id => $id,
                    text => $bucket,
                }
            );
        
        $statement->execute;
    }
}


method build_insert_from_array ( Str $table!, HashRef $values!, @columns ) {
    my ( @values, @placeholders );
    
    # use entire hash unless columns specified
    if ( ! @columns ) {
        @columns = keys %{ $values };
    }
    
    foreach my $column ( @columns ) {
        push @values,       $values->{ $column };
        push @placeholders, '?';
    }
    
    my $insert_template = <<SQL;
        INSERT OR REPLACE 
            INTO        %s  (%s)
            VALUES          (%s)
SQL
    
    my $insert_command = sprintf $insert_template,
                            $table,
                            join( ',', @columns ),
                            join( ',', @placeholders );
    
    my $handle    = $self->get_handle();
    my $statement = $handle->prepare( $insert_command );
    
    my $count = 1;
    foreach my $value ( @values ) {
        $statement->bind_param( $count, $value );
        $count++;
    }
    
    return $statement;
}

1;
