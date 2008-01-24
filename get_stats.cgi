#!/usr/bin/env /proj/sot/ska/bin/perl

use strict;
use warnings;
#use diagnostics;

#use Getopt::Long;

use Ska::SQL::Select;

#use CGI::Carp qw{ fatalsToBrowser };

use Ska::DatabaseUtil qw{ sql_connect };

use CGI qw{ :standard -no_undef_params};

#use Chandra::Time;

#use Data::Dumper;

my $app = new CGI;

# if there are any parameters
unless ($app->param()){
    no_ids();
}

sub no_ids{
    print $app->header(),     
    $app->start_html('Guide Stat Query');
    print "No AGASC ID requested \n";
    print "\n";                      
    print $app->end_html(), "\n";
    exit;
}

my %config = ( 'db_connect_info' => 'sybase-aca-aca_read',
	       'gs_table' => 'guide_stats_view',
	       'acq_table' => 'acq_stats_data',
	       );


my $param_href= $app->Vars;                                                                                                           
                                                                                                                                          
# I like the GET URL syntax, but I hate the undef params                                                                           
# let's strip them and redirect to a pretty URL                                                                                    
if ( has_null_param( $param_href ) ){                                                                                              
    strip_nulls( $param_href );                                                                                                    
    print $app->redirect( -url => $app->self_url );                                                                                
}                                                                                                                                  
else{                                                                                                                              
    unless (defined $param_href->{id}){
	no_ids();
    }
    my $stars = get_stars( $param_href->{id});
    my $star_table = star_table( $stars );
    print $app->header(),
          $app->start_html('Guide Stat Query');

    print $star_table, "\n";
    print $app->end_html;

}

sub star_table{
    my $stars = shift;
    my $acq_stars = $stars->{acq};
    my $gui_stars = $stars->{gui};

    # layout        agasc_id  obsid  obi slot mag_exp mag_obs  %goodornoid %badstatus d_yang d_zang  
    my @title = ( 'type', 'id', 'obsid', 'obi', 'slot', 'mag', 'mag_obs', '% bad track', '% obc bad stat', 'acq d_yang', 'acq_d_zang'); 
    my @acq_field =  ( 'type', 'agasc_id', 'obsid', 'obi', 'slot', 'mag' , 'mag_obs', 'obc_id', undef, 'd_yang', 'd_zang' );
    my @gui_field = ( 'type', 'id', 'obsid', 'obi', 'slot', 'mag_exp', 'mag_obs_mean', 'percent_not_tracking', 'percent_obc_bad_status', undef, undef );
    
    my $table = qq{ <TABLE BORDER=1> };
    $table .= qq{ <TR> };
    for my $title_field (@title){
	$table .= qq{ <TH>$title_field</TH> };
    }
    $table .= qq{ </TR> \n };
    for my $star (@{$acq_stars}){
	$star->{type} = 'ACQ';
    }
    for my $star (@{$gui_stars}){
	$star->{type} = 'GUI';
    }
    for my $star ( @{$acq_stars} , @{$gui_stars}){
	$table .= qq{ <TR> };
	for my $field_idx ( 0 ... $#title){
	    my $field = ( $star->{type} eq 'ACQ' ) ? $acq_field[$field_idx]
		        : ( $star->{type} eq 'GUI') ? $gui_field[$field_idx]  : undef;

	    if ( not defined $field or not defined $star->{$field} ){
		$table .= qq{ <TD></TD> };
		next;
	    }
	    my $value = $star->{$field};
	    if ($value =~ /\d*\.\d+/){
		$table .= sprintf( "<TD>%6.3f</TD>", $value );
		next;
	    }
	    $table .= qq{ <TD>$value</TD> };
	}
	$table .= qq{ </TR> \n };
    }
    $table .= qq{ </TABLE> };
    

}


sub get_stars{
    my $id = shift;

    my $handle = sql_connect( $config{db_connect_info} );

    my $acq_select = Ska::SQL::Select->new({  
	table => $config{acq_table}, 
	fields => ['*'], 
	order => ['tstart'],
	where => { agasc_id => $id },
    });


    my $acq_ref = $acq_select->run({handle => $handle, type => 'array'});
    

    my $gs_select = Ska::SQL::Select->new({  
	table => $config{gs_table}, 
	fields => ['*'], 
	order => ['kalman_tstart'],
	where => { id => $id },
    });
    
    
    my $gs_ref = $gs_select->run({handle => $handle, type => 'array'});

    my %stars = ( acq => $acq_ref,
		  gui => $gs_ref );a

    return \%stars;

}

sub has_null_param{

    my $param_href = shift;

    for my $key (keys %{$param_href}){
        if ($param_href->{$key} =~ /^$/){
	    return 1;
        }
    }
    return 0;
}
#
sub clear_params{
    my $param_href = shift;

    for my $key (keys %{$param_href}){
            delete $param_href->{$key};
    }
}
#    
#
sub strip_nulls{

    my $param_href = shift;

    for my $key (keys %{$param_href}){
        if ($param_href->{$key} =~ /^$/){
            delete $param_href->{$key};
        }
    }

}


