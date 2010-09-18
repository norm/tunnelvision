package Twitter::Filter;

use Modern::Perl;
use Moose;
use MooseX::FollowPBP;
use MooseX::Method::Signatures;

use Cache::FastMmap;
use Date::Manip;
use DB::CouchDB;
use Module::Pluggable::Ordered
        require => 1,
        search_path => [ 
            'Twitter::Filter::Classifier',
            'Twitter::Filter::Plugin',
        ];
use Net::Twitter;
use POSIX;
use Test::Deep::NoTest  qw( eq_deeply );
use Text::Wrap;

use constant FETCH_LISTS_AFTER => ( 12 * 60 * 60 );

with 'Twitter::Filter::Classify';
with 'Twitter::Filter::Config';
with 'Twitter::Filter::Views';

has database => (
        isa     => 'DB::CouchDB',
        is      => 'ro',
        builder => 'build_db_handle',
    );
has application => (
        isa => 'Str',
        is  => 'ro',
    );
has user => (
        isa => 'Str',
        is  => 'ro',
    );
has plugins => (
        isa => 'ArrayRef',
        is  => 'ro',
        builder => 'build_plugins',
    );
has classifiers => (
        isa => 'ArrayRef',
        is  => 'ro',
        builder => 'build_classifiers',
    );
has circulators => (
        isa => 'ArrayRef',
        is  => 'ro',
        builder => 'build_circulators',
    );
has twitter => (
        isa => 'Net::Twitter', 
        is  => 'rw' 
    );
has _config => (
        isa => 'HashRef',
        is => 'rw',
    );
has _cache => (
        isa     => 'Cache::FastMmap',
        is      => 'ro',
        builder => 'build_cache',
        handles => {
            cache_get    => 'get',
            cache_set    => 'set',
            cache_remove => 'get_and_remove',
        },
    );



method build_db_handle {
    my $db = DB::CouchDB->new( 
            host => 'localhost',
            db   => 'twitter',
        );
    $db->create_db();
    
    return $db;
}
method build_plugins {
    my @plugins;
    my @working;
    
    foreach my $plugin ( $self->plugins_ordered() ) {
        push @plugins, $plugin;
    }
    
    # TODO pass in configuration to plugins automatically
    PLUGIN:
    foreach my $plugin ( @plugins ) {
        if ( $plugin->can( 'initialise' ) ) {
            $plugin->initialise( $self )
                or next PLUGIN;
        }
        
        # only a working plugin if it successfully
        # initialises, or has no initialisation
        push @working, $plugin;
    }
    
    return \@working;
}
method build_classifiers {
    my @classifiers;
    
    foreach my $plugin ( @{ $self->get_plugins() } ) {
        if ( $plugin->can( 'classify' ) ) {
            push @classifiers, $plugin;
        }
    }
    
    return \@classifiers;
}
method build_circulators {
    my @circulators;
    
    foreach my $plugin ( @{ $self->get_plugins() } ) {
        if ( $plugin->can( 'circulate' ) ) {
            push @circulators, $plugin;
        }
    }
    
    return \@circulators;
}
method build_cache {
    return Cache::FastMmap->new(
            share_file     => 'state/shared.cache',
            expire_time    => '2h',
            cache_size     => '16m',
            init_file      => 0,
            unlink_on_exit => 0,
        );
}
method BUILD {
    $self->{'_config'} = $self->read_global_config();
    
    my $user   = $self->get_user()
              // $self->get_config( 'primary_user' );
    my $token  = $self->get_config( 'token', "user ${user}" );
    my $secret = $self->get_config( 'token_secret', "user ${user}" );
    
    # create twitter object
    my %options = (
            consumer_key        => $self->get_config( 'consumer_key' ),
            consumer_secret     => $self->get_config( 'consumer_secret' ),
            traits              => [
                'API::Lists',
                'API::REST',
                'API::Search',
                'OAuth',
                'WrapError',
            ],
        );
    if ( defined $token && defined $secret ) {
        $options{'access_token'}        = $token;
        $options{'access_token_secret'} = $secret;
    }
    
    $self->set_twitter( Net::Twitter->new( %options ) );
}
method DEMOLISH {
    $self->save_config();
}



method strip_tweet_user ( HashRef $tweet ) {
    my $user;
    my $body;
    
    # direct messages have a different format to a 'normal' tweet
    my $dm = $tweet->{'direct_message'};
    if ( defined $dm ) {
        $user = $dm->{'sender'};
        delete $dm->{'recipient'};
        delete $dm->{'sender'};
        $body = $dm;
    }
    else {
        $user = $tweet->{'user'};
        $body = $tweet;
        $body->{'sender_id'} = $body->{'user'}{'id'};
        delete $body->{'user'};
    }
    
    return( $user, $body );
}

