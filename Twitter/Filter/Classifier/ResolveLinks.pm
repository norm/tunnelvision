package Twitter::Filter::Classifier::ResolveLinks;
use base qw( Twitter::Filter::Classifier );

use Modern::Perl;
use LWP::UserAgent;
use URI::Find;

my $ua = LWP::UserAgent->new( max_redirect => 5 );



sub classify {
    my $class  = shift;
    my $filter = shift;
    my $tweet  = shift;
    my $tokens = shift;
    my @tags;
    
    my $finder = URI::Find->new(
            sub {
                my $object = shift;
                my $text   = shift;
                
                # figure out where the link points finally, then store the
                # hostname as a tag (e.g. for filtering against "youtube.com")
                my $head = $ua->head( $text );
                if ( $head->is_success() ) {
                    my $uri  = $head->request->uri;
                    my $host = $uri->host();
                    
                    # canonicalise www.youtube.com to youtube.com
                    $host =~ s{^www\.}{};
                    push @tags, "link:$host";
                    
                    # uncomment to replace short links in
                    # tweet with the resolved version
                    # return $uri;
                }
                return $text;
            }
        );
        
    $finder->find( \$tweet->{'text'} );
    
    return ( 0, @tags );
}

1;
