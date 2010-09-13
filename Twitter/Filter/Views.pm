package Twitter::Filter::Views;

use Modern::Perl;
use Moose::Role;
use MooseX::Method::Signatures;

use constant ROWS_PER_REQUEST => 50;
use constant DESIGN_DOCUMENT  => '_design/standard';



method get_standard_view ( Str $type, Str $option ) {
    $self->update_design_document_with_view( $type, $option );
    
    my $db      = $self->get_database();
    my $view_id = $self->get_view_id( $type, $option );
    my $results = $db->view(
            'standard',
            $view_id,
            {
                descending => 'false',
                limit      => ROWS_PER_REQUEST,
            }
        );
    
    my $more = $results->{'count'} > ROWS_PER_REQUEST;
    
    return( $results, $more );
}
method get_view_id ( Str $type, Str $option ) {
    return "${type}_${option}";
}
method update_design_document_with_view ( Str $type, Str $option ) {
    my $db = $self->get_database();
    my $view_code;
    
    given ( $type ) {
        when ( 'score' ) { 
            $view_code = $self->get_score_view_template( $option ) 
        }
        when ( 'tag' ) { 
            $view_code = $self->get_tag_view_template( $option ) 
        }
        when ( 'bucket' ) { 
            $view_code = $self->get_bucket_view_template( $option ) 
        }
        default {
            die "Unknown view type: $type";
        }
    }
    
    my $view_id = $self->get_view_id( $type, $option );
    my $doc     = $db->get_doc( DESIGN_DOCUMENT );
    my %design  = %$doc;
    
    $design{'views'}{ $view_id }{'map'} = $view_code;
    
    $self->update_if_changed( DESIGN_DOCUMENT, \%design );
}

method get_score_view_template ( Int $score ) {
    return <<"JAVASCRIPT";
        function( doc ) {
            if ( !doc.seen && doc.classified ) {
                if ( doc.score >= ${score} ) {
                    emit( doc.created, doc.id );
                }
            }
        }
JAVASCRIPT
}
method get_tag_view_template ( Str $tag ) {
    return <<"JAVASCRIPT";
        function( doc ) {
            if ( !doc.seen && doc.classified ) {
                for ( tag in doc.tags ) {
                    if ( '${tag}' == doc.tags[tag] ) {
                        emit( doc.created, doc.id );
                    }
                }
            }
        }
JAVASCRIPT
}
method get_bucket_view_template ( Str $bucket ) {
    return <<"JAVASCRIPT";
        function( doc ) {
            if ( !doc.seen && doc.classified ) {
                for ( bucket in doc.buckets ) {
                    if ( '${bucket}' == doc.buckets[bucket] ) {
                        emit( doc.created, doc.id );
                    }
                }
            }
        }
JAVASCRIPT
}

1;