method fetch_tweet ( Str $id, HashRef $extra_options ) {
    my $twitter = $self->get_twitter();
    
    my $tweet = $twitter->show_status( $id );
    my %tweet = (
            %$tweet,
            %$extra_options,
        );
    
    $self->save_tweet( \%tweet );
}
method save_tweet ( HashRef $tweet ) {
    my( $user, $body ) = $self->strip_tweet_user( $tweet );
    
    $self->update_user_document( $user );
    
    # fix things
    my $id      = $tweet->{'id'};
    my $created = $tweet->{'created_at'} // '';
    my $stamp   = UnixDate( $created, '%s' );
    $body->{'created'} = $stamp;
    
    if ( defined $id ) {
        $self->update_if_changed( $id, $body );
    }
    else {
        say "\nSAVE TWEET CALLED WITH INVALID CONTENT:";
        use Data::Dumper::Concise;
        print Dumper $tweet;
    }
}
method load_tweet ( Str $id ) {
    my $db = $self->get_database();
    
    my $doc = $db->get_doc( $id );
    my %doc = %$doc;
    return \%doc;
}

method tweet_as_text ( HashRef $tweet, $meta = '' ) {
    my( $screen, $name ) = $self->screen_name_from_tweet( $tweet );
    
    my $timestamp = $tweet->{'created'} // 0;
    my $time      = strftime '%R', localtime( $timestamp );
    
    if ( $meta ) {
        my $score   = $tweet->{'score'}   // 0;
        my $tags    = $tweet->{'tags'}    // [];
        my $buckets = $tweet->{'buckets'} // [];
        
        my $tags_str    = join ', ', @$tags;
        my $buckets_str = join ', ', @$buckets;
        
        $meta = sprintf " -- scored %02d %s %s",
                    $score,
                    $tags_str,
                    ( $buckets_str ? "{${buckets_str}}" : '' );
    }
    
    return "\@$screen [$name] $time$meta\n"
           . wrap( '      ', '      ', $tweet->{'text'} )
           . "\n\n";
}
method tweet_as_html ( HashRef $tweet, $meta = '', $include_replies=1 ) {
    my $db = $self->get_database();
    
    my $user_id = $tweet->{'sender_id'} // '';
    my $id      = "user_${user_id}";
    my $doc     = $db->get_doc( $id );
    
    my $avatar = $doc->{'profile_image_url'};
    my $screen = $doc->{'screen_name'};
    my $name   = $doc->{'name'};
    
    my $text        = $tweet->{'text'};
    my $timestamp   = $tweet->{'created'} // 0;
    my $time        = strftime '%d %b %R', localtime( $timestamp );
    my $reply_chain = '';
    
    if ( $include_replies ) {
        foreach my $reply ( $self->get_reply_to_chain( $tweet ) ) {
            $reply_chain .= $self->tweet_as_html( $reply, $meta, 0 );
        }
        
        $reply_chain = "<ul>${reply_chain}</ul>"
            if $reply_chain;
    }
    
    
    
    return <<HTML;
<li>
  <div>
      <span class='when'>${time}</span>
      <em><a href='http://twitter.com/${screen}'>
          <img src='${avatar}' width='48' height='48' alt=''>
          $name <span class='screen'>\@${screen}</span></em>
      </a>
      <span class='tweet'>${text}</span>
  </div>
  ${reply_chain}
</li>
HTML
}

method screen_name_from_tweet ( HashRef $tweet ) {
    my $name   = $tweet->{'name'}        // $tweet->{'user'}{'name'};
    my $screen = $tweet->{'screen_name'} // $tweet->{'user'}{'screen_name'};
    
    if ( !defined $name || !defined $screen ) {
        my $id = $tweet->{'sender_id'} // '';
        ( $screen, $name ) = $self->get_screen_name( $id );
    }
    
    return( $screen, $name );
}
method get_screen_name ( Str $id ) {
    return( 'ANON', 'Unknown user' )
        unless $id;
    
    my $db     = $self->get_database();
    my $doc_id = "user_${id}";
    my $doc    = $db->get_doc( $doc_id );
    
    # TODO check doc existed and contains keys
    return( $doc->{'screen_name'}, $doc->{'name'} );
}
method get_reply_to_chain ( HashRef $tweet ) {
    my $reply_to = $tweet->{'in_reply_to_status_id'};
    
    return
        unless defined $reply_to;
    
    my $doc      = $self->load_tweet( $reply_to );
    my @reply_to = $self->get_reply_to_chain( $doc );
    
    unshift @reply_to, $doc;
    return @reply_to;
}

method update_user_document ( HashRef $user ) {
    my $db      = $self->get_database();
    my $user_id = $user->{'id'};
    my $doc_id  = "user_${user_id}";
    my $doc     = $db->get_doc( $doc_id );
    
    # TODO refactor to use update_if_changed
    if ( $doc->err ) {
        $db->create_named_doc( $user, $doc_id );
    }
    else {
        my $count = $user->{'statuses_count'};
        delete $user->{'statuses_count'};
        
        my $changed = 0;
        foreach my $key ( keys %{$user} ) {
            my $new = $user->{ $key } // '';
            my $old = $doc->{ $key }  // '';
            
            $changed = 1 if $new ne $old;
        }
        if ( $changed ) {
            my %new_doc = (
                    %$doc,
                    %$user,
                );
            $db->update_doc( $doc_id, \%new_doc );
        }
        $self->update_user_statuses_count( $user_id, $count );
    }
}
method update_user_statuses_count ( Str $user, Str $count ) {
    # nothing right now
}

method get_twitter_lists {
    my $lists = $self->cache_get( 'twitter_lists' );
    
    if ( !defined $lists ) {
        say "[refetching lists]";
        
        my $twitter   = $self->get_twitter();
        my $user      = $self->get_config( 'primary_user' );
        my $get_lists = $twitter->get_lists( $user );
        my %lists;
        
        foreach my $list ( @{ $get_lists->{'lists'} } ) {
            my $slug    = $list->{'slug'};
            my $members = $twitter->list_members( $user, $list->{'id'} );
            
            foreach my $member ( @{ $members->{'users'} } ) {
                push @{ $lists{ $slug } }, $member->{'id'};
            }
        }
        
        $self->cache_set( 'twitter_lists', \%lists );
        $lists = $self->cache_get( 'twitter_lists' );
    }
    
    return %$lists;
}

method get_next_unclassified_tweet {
    # Get the next tweet that has yet to be classified.
    #
    # There are instances of random numbers used within this
    # function; this is to attempt to reduce the chances of
    # multiple classifiers running over the same tweet.
    
    my $db    = $self->get_database();
    my $count = 0;
    my $results;
    my $next;
    
    while ( $count == 0 ) {
        $results = $db->view( 
                'classifier',
                'unclassified',
                {
                    limit => 5,
                }
            );
        $count = scalar @{ $results->{'data'} };
        
        if ( $count == 0 ) {
            sleep int rand 15;
        }
        else {
            $next = int rand $count;
        }
    }
    
    return $results->{'data'}[$next]{'id'};
}
method get_next_uncirculated_tweet {
    # Get the next tweet that has yet to be circulated.
    #
    # There are instances of random numbers used within
    # this function, to attempt to reduce the chances of
    # multiple classifiers running over the same tweet.
    
    my $db    = $self->get_database();
    my $count = 0;
    my $results;
    my $next;
    
    while ( $count == 0 ) {
        $results = $db->view( 
                'classifier',
                'uncirculated',
                {
                    limit => 5,
                }
            );
        $count = scalar @{ $results->{'data'} };
        
        if ( $count == 0 ) {
            sleep int rand 15;
        }
        else {
            $next = int rand $count;
        }
    }
    
    return $results->{'data'}[$next];
}

method get_config_users {
    my @users;
    
    foreach my $key ( keys %{ $self->{'_config'} } ) {
        next unless $key =~ m{ ^ user \s+ (.*) $ }x;
        push @users, $1;
    }
    
    return @users;
}
method has_authorisation {
    my $twitter = $self->get_twitter();
    return $twitter->authorized();
}
method get_auth_url {
    my $twitter = $self->get_twitter();
    return $twitter->get_authorization_url();
}
method get_access_tokens ( Int $pin! ) {
    my $twitter = $self->get_twitter();
    return $twitter->request_access_token( verifier => $pin );
}

method update_document ( Str $id!, HashRef $state ) {
    my $db = $self->get_database();
    
    return $db->update_doc( $id, $state );
}
method add_to_document ( Str $id!, HashRef $added_state, Bool $create=0 ) {
    my $db  = $self->get_database();
    my $doc = $db->get_doc( $id );
    
    return $doc
        if $doc->err && !$create;
    
    my %new_doc = ( 
            %$doc,
            %$added_state,
        );
    
    return $self->update_if_changed( $id, \%new_doc );
}
method update_if_changed ( Str $id!, HashRef $state ) {
    my $db  = $self->get_database();
    my $doc = $db->get_doc( $id );
    
    if ( $doc->err ) {
        $doc = $db->create_named_doc( $state, $id );
    }
    else {
        # copy across the couchdb internal state as the client shouldn't
        # have to worry about preserving that part
        $state->{'_id'} = $doc->{'_id'};
        $state->{'_rev'} = $doc->{'_rev'};
        
        my %all_keys;
        $all_keys{$_}++ for keys %$state;
        $all_keys{$_}++ for keys %$doc;
        delete $all_keys{'_id'};
        delete $all_keys{'_rev'};
        
        my $changed = 0;
        foreach my $key ( keys %all_keys ) {
            $changed = 1 
                unless eq_deeply( $state->{$key}, $doc->{$key} );
        }
        
        $doc = $db->update_doc( $id, $state )
            if $changed;
    }
    
    return $doc;
}

1;




















